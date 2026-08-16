require "./marshaler"

# Marshals `list_attr` attributes: values read and are stored as an `L` attribute.
class Aws::Record::Marshalers::ListMarshaler < Aws::Record::Marshalers::Marshaler
  # What `#type_cast` produces.
  alias Cast = Array(Aws::DynamoDB::Value)?

  # Creates the marshaler.
  def initialize : Nil
  end

  # Casts *raw* to a list, leaving `nil` and the empty string as `nil`.
  #
  # Sets become lists of their members, and maps become lists of `[key, value]` pairs, mirroring
  # Ruby's `Hash#to_a`.
  def type_cast(raw : RawValue) : RawValue
    cast(raw)
  end

  # Stores *raw* as an `L` attribute.
  def serialize(raw : RawValue) : Aws::DynamoDB::Value
    cast(raw)
  end

  # Recovers the cast type of *value*.
  def self.narrow(value : RawValue) : Cast
    value.as?(Array(Aws::DynamoDB::Value))
  end

  private def cast(raw : RawValue) : Array(Aws::DynamoDB::Value)?
    case raw
    when Nil, ""                            then nil
    when Array(Aws::DynamoDB::Value)        then raw
    when Set(String), Set(BigDecimal)       then to_list(raw)
    when Set(Bytes)                         then to_list(raw)
    when Hash(String, Aws::DynamoDB::Value) then pairs(raw)
    else
      raise ArgumentError.new("Don't know how to make #{raw} of type #{raw.class} into an array!")
    end
  end

  private def to_list(set) : Array(Aws::DynamoDB::Value)
    list = Array(Aws::DynamoDB::Value).new(set.size)
    set.each { |element| list << element }
    list
  end

  private def pairs(map) : Array(Aws::DynamoDB::Value)
    list = Array(Aws::DynamoDB::Value).new(map.size)
    map.each { |key, value| list << [key, value] of Aws::DynamoDB::Value }
    list
  end
end
