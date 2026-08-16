require "./marshaler"

# Marshals `numeric_set_attr` attributes.
#
# A missing value reads as an empty set rather than `nil`, and an empty set is not persisted — both
# as in the Ruby gem. Members are always `BigDecimal`, so that DynamoDB's decimal precision is kept.
class Aws::Record::Marshalers::NumericSetMarshaler < Aws::Record::Marshalers::Marshaler
  # What `#type_cast` produces.
  alias Cast = Set(BigDecimal)

  # Creates the marshaler.
  #
  # The Ruby gem has a stray `initialize` outside its `NumericSetMarshaler` class; this is the
  # no-op it was meant to be.
  def initialize : Nil
  end

  # Casts *raw* to a `Set(BigDecimal)`.
  def type_cast(raw : RawValue) : RawValue
    cast(raw)
  end

  # Stores *raw* as an `NS` attribute; an empty set is not persisted.
  def serialize(raw : RawValue) : Aws::DynamoDB::Value
    set = cast(raw)
    set.empty? ? nil : set
  end

  # Recovers the cast type of *value*.
  def self.narrow(value : RawValue) : Cast
    value.as?(Set(BigDecimal)) || Set(BigDecimal).new
  end

  private def cast(raw : RawValue) : Set(BigDecimal)
    case raw
    when Nil, ""                     then Set(BigDecimal).new
    when Set(BigDecimal)             then raw
    when Set(String)                 then raw.map { |element| numeric(element) }.to_set
    when Array(Aws::DynamoDB::Value) then raw.map { |element| numeric(element) }.to_set
    else
      raise ArgumentError.new("Don't know how to make #{raw} of type #{raw.class} into a Numeric Set!")
    end
  end

  private def numeric(element : Aws::DynamoDB::Value) : BigDecimal
    case element
    when Number then Aws::DynamoDB::Values.big_decimal(element)
    when String then BigDecimal.new(element)
    else             raise ArgumentError.new("Don't know how to make #{element} into a number!")
    end
  end
end
