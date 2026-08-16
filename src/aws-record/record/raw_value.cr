require "../dynamodb/value"

# A value as the user assigned it, before any marshaling.
#
# The Ruby gem stores whatever was assigned to an attribute and type casts on read; this alias is
# what "whatever was assigned" means here: everything DynamoDB can hold, plus `Time`, which the
# date and time marshalers accept and produce.
alias Aws::Record::RawValue = Aws::DynamoDB::Value | Time

# Conversions from convenient Crystal values into `Aws::Record::RawValue`.
#
# `RawValue` is a union alias, so these helpers cannot live on it directly; see
# `docs/DIFFERENCES.md`.
module Aws::Record::RawValues
  extend self

  # Returns *value* unchanged: `Time` is stored as it is and marshaled on read.
  def from(value : Time) : RawValue
    value
  end

  # Converts anything else with `Aws::DynamoDB::Values.from`.
  def from(value : _) : RawValue
    Aws::DynamoDB::Values.from(value)
  end

  # Deep-copies *value* so that mutations of the copy cannot be observed through the original.
  def deep_copy(value : RawValue) : RawValue
    return value if value.is_a?(Time)
    Aws::DynamoDB::Values.deep_copy(value)
  end

  # Whether *value* cannot be mutated, and so needs no copy.
  #
  # Mirrors the Ruby gem's `Attribute#_immutable?`; Crystal strings are immutable too, so they count.
  def immutable?(value : RawValue) : Bool
    case value
    when Nil, Bool, String, Int64, Float64, BigDecimal, Time then true
    else                                                          false
    end
  end
end
