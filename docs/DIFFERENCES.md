# Intentional differences from the `aws-record` Ruby gem

Every deviation from the Ruby gem's behavior or API is recorded here, with the reason.
Spec files that assert a divergent behavior carry a comment pointing at the relevant section.

## Model definition

- **`class MyModel < Aws::Record::Base` instead of `include Aws::Record`.** Crystal module metaclasses are
  not supertypes of the including classes' metaclasses, so heterogeneous collections of *model classes*
  (`BatchRead`'s table→class map, `Transactions.transact_find`, `ItemCollection#multi_model_filter`,
  `TableConfig#model_class`) are impossible with a module. An abstract base class makes all of them work.

## Types

- **Attribute names are `String` at runtime**, not `Symbol`: Crystal cannot create symbols at runtime and
  names arrive from the wire. Public APIs accept `String | Symbol` so `item.attribute_dirty?(:name)` still
  reads like Ruby.
- **Numeric sets are always `Set(BigDecimal)`, and collections are homogeneous.** A Crystal `Set` cannot
  hold mixed types, so the Ruby examples that type cast `Set.new([1, '2', 3])` pass a list here instead.
- **A default value given as a block is wrapped with `Aws::Record::Attribute.default_proc`.** Crystal infers
  a proc literal's type from its body, so `->{ 2 + 3 }` is a `Proc(Int32)` and would not fit; `default_proc`
  widens the result to `RawValue`.

- **`Aws::DynamoDB::Values.from` instead of `Aws::DynamoDB::Value.from`.** `Value` is a union *alias*
  (`Nil | Bool | String | Int64 | … | Array(Value) | Hash(String, Value)`), and Crystal cannot attach
  class methods to an alias. The conversion helpers therefore live in a sibling module, `Values`.
- **DynamoDB numbers read from the wire are `Int64` or `BigDecimal`, never `Float64`.** DynamoDB numbers
  are decimal with up to 38 digits of precision, which `Float64` cannot represent. A `float_attr` is still
  written as a `Float64` (`{"N": "3.0"}`, matching the Ruby gem) and the `FloatMarshaler` casts back to
  `Float64` on read, so model attributes behave exactly as in Ruby; only the raw client layer differs.

## Time and dates

- **Crystal has one time type, so `date_attr`, `datetime_attr`, `time_attr` and `epoch_time_attr` all
  read as `Time?`.** Ruby distinguishes `Date`, `DateTime` and `Time`. What still differs per attribute
  is the *wire* format, which is byte-identical to the Ruby gem's (see `spec/aws-record/wire_compat_spec.cr`):
  `%F` for dates, `Time#iso8601` (`Z` for UTC) for times, `DateTime#iso8601` (always a numeric offset)
  for datetimes, and whole epoch seconds for epoch times. A `date_attr` reads as midnight UTC of its day.
- **`Aws::Record::TimeParsing.parse` replaces Ruby's `Date.parse`/`Time.parse`.** Crystal's parsers are
  strict and each handles one format, and `Time.parse_iso8601` rejects a date-only string, so the
  marshalers go through a cascade of the formats the Ruby gem accepts. It raises `ArgumentError` when
  nothing matches, exactly as Ruby does.
- **Custom formatters are `Proc(Time, String)`** rather than an object responding to `.format`.

## Client and options

## Errors

- **Marshalers cannot raise "expected a X value" the way Ruby's do.** `#type_cast` is typed to return
  the marshaler's `Cast` type, so the mismatch those errors guard against cannot happen. The Ruby specs
  that assert them are ported with their descriptions and assert the Crystal behaviour instead: values
  Ruby would have turned into nonsense (`"wrong".to_i`) become zero, exactly as they do in Ruby.
- **`Aws::Record::Marshalers::DefaultMarshaler` refuses to serialize a `Time`** with an `ArgumentError`
  naming the time attribute macros. Ruby would have passed the `Time` on to the SDK, which fails later
  and less clearly.

## Spec techniques

## Not implemented (out of scope)
