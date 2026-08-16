require "./marshaler"

# Marshals `string_set_attr` attributes.
#
# A missing value reads as an empty set rather than `nil`, and an empty set is not persisted — both
# as in the Ruby gem.
class Aws::Record::Marshalers::StringSetMarshaler < Aws::Record::Marshalers::Marshaler
  # What `#type_cast` produces.
  alias Cast = Set(String)

  # Creates the marshaler.
  def initialize : Nil
  end

  # Casts *raw* to a `Set(String)`, stringifying every member.
  def type_cast(raw : RawValue) : RawValue
    cast(raw)
  end

  # Stores *raw* as an `SS` attribute; an empty set is not persisted.
  def serialize(raw : RawValue) : Aws::DynamoDB::Value
    set = cast(raw)
    set.empty? ? nil : set
  end

  # Recovers the cast type of *value*.
  def self.narrow(value : RawValue) : Cast
    value.as?(Set(String)) || Set(String).new
  end

  private def cast(raw : RawValue) : Set(String)
    case raw
    when Nil, ""                     then Set(String).new
    when Set(String)                 then raw
    when Set(BigDecimal)             then raw.map(&.to_s).to_set
    when Set(Bytes)                  then raw.map { |element| String.new(element) }.to_set
    when Array(Aws::DynamoDB::Value) then raw.map { |element| stringify(element) }.to_set
    else
      raise ArgumentError.new("Don't know how to make #{raw} of type #{raw.class} into a String Set!")
    end
  end

  private def stringify(element : Aws::DynamoDB::Value) : String
    element.is_a?(Bytes) ? String.new(element) : element.to_s
  end
end
