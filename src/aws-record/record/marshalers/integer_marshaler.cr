require "./marshaler"

# Marshals `integer_attr` attributes: anything reads as an `Int64`.
#
# As in Ruby, a string that does not look like a number reads as zero rather than raising.
class Aws::Record::Marshalers::IntegerMarshaler < Aws::Record::Marshalers::Marshaler
  # What `#type_cast` produces.
  alias Cast = Int64?

  # Creates the marshaler.
  def initialize : Nil
  end

  # Casts *raw* to an `Int64`, leaving `nil` and the empty string as `nil`.
  def type_cast(raw : RawValue) : RawValue
    cast(raw)
  end

  # Stores *raw* as an `N` attribute.
  def serialize(raw : RawValue) : Aws::DynamoDB::Value
    cast(raw)
  end

  # Recovers the cast type of *value*.
  def self.narrow(value : RawValue) : Cast
    value.as?(Int64)
  end

  private def cast(raw : RawValue) : Int64?
    case raw
    when Nil, "" then nil
    when Int64   then raw
    when Number  then raw.to_i64
    when String  then raw.to_i64?(strict: false) || 0_i64
    when Bytes   then String.new(raw).to_i64?(strict: false) || 0_i64
    when Time    then raw.to_unix
    when true    then 1_i64
    when false   then 0_i64
    else              0_i64
    end
  end
end
