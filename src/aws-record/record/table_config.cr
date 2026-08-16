require "./base"
require "./errors"

# Declares what a model's table should look like, and brings the remote table in line with it.
#
# ```
# table_config = Aws::Record::TableConfig.define do |t|
#   t.model_class Forum
#   t.read_capacity_units 10
#   t.write_capacity_units 5
#   t.global_secondary_index(:title) do |i|
#     i.read_capacity_units 5
#     i.write_capacity_units 5
#   end
# end
#
# table_config.migrate! unless table_config.compatible?
# ```
#
# `#migrate!` creates the table when it is missing and otherwise applies the smallest set of updates
# that gets it there — DynamoDB needs separate calls for throughput and for index changes.
class Aws::Record::TableConfig
  # The capacity settings of one global secondary index.
  class GlobalSecondaryIndex
    # The capacity this index is configured with; every field is `nil` until one is set.
    getter provisioned_throughput : Aws::DynamoDB::Types::ProvisionedThroughput

    # Creates an index with no capacity set.
    def initialize : Nil
      @provisioned_throughput = Aws::DynamoDB::Types::ProvisionedThroughput.new
    end

    # Sets the index's read capacity.
    def read_capacity_units(units : Int) : Nil
      @provisioned_throughput = @provisioned_throughput.merge(read_capacity_units: units.to_i64)
    end

    # Sets the index's write capacity.
    def write_capacity_units(units : Int) : Nil
      @provisioned_throughput = @provisioned_throughput.merge(write_capacity_units: units.to_i64)
    end
  end

  # The client this configuration talks to.
  property client : Aws::DynamoDB::Client

  @model_class : (Aws::Record::Base.class)?
  @read_capacity_units : Int64?
  @write_capacity_units : Int64?
  @ttl_attribute : String?
  @billing_mode = "PROVISIONED"
  @global_secondary_indexes = {} of String => GlobalSecondaryIndex
  @client_builder : Proc(Aws::DynamoDB::Client)?

  # Builds a configuration with the DSL in the block, then builds its client.
  def self.define(& : TableConfig ->) : TableConfig
    config = new
    yield config
    config.configure_client
    config
  end

  # :nodoc:
  def initialize : Nil
    @client = uninitialized Aws::DynamoDB::Client
  end

  # Sets the model this table backs.
  def model_class(model : Aws::Record::Base.class) : Nil
    @model_class = model
  end

  # Sets the table's read capacity.
  def read_capacity_units(units : Int) : Nil
    @read_capacity_units = units.to_i64
  end

  # Sets the table's write capacity.
  def write_capacity_units(units : Int) : Nil
    @write_capacity_units = units.to_i64
  end

  # Configures the named global secondary index; the block sets its capacity.
  def global_secondary_index(name : String | Symbol, & : GlobalSecondaryIndex ->) : Nil
    index = GlobalSecondaryIndex.new
    yield index
    @global_secondary_indexes[name.to_s] = index
  end

  # :ditto:
  def global_secondary_index(name : String | Symbol) : Nil
    @global_secondary_indexes[name.to_s] = GlobalSecondaryIndex.new
  end

  # Sets the options the client is built with.
  def client_options(**opts) : Nil
    @client_builder = Proc(Aws::DynamoDB::Client).new { Aws::DynamoDB::Client.new(**opts) }
  end

  # Uses *client* as it is, instead of building one from `#client_options`.
  def client_options(client : Aws::DynamoDB::Client) : Nil
    @client_builder = Proc(Aws::DynamoDB::Client).new { client }
  end

  # Builds the client this configuration talks to.
  def configure_client : Nil
    builder = @client_builder
    @client = builder ? builder.call : Aws::DynamoDB::Client.new
    @client.config.add_user_agent_framework("aws-record")
  end

  # Marks the named attribute as the table's Time to Live attribute.
  #
  # Raises `ArgumentError` when the model has no such attribute.
  def ttl_attribute(name : String | Symbol) : Nil
    model = required_model
    attribute = model.attributes.attribute_for(name)
    raise ArgumentError.new("Invalid attribute #{name} for #{model}") unless attribute
    @ttl_attribute = attribute.database_name
  end

  # Sets the billing mode: `"PROVISIONED"` (the default) or `"PAY_PER_REQUEST"`.
  def billing_mode(mode : String) : Nil
    @billing_mode = mode
  end

  # Brings the remote table in line with this configuration, doing nothing when it already is.
  def migrate! : Nil
    validate_required_configuration
    model = required_model
    begin
      response = client.describe_table(table_name: model.table_name)
      apply_updates(response) unless compatible_check(response)
    rescue Aws::DynamoDB::Errors::ResourceNotFoundException
      client.create_table(create_table_input)
      client.wait_until_table_exists(model.table_name)
    end
    apply_ttl
  end

  # Whether the remote table has at least what this configuration asks for.
  #
  # Extra attribute definitions and extra global secondary indexes on the remote table are allowed,
  # which is what makes this friendly to single table inheritance.
  def compatible? : Bool
    response = client.describe_table(table_name: required_model.table_name)
    compatible_check(response) && ttl_compatibility_check?
  rescue Aws::DynamoDB::Errors::ResourceNotFoundException
    false
  end

  # Whether the remote table is exactly what this configuration asks for.
  def exact_match? : Bool
    response = client.describe_table(table_name: required_model.table_name)
    throughput_equal(response) && keys_equal(response) && attribute_definitions_equal(response) &&
      global_indexes_equal(response) && ttl_match_check?
  rescue Aws::DynamoDB::Errors::ResourceNotFoundException
    false
  end

  private def apply_updates(response) : Nil
    model = required_model
    # DynamoDB needs separate calls for throughput and for index changes.
    unless throughput_equal(response)
      client.update_table(update_throughput_input(response))
      client.wait_until_table_exists(model.table_name)
    end
    return if global_indexes_superset(response)
    client.update_table(update_index_input(response))
    client.wait_until_table_exists(model.table_name)
  end

  private def apply_ttl : Nil
    attribute = @ttl_attribute
    return unless attribute
    return if ttl_compatibility_check?
    client.update_time_to_live(
      table_name: required_model.table_name,
      time_to_live_specification: Aws::DynamoDB::Types::TimeToLiveSpecification.new(
        enabled: true, attribute_name: attribute
      )
    )
  end

  private def required_model : Aws::Record::Base.class
    model = @model_class
    raise Errors::MissingRequiredConfiguration.new("Missing: model_class") unless model
    model
  end

  private def validate_required_configuration : Nil
    missing = [] of String
    missing << "model_class" unless @model_class
    if @billing_mode == "PROVISIONED"
      missing << "read_capacity_units" unless @read_capacity_units
      missing << "write_capacity_units" unless @write_capacity_units
    elsif @read_capacity_units || @write_capacity_units
      raise ArgumentError.new("Cannot have billing mode #{@billing_mode} with provisioned capacity.")
    end
    return if missing.empty?
    raise Errors::MissingRequiredConfiguration.new("Missing: #{missing.join(", ")}")
  end

  private def table_throughput : Aws::DynamoDB::Types::ProvisionedThroughput
    Aws::DynamoDB::Types::ProvisionedThroughput.new(
      read_capacity_units: @read_capacity_units, write_capacity_units: @write_capacity_units
    )
  end

  private def create_table_input : Aws::DynamoDB::Types::CreateTableInput
    model = required_model
    input = Aws::DynamoDB::Types::CreateTableInput.new(table_name: model.table_name)
    input = case @billing_mode
            when "PROVISIONED"     then input.merge(provisioned_throughput: table_throughput)
            when "PAY_PER_REQUEST" then input.merge(billing_mode: @billing_mode)
            else                        raise ArgumentError.new("Unsupported billing mode #{@billing_mode}")
            end
    input = input.merge(key_schema: key_schema, attribute_definitions: attribute_definitions)
    indexes = configured_global_indexes
    indexes.empty? ? input : input.merge(global_secondary_indexes: indexes)
  end

  private def update_throughput_input(response) : Aws::DynamoDB::Types::UpdateTableInput
    model = required_model
    case @billing_mode
    when "PAY_PER_REQUEST"
      Aws::DynamoDB::Types::UpdateTableInput.new(table_name: model.table_name, billing_mode: @billing_mode)
    when "PROVISIONED"
      input = Aws::DynamoDB::Types::UpdateTableInput.new(
        table_name: model.table_name, provisioned_throughput: table_throughput
      )
      # Moving off per-request billing has to set the capacity of the existing indexes too.
      return input unless remote_billing_mode(response) == "PAY_PER_REQUEST"
      input = input.merge(billing_mode: @billing_mode)
      remote = remote_global_indexes(response)
      return input if remote.empty?
      input.merge(global_secondary_index_updates: remote.map { |index| index_throughput_update(index.index_name) })
    else
      raise ArgumentError.new("Unsupported billing mode #{@billing_mode}")
    end
  end

  private def index_throughput_update(name) : Aws::DynamoDB::Types::GlobalSecondaryIndexUpdate
    Aws::DynamoDB::Types::GlobalSecondaryIndexUpdate.new(
      update: Aws::DynamoDB::Types::UpdateGlobalSecondaryIndexAction.new(
        index_name: name,
        provisioned_throughput: @global_secondary_indexes[name.to_s]?.try(&.provisioned_throughput)
      )
    )
  end

  private def update_index_input(response) : Aws::DynamoDB::Types::UpdateTableInput
    updates, definitions = global_index_updates(response)
    input = Aws::DynamoDB::Types::UpdateTableInput.new(
      table_name: required_model.table_name, global_secondary_index_updates: updates
    )
    definitions.empty? ? input : input.merge(attribute_definitions: definitions)
  end

  private def global_index_updates(response)
    updates = [] of Aws::DynamoDB::Types::GlobalSecondaryIndexUpdate
    referenced = [] of String
    remote_names = remote_global_indexes(response).compact_map(&.index_name)
    local = configured_global_indexes

    local.each do |index|
      name = index.index_name || ""
      next if remote_names.includes?(name)
      index.key_schema.try(&.each { |element| element.attribute_name.try { |attr| referenced << attr } })
      updates << Aws::DynamoDB::Types::GlobalSecondaryIndexUpdate.new(
        create: Aws::DynamoDB::Types::CreateGlobalSecondaryIndexAction.new(
          index_name: index.index_name,
          key_schema: index.key_schema,
          projection: index.projection,
          provisioned_throughput: index.provisioned_throughput
        )
      )
    end

    if @billing_mode == "PROVISIONED"
      local.each do |index|
        name = index.index_name || ""
        updates << index_throughput_update(name) if remote_names.includes?(name)
      end
    end

    definitions = attribute_definitions
    incremental = referenced.compact_map do |name|
      definitions.find { |definition| definition.attribute_name == name }
    end
    {updates, incremental}
  end

  private def key_schema : Array(Aws::DynamoDB::Types::KeySchemaElement)
    model = required_model
    schema = [] of Aws::DynamoDB::Types::KeySchemaElement
    model.keys.each do |role, name|
      schema << Aws::DynamoDB::Types::KeySchemaElement.new(
        attribute_name: model.attributes.storage_name_for(name),
        key_type: role == :hash ? "HASH" : "RANGE"
      )
    end
    schema
  end

  private def attribute_definitions : Array(Aws::DynamoDB::Types::AttributeDefinition)
    model = required_model
    definitions = [] of Aws::DynamoDB::Types::AttributeDefinition
    model.keys.each_value { |name| add_definition(definitions, name) }
    model.global_secondary_indexes.each_value do |index|
      index.hash_key.try { |name| add_definition(definitions, name) }
      index.range_key.try { |name| add_definition(definitions, name) }
    end
    definitions
  end

  private def add_definition(definitions, name) : Nil
    attribute = required_model.attributes.attribute_for(name)
    return unless attribute
    return if definitions.any? { |definition| definition.attribute_name == attribute.database_name }
    definitions << Aws::DynamoDB::Types::AttributeDefinition.new(
      attribute_name: attribute.database_name, attribute_type: attribute.dynamodb_type
    )
  end

  private def configured_global_indexes : Array(Aws::DynamoDB::Types::GlobalSecondaryIndex)
    indexes = required_model.global_secondary_indexes_for_migration
    return [] of Aws::DynamoDB::Types::GlobalSecondaryIndex unless indexes
    return indexes unless @billing_mode == "PROVISIONED"
    indexes.map do |index|
      configured = @global_secondary_indexes[index.index_name.to_s]?
      index.merge(provisioned_throughput: configured.try(&.provisioned_throughput))
    end
  end

  private def remote_global_indexes(response) : Array(Aws::DynamoDB::Types::GlobalSecondaryIndex)
    response.table.try(&.global_secondary_indexes) || [] of Aws::DynamoDB::Types::GlobalSecondaryIndex
  end

  private def remote_billing_mode(response) : String?
    response.table.try(&.billing_mode_summary).try(&.billing_mode)
  end

  private def compatible_check(response) : Bool
    throughput_equal(response) && keys_equal(response) &&
      attribute_definitions_superset(response) && global_indexes_superset(response)
  end

  private def throughput_equal(response) : Bool
    if @billing_mode == "PAY_PER_REQUEST"
      return remote_billing_mode(response) == "PAY_PER_REQUEST"
    end
    remote = response.table.try(&.provisioned_throughput)
    return false unless remote
    (@read_capacity_units.nil? || remote.read_capacity_units == @read_capacity_units) &&
      (@write_capacity_units.nil? || remote.write_capacity_units == @write_capacity_units)
  end

  private def keys_equal(response) : Bool
    remote = response.table.try(&.key_schema) || [] of Aws::DynamoDB::Types::KeySchemaElement
    same_set?(remote, key_schema)
  end

  private def attribute_definitions_equal(response) : Bool
    remote = response.table.try(&.attribute_definitions) || [] of Aws::DynamoDB::Types::AttributeDefinition
    same_set?(remote, attribute_definitions)
  end

  private def attribute_definitions_superset(response) : Bool
    remote = response.table.try(&.attribute_definitions) || [] of Aws::DynamoDB::Types::AttributeDefinition
    attribute_definitions.all? { |definition| remote.includes?(definition) }
  end

  private def global_indexes_superset(response) : Bool
    remote = remote_global_indexes(response)
    local = configured_global_indexes
    remote_names = remote.compact_map(&.index_name).to_set
    local_names = local.compact_map(&.index_name).to_set
    return false unless local_names.subset_of?(remote_names)
    indexes_match?(remote, local)
  end

  private def global_indexes_equal(response) : Bool
    remote = remote_global_indexes(response)
    local = configured_global_indexes
    return false unless remote.compact_map(&.index_name).to_set == local.compact_map(&.index_name).to_set
    indexes_match?(remote, local)
  end

  private def indexes_match?(remote, local) : Bool
    local.all? do |index|
      counterpart = remote.find { |candidate| candidate.index_name == index.index_name }
      next false unless counterpart
      keys_match = same_set?(
        counterpart.key_schema || [] of Aws::DynamoDB::Types::KeySchemaElement,
        index.key_schema || [] of Aws::DynamoDB::Types::KeySchemaElement
      )
      keys_match && throughput_match?(counterpart, index) && projection_match?(counterpart, index)
    end
  end

  private def throughput_match?(remote, local) : Bool
    case @billing_mode
    when "PROVISIONED"
      wanted = local.provisioned_throughput
      return true unless wanted
      actual = remote.provisioned_throughput
      return false unless actual
      (wanted.read_capacity_units.nil? || actual.read_capacity_units == wanted.read_capacity_units) &&
        (wanted.write_capacity_units.nil? || actual.write_capacity_units == wanted.write_capacity_units)
    when "PAY_PER_REQUEST"
      local.provisioned_throughput.nil?
    else
      raise ArgumentError.new("Unsupported billing mode #{@billing_mode}")
    end
  end

  private def projection_match?(remote, local) : Bool
    normalize(remote.projection) == normalize(local.projection)
  end

  private def normalize(projection) : Tuple(String?, Array(String)?)
    return {nil, nil} unless projection
    {projection.projection_type, projection.non_key_attributes.try(&.sort)}
  end

  private def same_set?(left, right) : Bool
    left.all? { |element| right.includes?(element) } && right.all? { |element| left.includes?(element) }
  end

  private def ttl_description : Aws::DynamoDB::Types::TimeToLiveDescription?
    client.describe_time_to_live(table_name: required_model.table_name).time_to_live_description
  end

  private def ttl_compatibility_check? : Bool
    attribute = @ttl_attribute
    return true unless attribute
    description = ttl_description
    return false unless description
    ["ENABLED", "ENABLING"].includes?(description.time_to_live_status) &&
      description.attribute_name == attribute
  end

  private def ttl_match_check? : Bool
    description = ttl_description
    attribute = @ttl_attribute
    if attribute
      return false unless description
      ["ENABLED", "ENABLING"].includes?(description.time_to_live_status) &&
        description.attribute_name == attribute
    else
      return true unless description
      !["ENABLED", "ENABLING"].includes?(description.time_to_live_status) || description.attribute_name.nil?
    end
  end
end
