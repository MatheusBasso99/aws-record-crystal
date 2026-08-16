# Intentional differences from the `aws-record` Ruby gem

Every deviation from the Ruby gem's behavior or API is recorded here, with the reason.
Spec files that assert a divergent behavior carry a comment pointing at the relevant section.

## Model definition

- **`class MyModel < Aws::Record::Base` instead of `include Aws::Record`.** Crystal module metaclasses are
  not supertypes of the including classes' metaclasses, so heterogeneous collections of *model classes*
  (`BatchRead`'s table→class map, `Transactions.transact_find`, `ItemCollection#multi_model_filter`,
  `TableConfig#model_class`) are impossible with a module. An abstract base class makes all of them work.

## Types

- **`Aws::DynamoDB::Values.from` instead of `Aws::DynamoDB::Value.from`.** `Value` is a union *alias*
  (`Nil | Bool | String | Int64 | … | Array(Value) | Hash(String, Value)`), and Crystal cannot attach
  class methods to an alias. The conversion helpers therefore live in a sibling module, `Values`.
- **DynamoDB numbers read from the wire are `Int64` or `BigDecimal`, never `Float64`.** DynamoDB numbers
  are decimal with up to 38 digits of precision, which `Float64` cannot represent. A `float_attr` is still
  written as a `Float64` (`{"N": "3.0"}`, matching the Ruby gem) and the `FloatMarshaler` casts back to
  `Float64` on read, so model attributes behave exactly as in Ruby; only the raw client layer differs.

## Time and dates

## Client and options

## Errors

## Spec techniques

## Not implemented (out of scope)
