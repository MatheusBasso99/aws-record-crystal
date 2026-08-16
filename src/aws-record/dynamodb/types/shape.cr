require "json"
require "../attribute_value"

# Converts a single DynamoDB item between its wire form and `Aws::DynamoDB::Item`.
module Aws::DynamoDB::ItemConverter
  # Reads `{"id": {"N": "1"}}` into an `Aws::DynamoDB::Item`.
  def self.from_json(pull : JSON::PullParser) : Item
    AttributeValue.item_from_wire(JSON::Any.new(pull))
  end

  # Writes an `Aws::DynamoDB::Item` as `{"id": {"N": "1"}}`.
  def self.to_json(value : Item, builder : JSON::Builder) : Nil
    AttributeValue.item_to_wire(value).to_json(builder)
  end
end

# Converts a list of DynamoDB items between its wire form and `Array(Aws::DynamoDB::Item)`.
module Aws::DynamoDB::ItemListConverter
  # Reads `[{"id": {"N": "1"}}]` into an `Array(Aws::DynamoDB::Item)`.
  def self.from_json(pull : JSON::PullParser) : Array(Item)
    items = [] of Item
    pull.read_array { items << AttributeValue.item_from_wire(JSON::Any.new(pull)) }
    items
  end

  # Writes an `Array(Aws::DynamoDB::Item)` as `[{"id": {"N": "1"}}]`.
  def self.to_json(value : Array(Item), builder : JSON::Builder) : Nil
    builder.array { value.each { |item| AttributeValue.item_to_wire(item).to_json(builder) } }
  end
end

# Converts a table name to items map, as used by `BatchGetItem` responses.
module Aws::DynamoDB::ItemListMapConverter
  # Reads `{"Table": [{"id": {"N": "1"}}]}`.
  def self.from_json(pull : JSON::PullParser) : Hash(String, Array(Item))
    responses = Hash(String, Array(Item)).new
    pull.read_object { |table| responses[table] = ItemListConverter.from_json(pull) }
    responses
  end

  # Writes `{"Table": [{"id": {"N": "1"}}]}`.
  def self.to_json(value : Hash(String, Array(Item)), builder : JSON::Builder) : Nil
    builder.object do
      value.each do |table, items|
        builder.field(table) { ItemListConverter.to_json(items, builder) }
      end
    end
  end
end

# Behaviour shared by every DynamoDB request and response shape.
#
# Including `Shape` makes a struct `JSON::Serializable`, so that it *is* its own wire
# representation: field names are mapped to DynamoDB's PascalCase keys and `nil` fields are simply
# left out of the request. Declare the fields with `fields`, which also generates a keyword
# `initialize` where every field defaults to `nil`, plus `#merge` for the Ruby gem's
# `opts.merge(...)` pattern.
#
# ```
# struct Aws::DynamoDB::Types::DescribeTableInput
#   include Aws::DynamoDB::Types::Shape
#
#   fields(table_name : String?)
# end
#
# Aws::DynamoDB::Types::DescribeTableInput.new(table_name: "T").to_wire # => {"TableName" => "T"}
# ```
module Aws::DynamoDB::Types::Shape
  macro included
    include JSON::Serializable
  end

  # Declares the fields of a shape.
  #
  # Each declaration is a plain type declaration (`table_name : String?`). The DynamoDB wire key is
  # the field name in PascalCase, and item-valued fields get the converter that marshals them.
  macro fields(*decls)
    {%
      converters = {
        "Item"                      => "Aws::DynamoDB::ItemConverter",
        "Array(Item)"               => "Aws::DynamoDB::ItemListConverter",
        "Hash(String, Array(Item))" => "Aws::DynamoDB::ItemListMapConverter",
      }
    %}
    {% for decl in decls %}
      {% inner = decl.type.class_name == "Union" ? decl.type.types[0] : decl.type %}
      {% converter = converters[inner.stringify] %}
      {% if converter %}
        @[JSON::Field(key: {{ decl.var.stringify.camelcase }}, converter: {{ converter.id }})]
      {% else %}
        @[JSON::Field(key: {{ decl.var.stringify.camelcase }})]
      {% end %}
      getter {{ decl }}
    {% end %}

    def initialize(*, {% for decl in decls %}@{{ decl.var }} : {{ decl.type }} = nil, {% end %})
    end

    # The fields of this shape as a named tuple, in declaration order.
    def to_named_tuple
      { {% for decl in decls %}{{ decl.var }}: @{{ decl.var }}, {% end %} }
    end

    # Returns a copy of this shape with *overrides* applied.
    #
    # Naming a field that does not exist is a compile error, which is how the record layer's
    # pass-through options are checked.
    def merge(**overrides)
      self.class.new(**to_named_tuple.merge(overrides))
    end
  end

  # This shape in DynamoDB's wire form.
  def to_wire : JSON::Any
    JSON.parse(to_json)
  end
end
