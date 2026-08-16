require "base64"
require "json"
require "./value"

# Converts between `Aws::DynamoDB::Value` and DynamoDB's wire representation of an attribute value.
#
# ```
# Aws::DynamoDB::AttributeValue.to_wire(1_i64)                       # => {"N" => "1"}
# Aws::DynamoDB::AttributeValue.from_wire(JSON.parse(%({"N": "1"}))) # => 1_i64
# ```
module Aws::DynamoDB::AttributeValue
  extend self

  # Serializes *value* to its wire form.
  def to_wire(value : Value) : JSON::Any
    case value
    in Nil, Bool, String, Int64, Float64, BigDecimal, Bytes
      scalar_to_wire(value)
    in Set(String), Set(BigDecimal), Set(Bytes)
      set_to_wire(value)
    in Array(Value)
      wrap("L", JSON::Any.new(value.map { |element| to_wire(element) }))
    in Hash(String, Value)
      wrap("M", item_to_wire(value))
    end
  end

  private def scalar_to_wire(value)
    case value
    in Nil
      wrap("NULL", JSON::Any.new(true))
    in Bool
      wrap("BOOL", JSON::Any.new(value))
    in String
      wrap("S", JSON::Any.new(value))
    in Int64, Float64, BigDecimal
      wrap("N", JSON::Any.new(value.to_s))
    in Bytes
      wrap("B", JSON::Any.new(Base64.strict_encode(value)))
    end
  end

  private def set_to_wire(value)
    case value
    in Set(String)
      wrap("SS", JSON::Any.new(value.map { |element| JSON::Any.new(element) }))
    in Set(BigDecimal)
      wrap("NS", JSON::Any.new(value.map { |element| JSON::Any.new(element.to_s) }))
    in Set(Bytes)
      wrap("BS", JSON::Any.new(value.map { |element| JSON::Any.new(Base64.strict_encode(element)) }))
    end
  end

  # Serializes an item (a map of attribute name to value) to its wire form.
  def item_to_wire(item : Item) : JSON::Any
    hash = Hash(String, JSON::Any).new(initial_capacity: item.size)
    item.each { |name, value| hash[name] = to_wire(value) }
    JSON::Any.new(hash)
  end

  # Deserializes a single wire attribute value.
  #
  # Raises `ArgumentError` if *json* is not a one-key object with a known attribute type.
  def from_wire(json : JSON::Any) : Value
    object = json.as_h?
    raise ArgumentError.new("Expected a DynamoDB attribute value object, got #{json.to_json}") unless object
    type, raw = single_entry(object, json)
    scalar_from_wire(type, raw)
  end

  private def scalar_from_wire(type, raw)
    case type
    when "S"    then raw.as_s
    when "N"    then number_from_wire(raw.as_s)
    when "B"    then Base64.decode(raw.as_s)
    when "BOOL" then raw.as_bool
    when "NULL" then nil
    else             collection_from_wire(type, raw)
    end
  end

  private def collection_from_wire(type, raw)
    case type
    when "SS" then raw.as_a.map(&.as_s).to_set
    when "NS" then raw.as_a.map { |element| BigDecimal.new(element.as_s) }.to_set
    when "BS" then raw.as_a.map { |element| Base64.decode(element.as_s) }.to_set
    when "L"  then raw.as_a.map { |element| from_wire(element) }.as(Array(Value))
    when "M"  then item_from_wire(raw)
    else           raise ArgumentError.new("Unknown DynamoDB attribute type #{type.inspect}")
    end
  end

  # Deserializes an item (a map of attribute name to wire attribute value).
  def item_from_wire(json : JSON::Any) : Item
    object = json.as_h?
    raise ArgumentError.new("Expected a DynamoDB item object, got #{json.to_json}") unless object
    item = Item.new(initial_capacity: object.size)
    object.each { |name, value| item[name] = from_wire(value) }
    item
  end

  # Deserializes an item, or returns `nil` when *json* is absent or JSON `null`.
  def item_from_wire?(json : JSON::Any?) : Item?
    return if json.nil? || json.raw.nil?
    item_from_wire(json)
  end

  # Parses a DynamoDB `N` value: an `Int64` when it is an integer, a `BigDecimal` otherwise.
  #
  # Floats are never produced, so that DynamoDB's decimal precision is preserved.
  def number_from_wire(number : String) : Value
    number.to_i64? || BigDecimal.new(number)
  end

  private def wrap(type : String, value : JSON::Any) : JSON::Any
    JSON::Any.new({type => value})
  end

  private def single_entry(object, json)
    raise ArgumentError.new("Expected exactly one attribute type, got #{json.to_json}") unless object.size == 1
    object.first
  end
end
