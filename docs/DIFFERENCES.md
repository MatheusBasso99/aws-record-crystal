# Intentional differences from the `aws-record` Ruby gem

Every deviation from the Ruby gem's behavior or API is recorded here, with the reason.
Spec files that assert a divergent behavior carry a comment pointing at the relevant section.

## Model definition

- **`class MyModel < Aws::Record::Base` instead of `include Aws::Record`.** Crystal module metaclasses are
  not supertypes of the including classes' metaclasses, so heterogeneous collections of *model classes*
  (`BatchRead`'s table→class map, `Transactions.transact_find`, `ItemCollection#multi_model_filter`,
  `TableConfig#model_class`) are impossible with a module. An abstract base class makes all of them work.
- **Modelling mistakes are compile errors.** Duplicate attribute names, an attribute that is both hash
  and range key, storage name collisions, reserved names and non-symbol attribute names are raised by
  the attribute macros at compile time, where the Ruby gem raises `Errors::NameCollision`,
  `Errors::ReservedName` or `ArgumentError` when the class body runs. Passing an unknown attribute to
  `Model.new` or `#assign_attributes`, or a non-integer to `increment_<name>!`, is a compile error too.
  `Aws::Record::ModelAttributes` keeps the runtime checks for models that register attributes themselves.
- **Mutation tracking and the table name are inherited by lookup, not by snapshot.** The Ruby gem copies
  the parent's setting into the child when the child's class body runs, so the result depends on
  definition order; here a child with no setting of its own asks its parent every time.
- **Attribute setters accept any value (`value : _`)**, as Ruby's do, while getters are precisely typed
  (`Time?`, `Set(String)`, `Int64?`, …). A union type cannot express "any collection", so typing the
  setters would have rejected `item.tags = ["a", "b"]`.

## Types

- **Attribute names are `String` at runtime**, not `Symbol`: Crystal cannot create symbols at runtime and
  names arrive from the wire. Public APIs accept `String | Symbol` so `item.attribute_dirty?(:name)` still
  reads like Ruby.
- **Numeric sets are always `Set(BigDecimal)`, and collections are homogeneous.** A Crystal `Set` cannot
  hold mixed types, so the Ruby examples that type cast `Set.new([1, '2', 3])` pass a list here instead.
- **Assigning a collection that is not already a `Value` converts it, and so copies it.** Assigning an
  `Array(Aws::DynamoDB::Value)` or an `Aws::DynamoDB::Item` stores that very object, so mutating it
  afterwards is visible to the item — which is what mutation tracking observes, and what the Ruby gem
  does for every collection.
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

- **Pass-through options are typed.** Where Ruby forwards an arbitrary options hash to the SDK, the
  record layer builds the operation's input shape, so naming an option the operation does not have is
  a compile error rather than a runtime `ArgumentError` from the SDK.
- **`increment_<name>!` substitutes the attribute's *storage* name.** The Ruby gem substitutes the
  attribute name, which writes to the wrong DynamoDB attribute when the counter has a
  `database_attribute_name`.
- **`#assign_attributes(item)` accepts attribute names *and* storage names.** The Ruby gem folds a
  response's `attributes` back in by attribute name only, which raises for any attribute with a
  `database_attribute_name`.

## Errors

- **Marshalers cannot raise "expected a X value" the way Ruby's do.** `#type_cast` is typed to return
  the marshaler's `Cast` type, so the mismatch those errors guard against cannot happen. The Ruby specs
  that assert them are ported with their descriptions and assert the Crystal behaviour instead: values
  Ruby would have turned into nonsense (`"wrong".to_i`) become zero, exactly as they do in Ruby.
- **`Aws::Record::Marshalers::DefaultMarshaler` refuses to serialize a `Time`** with an `ArgumentError`
  naming the time attribute macros. Ruby would have passed the `Time` on to the SDK, which fails later
  and less clearly.

## Spec techniques

- **RSpec mocks are replaced by the stub client.** `spec/aws-record/record/dirty_tracking_spec.cr`
  stubs `get_item` where the Ruby spec stubs `.find`, and the Ruby examples that assert an
  `ArgumentError` for an unknown attribute assert a compile error here instead. Each such example keeps
  the Ruby description and says so in a comment.
- **ActiveModel is not available.** The Ruby specs that mix in `ActiveModel::Validations` or
  `ActiveModel::Model` are ported against a model that overrides `#valid?`, which is the hook this
  shard documents.

## Batch and transactions

- **A transactional write item is built by `Aws::Record::Transactions.save/.put/.update/.delete/.check`**
  rather than by a hash keyed on the operation (`{save: record}`). Each builder takes the record and
  that operation's options, so an option the operation does not have is a compile error.
- **`Aws::Record::Batch.write`/`.read` fall back to the client `Batch` itself is configured with.**
  The Ruby gem builds a brand new client for every call that does not name one.
- **`Model.find_all` and `Model.transact_find` take an `Array(Hash(String, Aws::Record::RawValue))`.**
  Crystal cannot hold named tuples of differing shapes in one array.

## Not implemented (out of scope)

- **Credential providers** are limited to explicit, environment and shared-file. IMDS, ECS, SSO and
  `AssumeRole` are not implemented; build an `Aws::DynamoDB::Credentials` yourself and pass it in.
