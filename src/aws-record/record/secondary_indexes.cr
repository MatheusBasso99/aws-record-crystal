require "./base"

# The key schema of a table or of one of its secondary indexes.
alias Aws::Record::KeySchema = Array(Aws::DynamoDB::Types::KeySchemaElement)

# A local or global secondary index declared on a model.
struct Aws::Record::IndexDefinition
  # The index name.
  getter name : String

  # The attribute name of the index's hash key.
  getter hash_key : String?

  # The attribute name of the index's range key, when it has one.
  getter range_key : String?

  # Which attributes the index copies from the table.
  getter projection : Aws::DynamoDB::Types::Projection?

  # Creates an index definition.
  def initialize(@name : String, @hash_key : String?, @range_key : String? = nil,
                 @projection : Aws::DynamoDB::Types::Projection? = nil) : Nil
  end
end

# Declaring a model's secondary indexes.
#
# The Ruby gem's `SecondaryIndexes` module; here these are macros and class methods of
# `Aws::Record::Base`. Both macros check, at compile time, that the attributes the index keys name
# have already been declared — the same requirement the Ruby gem enforces when the class body runs.
class Aws::Record::Base
  # Declares a local secondary index, which shares the table's hash key.
  #
  # ```
  # class Forum < Aws::Record::Base
  #   string_attr :forum_uuid, hash_key: true
  #   integer_attr :post_id, range_key: true
  #   string_attr :post_title
  #
  #   local_secondary_index :title, range_key: :post_title, projection: {projection_type: "ALL"}
  # end
  # ```
  macro local_secondary_index(name, **opts)
    {%
      visible = {} of Nil => Nil
      table_keys = {} of Nil => Nil
      @type.ancestors.select { |ancestor| ancestor.class? && ancestor.has_constant?(:ATTRIBUTE_DEFS) }
        .each do |ancestor|
          ancestor.constant(:ATTRIBUTE_DEFS).each { |key, value| visible[key] = value }
          ancestor.constant(:KEY_DEFS).each { |key, value| table_keys[key] = value }
        end
      ATTRIBUTE_DEFS.each { |key, value| visible[key] = value }
      KEY_DEFS.each { |key, value| table_keys[key] = value }

      unless opts[:range_key] && table_keys[:hash]
        raise "Local Secondary Indexes require a hash and range key!"
      end
      unless visible[opts[:range_key]]
        raise "#{opts[:range_key].id} not present in model attributes. Please ensure that " \
              "attributes are defined in the model class BEFORE defining an index on those attributes."
      end

      LSI_DEFS[name] = {
        hash_key:           table_keys[:hash],
        range_key:          opts[:range_key],
        projection:         opts[:projection],
        projection_type:    opts[:projection_type],
        non_key_attributes: opts[:non_key_attributes],
      }
    %}
  end

  # Declares a global secondary index, which has a hash key of its own.
  #
  # ```
  # class Forum < Aws::Record::Base
  #   string_attr :forum_uuid, hash_key: true
  #   string_attr :author_username
  #
  #   global_secondary_index :author, hash_key: :author_username, projection: {projection_type: "ALL"}
  # end
  # ```
  macro global_secondary_index(name, **opts)
    {%
      visible = {} of Nil => Nil
      @type.ancestors.select { |ancestor| ancestor.class? && ancestor.has_constant?(:ATTRIBUTE_DEFS) }
        .each { |ancestor| ancestor.constant(:ATTRIBUTE_DEFS).each { |key, value| visible[key] = value } }
      ATTRIBUTE_DEFS.each { |key, value| visible[key] = value }

      raise "Global Secondary Indexes require at least a hash key!" unless opts[:hash_key]

      missing = [] of Nil
      missing << opts[:hash_key] unless visible[opts[:hash_key]]
      missing << opts[:range_key] if opts[:range_key] && !visible[opts[:range_key]]
      unless missing.empty?
        raise "#{missing.map(&.id).join(", ").id} not present in model attributes. Please ensure " \
              "that attributes are defined in the model class BEFORE defining an index on those attributes."
      end

      GSI_DEFS[name] = {
        hash_key:           opts[:hash_key],
        range_key:          opts[:range_key],
        projection:         opts[:projection],
        projection_type:    opts[:projection_type],
        non_key_attributes: opts[:non_key_attributes],
      }
    %}
  end

  # This model's local secondary indexes, by name.
  def self.local_secondary_indexes : Hash(String, Aws::Record::IndexDefinition)
    {} of String => Aws::Record::IndexDefinition
  end

  # This model's global secondary indexes, by name.
  def self.global_secondary_indexes : Hash(String, Aws::Record::IndexDefinition)
    {} of String => Aws::Record::IndexDefinition
  end

  # This model's local secondary indexes in the shape `create_table` wants, or `nil` when it has none.
  def self.local_secondary_indexes_for_migration : Array(Aws::DynamoDB::Types::LocalSecondaryIndex)?
    indexes = local_secondary_indexes
    return if indexes.empty?
    indexes.map do |_name, index|
      Aws::DynamoDB::Types::LocalSecondaryIndex.new(
        index_name: index.name, key_schema: index_key_schema(index), projection: index.projection
      )
    end
  end

  # This model's global secondary indexes in the shape `create_table` wants, or `nil` when it has none.
  def self.global_secondary_indexes_for_migration : Array(Aws::DynamoDB::Types::GlobalSecondaryIndex)?
    indexes = global_secondary_indexes
    return if indexes.empty?
    indexes.map do |_name, index|
      Aws::DynamoDB::Types::GlobalSecondaryIndex.new(
        index_name: index.name, key_schema: index_key_schema(index), projection: index.projection
      )
    end
  end

  private def self.index_key_schema(index) : Aws::Record::KeySchema
    schema = Aws::Record::KeySchema.new
    index.hash_key.try do |name|
      schema << Aws::DynamoDB::Types::KeySchemaElement.new(
        key_type: "HASH", attribute_name: attributes.storage_name_for(name)
      )
    end
    index.range_key.try do |name|
      schema << Aws::DynamoDB::Types::KeySchemaElement.new(
        key_type: "RANGE", attribute_name: attributes.storage_name_for(name)
      )
    end
    schema
  end

  # :nodoc:
  #
  # Generates the index registries of one model. Called by `__aws_record_finalize`.
  macro __aws_record_finalize_indexes
    {%
      local = {} of Nil => Nil
      global = {} of Nil => Nil
      index_ancestors = @type.ancestors.select do |ancestor|
        ancestor.class? && ancestor.has_constant?(:LSI_DEFS)
      end
      (0...index_ancestors.size).each do |index|
        ancestor = index_ancestors[index_ancestors.size - 1 - index]
        ancestor.constant(:LSI_DEFS).each { |key, value| local[key] = value }
        ancestor.constant(:GSI_DEFS).each { |key, value| global[key] = value }
      end
      @type.constant(:LSI_DEFS).each { |key, value| local[key] = value }
      @type.constant(:GSI_DEFS).each { |key, value| global[key] = value }
    %}

    # :inherit:
    def self.local_secondary_indexes : Hash(String, Aws::Record::IndexDefinition)
      indexes = {} of String => Aws::Record::IndexDefinition
      {% for name, index in local %}
        {% projection = index[:projection] %}
        {% type = projection ? projection[:projection_type] : index[:projection_type] %}
        {% attributes = projection ? projection[:non_key_attributes] : index[:non_key_attributes] %}
        indexes[{{ name.id.stringify }}] = Aws::Record::IndexDefinition.new(
          {{ name.id.stringify }},
          {% if index[:hash_key] %}{{ index[:hash_key].id.stringify }}{% else %}nil{% end %},
          {% if index[:range_key] %}{{ index[:range_key].id.stringify }}{% else %}nil{% end %},
          {% if type || attributes %}
            Aws::DynamoDB::Types::Projection.new(projection_type: {{ type }}, non_key_attributes: {{ attributes }})
          {% else %}
            nil
          {% end %}
        )
      {% end %}
      indexes
    end

    # :inherit:
    def self.global_secondary_indexes : Hash(String, Aws::Record::IndexDefinition)
      indexes = {} of String => Aws::Record::IndexDefinition
      {% for name, index in global %}
        {% projection = index[:projection] %}
        {% type = projection ? projection[:projection_type] : index[:projection_type] %}
        {% attributes = projection ? projection[:non_key_attributes] : index[:non_key_attributes] %}
        indexes[{{ name.id.stringify }}] = Aws::Record::IndexDefinition.new(
          {{ name.id.stringify }},
          {% if index[:hash_key] %}{{ index[:hash_key].id.stringify }}{% else %}nil{% end %},
          {% if index[:range_key] %}{{ index[:range_key].id.stringify }}{% else %}nil{% end %},
          {% if type || attributes %}
            Aws::DynamoDB::Types::Projection.new(projection_type: {{ type }}, non_key_attributes: {{ attributes }})
          {% else %}
            nil
          {% end %}
        )
      {% end %}
      indexes
    end
  end
end
