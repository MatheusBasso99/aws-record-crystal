require "./marshaler"

# Marshals `boolean_attr` attributes.
#
# `nil` and the empty string read as `nil`; `false`, `"false"`, `"0"` and numeric zero read as
# `false`; everything else reads as `true`.
class Aws::Record::Marshalers::BooleanMarshaler < Aws::Record::Marshalers::Marshaler
  # What `#type_cast` produces.
  alias Cast = Bool?

  # Creates the marshaler.
  def initialize : Nil
  end

  # Casts *raw* to a `Bool`, leaving `nil` and the empty string as `nil`.
  def type_cast(raw : RawValue) : RawValue
    cast(raw)
  end

  # Stores *raw* as a `BOOL` attribute.
  def serialize(raw : RawValue) : Aws::DynamoDB::Value
    cast(raw)
  end

  # Recovers the cast type of *value*.
  def self.narrow(value : RawValue) : Cast
    value.as?(Bool)
  end

  private def cast(raw : RawValue) : Bool?
    case raw
    when Nil, ""      then nil
    when Bool         then raw
    when "false", "0" then false
    when Number       then raw != 0
    else                   true
    end
  end
end
