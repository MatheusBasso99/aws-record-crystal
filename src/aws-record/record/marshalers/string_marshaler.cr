require "./marshaler"

# Marshals `string_attr` attributes: anything reads as a `String`, and an empty string is not
# persisted at all.
class Aws::Record::Marshalers::StringMarshaler < Aws::Record::Marshalers::Marshaler
  # What `#type_cast` produces.
  alias Cast = String?

  # Creates the marshaler.
  def initialize : Nil
  end

  # Casts *raw* to a `String`, leaving `nil` as `nil`.
  def type_cast(raw : RawValue) : RawValue
    cast(raw)
  end

  # Stores *raw* as an `S` attribute; `nil` and the empty string are not persisted.
  def serialize(raw : RawValue) : Aws::DynamoDB::Value
    cast(raw).try(&.presence)
  end

  # Recovers the cast type of *value*.
  def self.narrow(value : RawValue) : Cast
    value.as?(String)
  end

  private def cast(raw : RawValue) : String?
    case raw
    when Nil    then nil
    when String then raw
    when Bytes  then String.new(raw)
    else             raw.to_s
    end
  end
end
