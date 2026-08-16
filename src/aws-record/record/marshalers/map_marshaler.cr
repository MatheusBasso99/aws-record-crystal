require "./marshaler"

# Marshals `map_attr` attributes: values read and are stored as an `M` attribute.
class Aws::Record::Marshalers::MapMarshaler < Aws::Record::Marshalers::Marshaler
  # What `#type_cast` produces.
  alias Cast = Aws::DynamoDB::Item?

  # Creates the marshaler.
  def initialize : Nil
  end

  # Casts *raw* to a map, leaving `nil` and the empty string as `nil`.
  #
  # A list of `[key, value]` pairs becomes a map, mirroring Ruby's `Array#to_h`.
  def type_cast(raw : RawValue) : RawValue
    cast(raw)
  end

  # Stores *raw* as an `M` attribute.
  def serialize(raw : RawValue) : Aws::DynamoDB::Value
    cast(raw)
  end

  # Recovers the cast type of *value*.
  def self.narrow(value : RawValue) : Cast
    value.as?(Aws::DynamoDB::Item)
  end

  private def cast(raw : RawValue) : Aws::DynamoDB::Item?
    case raw
    when Nil, ""                            then nil
    when Hash(String, Aws::DynamoDB::Value) then raw
    when Array(Aws::DynamoDB::Value)        then from_pairs(raw)
    else
      raise ArgumentError.new("Don't know how to make #{raw} of type #{raw.class} into a hash!")
    end
  end

  private def from_pairs(list) : Aws::DynamoDB::Item
    item = Aws::DynamoDB::Item.new(initial_capacity: list.size)
    list.each do |pair|
      unless pair.is_a?(Array(Aws::DynamoDB::Value)) && pair.size == 2
        raise ArgumentError.new("Don't know how to make #{list} of type #{list.class} into a hash!")
      end
      key = pair[0]
      item[key.is_a?(String) ? key : key.to_s] = pair[1]
    end
    item
  end
end
