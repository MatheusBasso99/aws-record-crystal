require "big"
require "set"

# A minimal, typed client for the Amazon DynamoDB JSON (1.0) API.
#
# It exists because there is no AWS SDK for Crystal; it covers exactly the operations
# `Aws::Record` needs, plus waiters, pagination, retries and response stubbing. Class names
# mirror the Ruby SDK (`Aws::DynamoDB::Client`, `Aws::DynamoDB::Errors::ResourceNotFoundException`, …)
# so that code and specs ported from the Ruby gem read the same.
module Aws::DynamoDB
  # A DynamoDB attribute value in its "simple" (unmarshalled) Crystal form.
  #
  # `Aws::DynamoDB::AttributeValue` converts between this and the wire form
  # (`{"S" => "x"}`, `{"N" => "1"}`, …).
  #
  # Numbers read from the wire become `Int64` when they parse as an integer and `BigDecimal`
  # otherwise — never `Float64`, so that DynamoDB's 38 digits of decimal precision survive.
  alias Value = (Bool | String | Int64 | Float64 | BigDecimal | Bytes |
                 Set(String) | Set(BigDecimal) | Set(Bytes) |
                 Array(Value) | Hash(String, Value))?

  # A DynamoDB item: attribute name to `Value`.
  #
  # Hash literals need the alias to get the right type: `Aws::DynamoDB::Item{"id" => 1_i64}`
  # (a bare `{"id" => 1_i64}` would be a `Hash(String, Int64)`).
  alias Item = Hash(String, Value)
end

# Conversions from convenient Crystal values into `Aws::DynamoDB::Value`.
#
# `Value` is a union alias, so these helpers cannot live on it directly; see
# `docs/DIFFERENCES.md`.
#
# ```
# Aws::DynamoDB::Values.from(1)           # => 1_i64
# Aws::DynamoDB::Values.from({a: [1, 2]}) # => {"a" => [1_i64, 2_i64]}
# ```
module Aws::DynamoDB::Values
  extend self

  # Returns `nil`, the only `Value` a `Nil` can be.
  def from(value : Nil) : Value
    value
  end

  # Returns *value* unchanged.
  def from(value : Bool) : Value
    value
  end

  # Returns *value* unchanged.
  def from(value : String) : Value
    value
  end

  # Converts a `Symbol` to its `String` form.
  def from(value : Symbol) : Value
    value.to_s
  end

  # Widens any integer to `Int64`.
  def from(value : Int) : Value
    value.to_i64
  end

  # Converts an arbitrary-precision integer to `BigDecimal`, which DynamoDB numbers map to.
  def from(value : BigInt) : Value
    BigDecimal.new(value)
  end

  # Widens any float to `Float64`.
  def from(value : Float) : Value
    value.to_f64
  end

  # Returns *value* unchanged.
  def from(value : BigDecimal) : Value
    value
  end

  # Returns *value* unchanged; binary data is sent as a `B` attribute.
  def from(value : Bytes) : Value
    value
  end

  # Converts a set to one of DynamoDB's set types (`SS`, `NS` or `BS`), based on its element type.
  def from(value : Set(T)) : Value forall T
    {% if T <= ::String || T <= ::Symbol %}
      value.map(&.to_s).to_set
    {% elsif T <= ::BigDecimal %}
      value
    {% elsif T <= ::Number %}
      value.map { |element| big_decimal(element) }.to_set
    {% elsif T <= ::Bytes %}
      value
    {% else %}
      {% raise "Values.from cannot convert a Set(#{T}): DynamoDB sets hold strings, numbers or binaries" %}
    {% end %}
  end

  # Converts a hash to a `Aws::DynamoDB::Item` (an `M` attribute). Keys must be strings or symbols.
  def from(value : Hash(K, V)) : Value forall K, V
    {% unless K <= ::String || K <= ::Symbol %}
      {% raise "Aws::DynamoDB::Values.from cannot convert a Hash with #{K} keys — DynamoDB map keys are strings" %}
    {% end %}
    map(value)
  end

  # Converts a named tuple to a `Aws::DynamoDB::Item` (an `M` attribute).
  def from(value : NamedTuple) : Value
    item = Item.new
    value.each { |key, element| item[key.to_s] = from(element) }
    item
  end

  # Converts any other enumerable (arrays, tuples, ranges, …) to an `L` attribute.
  #
  # When `from` is dispatched over a `Value`, Crystal hands this overload *every* enumerable member
  # of that union — binaries, sets, lists and maps — so they are all recognised here and returned
  # unchanged. Hashes especially must never fall through to the list path: iterating one yields
  # `Tuple(String, Value)`, which `Tuple#each`'s `Union(*T)` block restriction cannot type against
  # the recursive `Value` alias.
  def from(value : Enumerable) : Value
    return value if value.is_a?(Value)
    return map(value) if value.is_a?(Hash)
    list = Array(Value).new
    value.each { |element| list << from(element) }
    list
  end

  private def map(value)
    item = Item.new(initial_capacity: value.size)
    value.each { |key, element| item[key.to_s] = from(element) }
    item
  end

  # Deep-copies *value* so that mutations of the copy cannot be observed through the original.
  #
  # This replaces the Ruby gem's `Marshal.load(Marshal.dump(obj))` round trip.
  def deep_copy(value : Value) : Value
    case value
    in Nil, Bool, String, Int64, Float64, BigDecimal
      value
    in Bytes
      value.dup
    in Set(String), Set(BigDecimal)
      value.dup
    in Set(Bytes)
      value.map(&.dup).to_set
    in Array(Value)
      value.map { |element| deep_copy(element) }
    in Hash(String, Value)
      copy = Item.new(initial_capacity: value.size)
      value.each { |key, element| copy[key] = deep_copy(element) }
      copy
    end
  end

  # Converts *number* to `BigDecimal` without going through binary floating point artifacts.
  def big_decimal(number : Number) : BigDecimal
    case number
    when BigDecimal then number
    when Float      then BigDecimal.new(number.to_s)
    else                 BigDecimal.new(number.to_s)
    end
  end
end
