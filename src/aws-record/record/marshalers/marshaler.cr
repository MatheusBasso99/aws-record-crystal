require "../raw_value"

# Turns the value a user assigned into the value an attribute reads as, and into the value stored
# in DynamoDB.
#
# The Ruby gem uses a duck type with `#type_cast` and `#serialize`; here it is an abstract class, so
# that `Aws::Record::Attribute` can hold any marshaler and a model can bring its own with `attr`.
#
# Every marshaler also has a `Cast` alias naming the type `#type_cast` produces, and a `.narrow`
# class method that recovers it from a `RawValue` — that is what gives generated attribute getters
# their precise return type.
abstract class Aws::Record::Marshalers::Marshaler
  # The value *raw* reads as, after casting.
  abstract def type_cast(raw : RawValue) : RawValue

  # The value *raw* is stored as, or `nil` when it should not be persisted.
  abstract def serialize(raw : RawValue) : Aws::DynamoDB::Value
end

# The marshaler used by `Aws::Record::Attribute` when a model brings none: values pass through
# unchanged, exactly like the Ruby gem's `Aws::Record::DefaultMarshaler`.
class Aws::Record::Marshalers::DefaultMarshaler < Aws::Record::Marshalers::Marshaler
  # What `#type_cast` produces.
  alias Cast = RawValue

  # Creates the marshaler.
  def initialize : Nil
  end

  # Returns *raw* unchanged.
  def type_cast(raw : RawValue) : RawValue
    raw
  end

  # Returns *raw* unchanged.
  #
  # Raises `ArgumentError` for a `Time`, which DynamoDB has no type for: use `date_attr`,
  # `datetime_attr`, `time_attr` or `epoch_time_attr`, or bring a marshaler that formats it.
  def serialize(raw : RawValue) : Aws::DynamoDB::Value
    if raw.is_a?(Time)
      raise ArgumentError.new(
        "DefaultMarshaler cannot serialize a Time; use date_attr, datetime_attr, time_attr or epoch_time_attr"
      )
    end
    raw
  end

  # Recovers the cast type of *value*.
  def self.narrow(value : RawValue) : Cast
    value
  end
end
