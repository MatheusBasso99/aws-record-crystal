require "../dynamodb/client"
require "./client_configuration"
require "./errors"
require "./item_data"
require "./marshalers"
require "./model_attributes"
require "./raw_value"

# The base class of every `Aws::Record` model.
#
# Where the Ruby gem asks you to `include Aws::Record`, here you subclass:
#
# ```
# class Forum < Aws::Record::Base
#   string_attr :forum_uuid, hash_key: true
#   integer_attr :post_id, range_key: true
#   string_set_attr :tags
#   datetime_attr :created_at
# end
#
# post = Forum.new(forum_uuid: "abc", post_id: 1)
# post.created_at # => nil, typed as Time?
# ```
#
# Attributes are declared with the `*_attr` macros, which record them at compile time; the accessors,
# the attribute registry and the key metadata are generated once per class in `macro finished`.
#
# ### Inheritance
#
# A subclass inherits its parent's attributes and keys, and — when the parent set them explicitly —
# its table name, mutation tracking setting and DynamoDB client. Anything the subclass sets itself
# wins. An abstract intermediate class with no attributes is supported, and is the recommended way to
# share configuration across the models of an application:
#
# ```
# abstract class DynamoRecord < Aws::Record::Base
#   configure_client(region: "us-east-1")
# end
#
# class Session < DynamoRecord
#   string_attr :sid, hash_key: true
# end
# ```
abstract class Aws::Record::Base
  extend Aws::Record::ClientConfiguration

  # :nodoc:
  ATTRIBUTE_DEFS = {} of Nil => Nil

  # :nodoc:
  KEY_DEFS = {} of Nil => Nil

  # :nodoc:
  LSI_DEFS = {} of Nil => Nil

  # :nodoc:
  GSI_DEFS = {} of Nil => Nil

  @@table_name : String? = nil
  @@track_mutations : Bool? = nil
  @@definition : Aws::Record::ModelDefinition? = nil
  @@definition_mutex = Mutex.new

  @data : Aws::Record::ItemData

  macro inherited
    # :nodoc:
    ATTRIBUTE_DEFS = {} of Nil => Nil

    # :nodoc:
    KEY_DEFS = {} of Nil => Nil

    # :nodoc:
    LSI_DEFS = {} of Nil => Nil

    # :nodoc:
    GSI_DEFS = {} of Nil => Nil

    macro finished
      __aws_record_finalize
    end
  end

  # Declares an attribute with a marshaler of your own.
  #
  # *marshaler* may be a marshaler class, in which case the generated getter has that marshaler's
  # `Cast` type, or an already built marshaler, in which case the getter returns `RawValue`.
  macro attr(name, marshaler, **opts)
    __aws_record_attr(
      {{ name }}, {{ marshaler }}, {{ marshaler.is_a?(Path) }},
      {{ opts[:dynamodb_type] }}, false, {{ opts.double_splat }}
    )
  end

  # Declares a `String` attribute, stored as `S`.
  macro string_attr(name, **opts)
    __aws_record_attr({{ name }}, Aws::Record::Marshalers::StringMarshaler, true, "S", false, {{ opts.double_splat }})
  end

  # Declares a `Bool` attribute, stored as `BOOL`.
  macro boolean_attr(name, **opts)
    __aws_record_attr(
      {{ name }}, Aws::Record::Marshalers::BooleanMarshaler, true, "BOOL", false, {{ opts.double_splat }}
    )
  end

  # Declares an `Int64` attribute, stored as `N`.
  macro integer_attr(name, **opts)
    __aws_record_attr({{ name }}, Aws::Record::Marshalers::IntegerMarshaler, true, "N", false, {{ opts.double_splat }})
  end

  # Declares a `Float64` attribute, stored as `N`.
  macro float_attr(name, **opts)
    __aws_record_attr({{ name }}, Aws::Record::Marshalers::FloatMarshaler, true, "N", false, {{ opts.double_splat }})
  end

  # Declares a date attribute, read as a `Time` at midnight UTC and stored as `S` in `%F`.
  macro date_attr(name, **opts)
    __aws_record_attr({{ name }}, Aws::Record::Marshalers::DateMarshaler, true, "S", false, {{ opts.double_splat }})
  end

  # Declares a `Time` attribute stored as `S`, always with a numeric offset.
  macro datetime_attr(name, **opts)
    __aws_record_attr({{ name }}, Aws::Record::Marshalers::DateTimeMarshaler, true, "S", false, {{ opts.double_splat }})
  end

  # Declares a `Time` attribute stored as `S`, with `Z` for UTC.
  macro time_attr(name, **opts)
    __aws_record_attr({{ name }}, Aws::Record::Marshalers::TimeMarshaler, true, "S", false, {{ opts.double_splat }})
  end

  # Declares a `Time` attribute stored as `N` in epoch seconds, as DynamoDB's Time to Live expects.
  macro epoch_time_attr(name, **opts)
    __aws_record_attr(
      {{ name }}, Aws::Record::Marshalers::EpochTimeMarshaler, true, "N", false, {{ opts.double_splat }}
    )
  end

  # Declares a list attribute, stored as `L`.
  macro list_attr(name, **opts)
    __aws_record_attr({{ name }}, Aws::Record::Marshalers::ListMarshaler, true, "L", false, {{ opts.double_splat }})
  end

  # Declares a map attribute, stored as `M`.
  macro map_attr(name, **opts)
    __aws_record_attr({{ name }}, Aws::Record::Marshalers::MapMarshaler, true, "M", false, {{ opts.double_splat }})
  end

  # Declares a `Set(String)` attribute, stored as `SS`; an empty set is not persisted.
  macro string_set_attr(name, **opts)
    __aws_record_attr(
      {{ name }}, Aws::Record::Marshalers::StringSetMarshaler, true, "SS", false, {{ opts.double_splat }}
    )
  end

  # Declares a `Set(BigDecimal)` attribute, stored as `NS`; an empty set is not persisted.
  macro numeric_set_attr(name, **opts)
    __aws_record_attr(
      {{ name }}, Aws::Record::Marshalers::NumericSetMarshaler, true, "NS", false, {{ opts.double_splat }}
    )
  end

  # Declares an integer attribute that is incremented with `increment_<name>!`, without interfering
  # with other writers. It defaults to zero.
  macro atomic_counter(name, **opts)
    __aws_record_attr({{ name }}, Aws::Record::Marshalers::IntegerMarshaler, true, "N", true, {{ opts.double_splat }})
  end

  # :nodoc:
  macro __aws_record_attr(name, marshaler, marshaler_is_class, dynamodb_type, atomic, **opts)
    {% unless name.is_a?(SymbolLiteral) %}
      {% raise "Must use symbolized :name attribute, got #{name}" %}
    {% end %}
    {% if opts[:hash_key] && opts[:range_key] %}
      {% raise "Cannot have the same attribute be a hash and range key." %}
    {% end %}
    {% if ATTRIBUTE_DEFS[name] %}
      {% raise "Cannot overwrite existing attribute #{name.id} in #{@type}" %}
    {% end %}
    {%
      ATTRIBUTE_DEFS[name] = {
        marshaler:          marshaler,
        marshaler_is_class: marshaler_is_class,
        dynamodb_type:      dynamodb_type,
        opts:               opts,
        atomic:             atomic,
      }
    %}
    {% if opts[:hash_key] %}{% KEY_DEFS[:hash] = name %}{% end %}
    {% if opts[:range_key] %}{% KEY_DEFS[:range] = name %}{% end %}
  end

  # Sets a custom DynamoDB table name for this model.
  def self.set_table_name(name : String | Symbol) : Nil
    @@table_name = name.to_s
  end

  # The DynamoDB table name of this model; by default its class name, with `::` turned into `_`.
  def self.table_name : String
    "Aws_Record_Base"
  end

  # The table name this model was explicitly given, or `nil`.
  def self.explicit_table_name? : String?
    @@table_name
  end

  # This model's attributes and keys.
  def self.definition : Aws::Record::ModelDefinition
    Aws::Record::ModelDefinition.empty
  end

  # This model's attributes.
  def self.attributes : Aws::Record::ModelAttributes
    definition.attributes
  end

  # This model's keys.
  def self.key_attributes : Aws::Record::KeyAttributes
    definition.keys
  end

  # This model's keys, by role: `{:hash => "id", :range => "date"}`.
  def self.keys : Hash(Symbol, String)
    definition.keys.keys
  end

  # The name of this model's hash key attribute, or `nil`.
  def self.hash_key : String?
    definition.keys.hash_key
  end

  # The name of this model's range key attribute, or `nil`.
  def self.range_key : String?
    definition.keys.range_key
  end

  # The names of this model's attributes, in declaration order.
  def self.attribute_names : Array(String)
    definition.attributes.attributes.keys
  end

  # Turns off mutation tracking for every attribute of this model.
  def self.disable_mutation_tracking : Nil
    @@track_mutations = false
  end

  # Turns mutation tracking back on for every attribute of this model. It is on by default.
  def self.enable_mutation_tracking : Nil
    @@track_mutations = true
  end

  # Whether mutation tracking is enabled for this model.
  def self.mutation_tracking_enabled? : Bool
    @@track_mutations.nil? ? true : @@track_mutations == true
  end

  # Raises `Errors::InvalidModel` unless this model can back a DynamoDB table.
  def self.model_valid? : Nil
    raise Errors::InvalidModel.new("Table models must include a hash key") if hash_key.nil?
  end

  # The provisioned throughput of this model's remote table.
  #
  # Raises `Errors::TableDoesNotExist` when the table is not there.
  def self.provisioned_throughput : NamedTuple(read_capacity_units: Int64?, write_capacity_units: Int64?)
    throughput = dynamodb_client.describe_table(table_name: table_name).table.try(&.provisioned_throughput)
    {
      read_capacity_units:  throughput.try(&.read_capacity_units),
      write_capacity_units: throughput.try(&.write_capacity_units),
    }
  rescue Aws::DynamoDB::Errors::ResourceNotFoundException
    raise Errors::TableDoesNotExist.new
  end

  # Whether this model's table exists in DynamoDB and is `ACTIVE`.
  def self.table_exists? : Bool
    dynamodb_client.describe_table(table_name: table_name).table.try(&.table_status) == "ACTIVE"
  rescue Aws::DynamoDB::Errors::ResourceNotFoundException
    false
  end

  # Creates an item, optionally assigning attributes.
  #
  # Naming an attribute the model does not have is a compile error.
  def initialize(**attrs : **T) : Nil forall T
    @data = Aws::Record::ItemData.new(
      self.class.attributes, track_mutations: self.class.mutation_tracking_enabled?
    )
    {% for key in T.keys %}
      {% unless @type.has_method?(key.stringify + "=") %}
        {% raise "Invalid field: #{key} for #{@type}" %}
      {% end %}
      self.{{ key.id }} = attrs[{{ key.symbolize }}]
    {% end %}
  end

  # Assigns the given attributes to this item.
  #
  # Naming an attribute the model does not have is a compile error.
  def assign_attributes(**attrs : **T) : Nil forall T
    {% for key in T.keys %}
      {% unless @type.has_method?(key.stringify + "=") %}
        {% raise "Invalid field: #{key} for #{@type}" %}
      {% end %}
      self.{{ key.id }} = attrs[{{ key.symbolize }}]
    {% end %}
  end

  # Assigns the values of *item*, whose keys may be attribute names or DynamoDB storage names.
  #
  # This is how a response's `attributes` are folded back into an item. The Ruby gem only accepts
  # attribute names here, which breaks for attributes with a `database_attribute_name`.
  def assign_attributes(item : Aws::DynamoDB::Item) : Nil
    attributes = self.class.attributes
    item.each do |name, value|
      attribute = attributes.attribute_for(name)
      attribute ||= attributes.db_to_attribute_name(name).try { |resolved| attributes.attribute_for(resolved) }
      raise ArgumentError.new("Invalid field: #{name} for model") unless attribute
      @data.set_attribute(attribute.name, value)
    end
  end

  # The raw values of this item's attributes, by attribute name.
  def to_h : Hash(String, Aws::Record::RawValue)
    @data.hash_copy
  end

  # The names of this model's attributes, in declaration order.
  def attribute_names : Array(String)
    self.class.attribute_names
  end

  # Whether this item may be saved.
  #
  # Always `true`; override it — or include a validation library that does — to hook `#save` and
  # `#save!` the way the Ruby gem hooks ActiveModel's `valid?`.
  def valid? : Bool
    true
  end

  # The DynamoDB client this item's model is configured with.
  def dynamodb_client : Aws::DynamoDB::Client
    self.class.dynamodb_client
  end

  # :nodoc:
  macro __aws_record_finalize
    {% unless @type.has_constant?(:AWS_RECORD_FINALIZED) %}
      # :nodoc:
      AWS_RECORD_FINALIZED = true

      {% own = @type.constant(:ATTRIBUTE_DEFS) %}
      {% own_keys = @type.constant(:KEY_DEFS) %}
      {% parent = @type.superclass %}
      {% inherits_model = parent != Aws::Record::Base %}

      {% defs = {} of Nil => Nil %}
      {% keys = {} of Nil => Nil %}
      {% ancestors = @type.ancestors.select { |a| a.class? && a.has_constant?(:ATTRIBUTE_DEFS) } %}
      {% for index in 0...ancestors.size %}
        {% ancestor = ancestors[ancestors.size - 1 - index] %}
        {% for key, value in ancestor.constant(:ATTRIBUTE_DEFS) %}{% defs[key] = value %}{% end %}
        {% for key, value in ancestor.constant(:KEY_DEFS) %}{% keys[key] = value %}{% end %}
      {% end %}
      {% for key, value in own %}
        {% if defs[key] %}
          {% raise "Cannot overwrite existing attribute #{key.id} in #{@type}" %}
        {% end %}
        {% own_method = @type.has_method?(key.id.stringify) %}
        {% if own_method || @type.ancestors.any?(&.has_method?(key.id.stringify)) %}
          {% raise "Cannot name an attribute #{key.id} in #{@type}, " \
                   "that would collide with an existing instance method." %}
        {% end %}
        {% defs[key] = value %}
      {% end %}
      {% for key, value in own_keys %}{% keys[key] = value %}{% end %}

      {% storage = {} of Nil => Nil %}
      {% for key, value in defs %}
        {% custom = value[:opts][:database_attribute_name] %}
        {% name = custom == nil ? key.id.stringify : custom.id.stringify %}
        {% if storage[name] %}
          {% raise "Custom storage name #{name.id} already in use in #{@type}" %}
        {% end %}
        {% storage[name] = key.id.stringify %}
      {% end %}
      {% for key, value in defs %}
        {% owner = storage[key.id.stringify] %}
        {% if owner && owner != key.id.stringify %}
          {% raise "Custom storage name #{key.id} already exists as an attribute name in #{@type}" %}
        {% end %}
      {% end %}

      # :nodoc:
      def self.__aws_record_build_definition : Aws::Record::ModelDefinition
        model_attributes = Aws::Record::ModelAttributes.new
        {% for key, value in defs %}
          {% opts = value[:opts] %}
          {% has_default = opts.keys.map(&.stringify).includes?("default_value") %}
          {% default = opts[:default_value] %}
          {% marshaler_args = [] of Nil %}
          {% if opts[:formatter] %}
            {% marshaler_args << "formatter: #{opts[:formatter]}" %}
          {% end %}
          {% if opts[:use_local_time] != nil %}
            {% marshaler_args << "use_local_time: #{opts[:use_local_time]}" %}
          {% end %}
          model_attributes.register_attribute(
            Aws::Record::Attribute.new(
              {{ key.id.stringify }},
              {% if value[:marshaler_is_class] %}
                marshaler: {{ value[:marshaler] }}.new({{ marshaler_args.join(", ").id }}),
              {% else %}
                marshaler: {{ value[:marshaler] }},
              {% end %}
              {% if opts[:database_attribute_name] %}
                database_attribute_name: {{ opts[:database_attribute_name].id.stringify }},
              {% end %}
              {% if value[:dynamodb_type] %}dynamodb_type: {{ value[:dynamodb_type] }},{% end %}
              {% if opts[:persist_nil] %}persist_nil: true,{% end %}
              {% if has_default && default.is_a?(ProcLiteral) %}
                default_value_proc: Aws::Record::Attribute.default_proc { ({{ default }}).call },
              {% elsif has_default %}
                default_value: Aws::Record::RawValues.from({{ default }}), default_value_set: true,
              {% elsif value[:atomic] %}
                default_value: Aws::Record::RawValues.from(0), default_value_set: true,
              {% end %}
            )
          )
        {% end %}
        key_attributes = Aws::Record::KeyAttributes.new(model_attributes)
        {% if keys[:hash] %}key_attributes.hash_key = {{ keys[:hash].id.stringify }}{% end %}
        {% if keys[:range] %}key_attributes.range_key = {{ keys[:range].id.stringify }}{% end %}
        Aws::Record::ModelDefinition.new(model_attributes, key_attributes)
      end

      # This model's attributes and keys, built once and remembered.
      def self.definition : Aws::Record::ModelDefinition
        if existing = @@definition
          return existing
        end
        @@definition_mutex.synchronize do
          existing = @@definition
          existing || (@@definition = __aws_record_build_definition)
        end
      end

      # The DynamoDB table name of this model.
      def self.table_name : String
        if own = @@table_name
          return own
        end
        {% if inherits_model %}
          if inherited = {{ parent }}.explicit_table_name?
            return inherited
          end
        {% end %}
        {{ @type.name.stringify.gsub(/::/, "_") }}
      end

      # The table name this model, or a model it inherits from, was explicitly given.
      def self.explicit_table_name? : String?
        @@table_name{% if inherits_model %} || {{ parent }}.explicit_table_name?{% end %}
      end

      # Whether mutation tracking is enabled for this model.
      def self.mutation_tracking_enabled? : Bool
        own = @@track_mutations
        return own unless own.nil?
        {% if inherits_model %}{{ parent }}.mutation_tracking_enabled?{% else %}true{% end %}
      end

      # The DynamoDB client this model uses.
      def self.dynamodb_client : Aws::DynamoDB::Client
        if own = @@dynamodb_client
          return own
        end
        {% if inherits_model %}
          if inherited = {{ parent }}.explicit_dynamodb_client?
            return @@dynamodb_client = inherited
          end
        {% end %}
        configure_client
      end

      # The client this model, or a model it inherits from, was explicitly configured with.
      def self.explicit_dynamodb_client? : Aws::DynamoDB::Client?
        @@dynamodb_client{% if inherits_model %} || {{ parent }}.explicit_dynamodb_client?{% end %}
      end

      __aws_record_finalize_indexes

      {% for key, value in own %}
        {% name = key.id.stringify %}
        {% cast = value[:marshaler_is_class] ? "#{value[:marshaler]}::Cast".id : "Aws::Record::RawValue".id %}

        def {{ key.id }} : {{ cast }}
          {% if value[:marshaler_is_class] %}
            {{ value[:marshaler] }}.narrow(@data.get_attribute({{ name }}))
          {% else %}
            @data.get_attribute({{ name }})
          {% end %}
        end

        def {{ key.id }}=(value : _) : Nil
          @data.set_attribute({{ name }}, Aws::Record::RawValues.from(value))
        end

        def {{ key.id }}_dirty? : Bool
          @data.attribute_dirty?({{ name }})
        end

        def {{ key.id }}_dirty! : Nil
          @data.attribute_dirty!({{ name }})
        end

        def {{ key.id }}_was : {{ cast }}
          {% if value[:marshaler_is_class] %}
            {{ value[:marshaler] }}.narrow(@data.attribute_was({{ name }}))
          {% else %}
            @data.attribute_was({{ name }})
          {% end %}
        end

        def rollback_{{ key.id }}! : {{ cast }}
          {% if value[:marshaler_is_class] %}
            {{ value[:marshaler] }}.narrow(@data.rollback_attribute!({{ name }}))
          {% else %}
            @data.rollback_attribute!({{ name }})
          {% end %}
        end

        {% if value[:atomic] %}
          def increment_{{ key.id }}!(increment : Int = 1) : Int64
            increment_counter!({{ name }}, increment)
          end
        {% end %}
      {% end %}
    {% end %}
  end
end
