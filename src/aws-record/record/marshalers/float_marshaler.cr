require "./marshaler"

# Marshals `float_attr` attributes: anything reads as a `Float64`.
#
# As in Ruby, a string that does not look like a number reads as zero rather than raising.
class Aws::Record::Marshalers::FloatMarshaler < Aws::Record::Marshalers::Marshaler
  # What `#type_cast` produces.
  alias Cast = Float64?

  # Creates the marshaler.
  def initialize : Nil
  end

  # Casts *raw* to a `Float64`, leaving `nil` and the empty string as `nil`.
  def type_cast(raw : RawValue) : RawValue
    cast(raw)
  end

  # Stores *raw* as an `N` attribute.
  def serialize(raw : RawValue) : Aws::DynamoDB::Value
    cast(raw)
  end

  # Recovers the cast type of *value*.
  def self.narrow(value : RawValue) : Cast
    value.as?(Float64)
  end

  private def cast(raw : RawValue) : Float64?
    case raw
    when Nil, "" then nil
    when Float64 then raw
    when Number  then raw.to_f64
    when String  then raw.to_f64?(strict: false) || 0.0
    when Bytes   then String.new(raw).to_f64?(strict: false) || 0.0
    when Time    then raw.to_unix.to_f64
    when true    then 1.0
    when false   then 0.0
    else              0.0
    end
  end
end
