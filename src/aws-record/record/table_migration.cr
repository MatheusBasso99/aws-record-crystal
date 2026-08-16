require "./base"
require "./errors"

# Creates, updates and deletes the DynamoDB table behind a model.
#
# ```
# migration = Aws::Record::TableMigration.new(Forum)
# migration.create!(
#   provisioned_throughput: Aws::DynamoDB::Types::ProvisionedThroughput.new(
#     read_capacity_units: 5, write_capacity_units: 2
#   )
# )
# migration.wait_until_available
# ```
#
# The attribute definitions and key schema come from the model, as do its secondary indexes.
class Aws::Record::TableMigration
  # The billing modes DynamoDB accepts.
  VALID_BILLING_MODES = ["PAY_PER_REQUEST", "PROVISIONED"]

  # The client this migration talks to.
  property client : Aws::DynamoDB::Client

  # Creates a migration for *model*.
  #
  # Raises `Errors::InvalidModel` when the model has no hash key, and so cannot back a table.
  def initialize(@model : Aws::Record::Base.class, client : Aws::DynamoDB::Client? = nil) : Nil
    @model.model_valid?
    @client = client || @model.dynamodb_client
    @client.config.add_user_agent_framework("aws-record")
  end

  # Creates the table.
  #
  # *global_secondary_index_throughput* gives each global secondary index its capacity, and is
  # required unless the table is billed per request. Every other option is passed to `create_table`.
  def create!(global_secondary_index_throughput : Hash(String, Aws::DynamoDB::Types::ProvisionedThroughput)? = nil,
              **opts) : Aws::DynamoDB::Types::CreateTableOutput
    validate_billing(**opts)
    definitions = attribute_definitions
    input = Aws::DynamoDB::Types::CreateTableInput.new(**opts).merge(
      table_name: @model.table_name, key_schema: key_schema
    )
    input = add_local_indexes(input, definitions)
    input = add_global_indexes(input, definitions, global_secondary_index_throughput, opts[:billing_mode]?)
    client.create_table(input.merge(attribute_definitions: definitions))
  end

  # Updates the table.
  #
  # Raises `Errors::TableDoesNotExist` when there is no such table.
  def update!(**opts) : Aws::DynamoDB::Types::UpdateTableOutput
    client.update_table(Aws::DynamoDB::Types::UpdateTableInput.new(**opts).merge(table_name: @model.table_name))
  rescue Aws::DynamoDB::Errors::ResourceNotFoundException
    raise Errors::TableDoesNotExist.new
  end

  # Deletes the table.
  #
  # Raises `Errors::TableDoesNotExist` when there is no such table.
  def delete! : Aws::DynamoDB::Types::DeleteTableOutput
    client.delete_table(table_name: @model.table_name)
  rescue Aws::DynamoDB::Errors::ResourceNotFoundException
    raise Errors::TableDoesNotExist.new
  end

  # Blocks until the table is `ACTIVE`.
  def wait_until_available : Aws::DynamoDB::Types::TableDescription
    client.wait_until_table_exists(@model.table_name)
  end

  private def validate_billing(**opts) : Nil
    billing_mode = opts[:billing_mode]?
    if billing_mode && !VALID_BILLING_MODES.includes?(billing_mode)
      raise ArgumentError.new(
        ":billing_mode option must be one of #{VALID_BILLING_MODES.join(", ")} " \
        "current value is: #{billing_mode}"
      )
    end
    if opts[:provisioned_throughput]?
      if billing_mode == "PAY_PER_REQUEST"
        raise ArgumentError.new(
          "when :provisioned_throughput option is specified, :billing_mode " \
          "must either be unspecified or have a value of 'PROVISIONED'"
        )
      end
    elsif billing_mode != "PAY_PER_REQUEST"
      raise ArgumentError.new(
        "when :provisioned_throughput option is not specified, " \
        ":billing_mode must be set to 'PAY_PER_REQUEST'"
      )
    end
  end

  private def key_schema : Array(Aws::DynamoDB::Types::KeySchemaElement)
    schema = [] of Aws::DynamoDB::Types::KeySchemaElement
    @model.keys.each do |role, name|
      schema << Aws::DynamoDB::Types::KeySchemaElement.new(
        attribute_name: @model.attributes.storage_name_for(name),
        key_type: role == :hash ? "HASH" : "RANGE"
      )
    end
    schema
  end

  private def attribute_definitions : Array(Aws::DynamoDB::Types::AttributeDefinition)
    definitions = [] of Aws::DynamoDB::Types::AttributeDefinition
    @model.keys.each_value do |name|
      attribute = @model.attributes.attribute_for(name)
      next unless attribute
      definitions << Aws::DynamoDB::Types::AttributeDefinition.new(
        attribute_name: attribute.database_name, attribute_type: attribute.dynamodb_type
      )
    end
    definitions
  end

  private def index_schema(index) : Array(Aws::DynamoDB::Types::KeySchemaElement)
    index.key_schema || [] of Aws::DynamoDB::Types::KeySchemaElement
  end

  private def append_definitions(definitions, key_schema) : Nil
    key_schema.each do |element|
      storage_name = element.attribute_name
      next unless storage_name
      next if definitions.any? { |definition| definition.attribute_name == storage_name }
      name = @model.attributes.db_to_attribute_name(storage_name)
      attribute = name ? @model.attributes.attribute_for(name) : nil
      next unless attribute
      definitions << Aws::DynamoDB::Types::AttributeDefinition.new(
        attribute_name: attribute.database_name, attribute_type: attribute.dynamodb_type
      )
    end
  end

  private def add_local_indexes(input, definitions) : Aws::DynamoDB::Types::CreateTableInput
    indexes = @model.local_secondary_indexes_for_migration
    return input unless indexes
    indexes.each { |index| append_definitions(definitions, index_schema(index)) }
    input.merge(local_secondary_indexes: indexes)
  end

  private def add_global_indexes(input, definitions, throughput, billing_mode) : Aws::DynamoDB::Types::CreateTableInput
    indexes = @model.global_secondary_indexes_for_migration
    return input unless indexes
    if !throughput && billing_mode != "PAY_PER_REQUEST"
      raise ArgumentError.new(
        "If you define global secondary indexes, you must also define " \
        ":global_secondary_index_throughput on table creation, " \
        "unless :billing_mode is set to 'PAY_PER_REQUEST'."
      )
    end
    indexes = with_throughput(indexes, throughput) if throughput && billing_mode != "PAY_PER_REQUEST"
    indexes.each { |index| append_definitions(definitions, index_schema(index)) }
    input.merge(global_secondary_indexes: indexes)
  end

  private def with_throughput(indexes, throughput) : Array(Aws::DynamoDB::Types::GlobalSecondaryIndex)
    missing = [] of String
    result = indexes.map do |index|
      name = index.index_name || ""
      capacity = throughput[name]?
      missing << name unless capacity
      index.merge(provisioned_throughput: capacity)
    end
    unless missing.empty?
      raise ArgumentError.new(
        "Missing provisioned throughput for the following global secondary " \
        "indexes: #{missing.join(", ")}. GSIs: #{indexes.map(&.index_name)} " \
        "and defined throughput: #{throughput.keys}"
      )
    end
    result
  end
end
