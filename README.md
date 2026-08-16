# aws-record-crystal

Object mapping abstraction for [Amazon DynamoDB](https://aws.amazon.com/dynamodb/) — a Crystal port of
Amazon's [`aws-record`](https://github.com/aws/aws-record-ruby) Ruby gem (version 2.15.1, commit
`c97f732`).

Every one of the gem's 372 unit examples and 45 Cucumber scenarios is ported, with the same
descriptions, so the two suites can be diffed side by side. The shard ships its own minimal, typed
DynamoDB client (`Aws::DynamoDB`) because there is no AWS SDK for Crystal.

* [`docs/DIFFERENCES.md`](docs/DIFFERENCES.md) — every intentional behavior difference from the gem
* [`PORT_STATUS.md`](PORT_STATUS.md) — parity tables, coverage history and known limitations
* [`CHANGELOG.md`](CHANGELOG.md)

## Table of contents

* [Installation](#installation)
* [Usage](#usage)
  * [Item operations](#item-operations)
  * [BatchGetItem and BatchWriteItem](#batchgetitem-and-batchwriteitem)
  * [Transactions](#transactions)
  * [Inheritance support](#inheritance-support)
* [Differences from the Ruby gem](#differences-from-the-ruby-gem)
* [Using with Lucky/Avram](#using-with-luckyavram)
* [Development](#development)
* [License](#license)

---

## Installation

Requires Crystal 1.21.0 or newer. Add the dependency to your `shard.yml`:

```yaml
dependencies:
  aws-record-crystal:
    github: MatheusBasso99/aws-record-crystal
```

Then run `shards install`. The only runtime dependency is
[`awscr-signer`](https://github.com/taylorfinnell/awscr-signer), used for SigV4 request signing.

---

## Usage

A model is a class that inherits from `Aws::Record::Base` (where the Ruby gem uses
`include Aws::Record` — see [Differences](#differences-from-the-ruby-gem)):

```crystal
require "aws-record-crystal"

class MyModel < Aws::Record::Base
  integer_attr :id, hash_key: true
  string_attr :name, range_key: true
  boolean_attr :active, database_attribute_name: "is_active_flag"
end
```

The attribute macros are `string_attr`, `boolean_attr`, `integer_attr`, `float_attr`, `date_attr`,
`datetime_attr`, `time_attr`, `epoch_time_attr`, `list_attr`, `map_attr`, `string_set_attr`,
`numeric_set_attr`, `atomic_counter`, and `attr` for a marshaler of your own. They accept
`hash_key:`, `range_key:`, `database_attribute_name:`, `persist_nil:`, `default_value:` and the
per-type `formatter:`/`use_local_time:` options.

If a matching table does not exist in DynamoDB, the `TableConfig` DSL creates it:

```crystal
config = Aws::Record::TableConfig.define do |table|
  table.model_class(MyModel)
  table.read_capacity_units(5)
  table.write_capacity_units(2)
end
config.migrate!
```

With a table in place, the model class reads and writes items:

```crystal
if found = MyModel.find(id: 1, name: "Hello Record")
  found.active = true
  found.save
  found.delete!
end

MyModel.find(id: 1, name: "Hello Record") # => nil

item = MyModel.new
item.id = 2
item.name = "Item"
item.active = false
item.save
```

Getters are typed after the attribute (`Int64?`, `String?`, `Bool?`, `Time?`, `Set(String)`, …) and
setters take whatever converts to the stored value, so `item.tags = ["a", "b"]` works.

Searching returns a lazy, `Enumerable` collection that pages as you read it:

```crystal
MyModel.scan(consistent_read: true).each { |record| puts record.to_h }

MyModel.build_query
  .key_expr(":id = ? AND :name > ?", 1, "b")
  .filter_expr(":active = ?", true)
  .consistent_read(true)
  .complete!
```

---

### Item operations

```crystal
class Post < Aws::Record::Base
  integer_attr :uuid, hash_key: true
  string_attr :name, range_key: true
  integer_attr :age
end

post = Post.find(uuid: 1, name: "Foo")
post.try(&.update(age: 1))

# Or, without reading the item first — this writes an update expression for `age` only:
Post.update(uuid: 1, name: "Foo", age: 1)
```

`save` writes a conditional put for a new record and an update expression for a loaded one, so an
existing item is never clobbered by accident; `save!` raises `Aws::Record::Errors::ConditionalWriteFailed`
instead of returning `false`, and `save(force: true)` skips the condition. Dirty tracking backs all of
it: `#dirty?`, `#dirty`, `#<attr>_dirty?`, `#<attr>_was`, `#rollback!`, `#clean!` and `#reload!`.

---

### BatchGetItem and BatchWriteItem

```crystal
class Lunch < Aws::Record::Base
  integer_attr :id, hash_key: true
  string_attr :name, range_key: true
end

class Dessert < Aws::Record::Base
  integer_attr :id, hash_key: true
  string_attr :name, range_key: true
end

read = Aws::Record::Batch.read do |db|
  db.find(Lunch, id: 1, name: "Papaya Salad")
  db.find(Lunch, id: 2, name: "BLT Sandwich")
  db.find(Dessert, id: 1, name: "Apple Pie")
end

# BatchRead is Enumerable and handles pagination. Items come back as `Aws::Record::Base`,
# so narrow them to reach the typed accessors:
read.each do |item|
  puts item.name if item.is_a?(Lunch)
end

# BatchRead also has a lower level interface: `execute!`, `complete?` and `items`.
# Unprocessed keys are retried by calling `execute!` again:
until read.complete?
  read.execute!
end
```

```crystal
class Breakfast < Aws::Record::Base
  integer_attr :id, hash_key: true
  string_attr :name, range_key: true
  string_attr :body
end

eggs = Breakfast.new(id: 1, name: "eggs")
eggs.save!
waffles = Breakfast.new(id: 2, name: "waffles")
pancakes = Breakfast.new(id: 3, name: "pancakes")

write = Aws::Record::Batch.write(client: Breakfast.dynamodb_client) do |db|
  db.put(waffles)
  db.delete(eggs)
  db.put(pancakes)
end

# Unprocessed items are retried by calling `execute!` again:
until write.complete?
  write.execute!
end
```

---

### Transactions

```crystal
class TableOne < Aws::Record::Base
  string_attr :uuid, hash_key: true
  string_attr :body
end

class TableTwo < Aws::Record::Base
  string_attr :hk, hash_key: true
  string_attr :rk, range_key: true
  string_attr :body
end

results = Aws::Record::Transactions.transact_find(transact_items: [
  TableOne.tfind_opts(key: {uuid: "uuid1234"}),
  TableTwo.tfind_opts(key: {hk: "hk1", rk: "rk1"}),
  TableTwo.tfind_opts(key: {hk: "hk2", rk: "rk2"}),
])
# `results.responses` holds an item or nil per request; `results.missing_items` says which were missing.
results.responses.map(&.class) # => [TableOne, TableTwo, TableTwo]
```

Write actions are built by `Aws::Record::Transactions.save/.put/.update/.delete/.check`, each taking
that operation's options, where the Ruby gem takes a hash keyed on the operation:

```crystal
check = TableOne.transact_check_expression(
  key: {uuid: "foo"},
  condition_expression: "size(#T) <= :v",
  expression_attribute_names: {"#T" => "body"},
  expression_attribute_values: Aws::DynamoDB::Item{":v" => 1024_i64}
)
new_item = TableTwo.new(hk: "hk1", rk: "rk1", body: "Hello!")
put_item = TableOne.new(uuid: "foobar", body: "Content!")

actions = [
  Aws::Record::Transactions.check(check),
  Aws::Record::Transactions.save(new_item),
  Aws::Record::Transactions.put(
    put_item,
    condition_expression: "attribute_not_exists(#H)",
    expression_attribute_names: {"#H" => "uuid"},
    return_values_on_condition_check_failure: "ALL_OLD"
  ),
]

if updated = TableOne.find(uuid: "bar")
  updated.body = "Updated the body!"
  actions << Aws::Record::Transactions.save(updated)
end
if doomed = TableOne.find(uuid: "to_be_deleted")
  actions << Aws::Record::Transactions.delete(doomed)
end

Aws::Record::Transactions.transact_write(transact_items: actions)
```

---

### Inheritance support

Models extend by ordinary Crystal inheritance. A child inherits its parent's

* table name (`set_table_name`),
* attributes and keys,
* mutation tracking setting (`enable_mutation_tracking` / `disable_mutation_tracking`),
* local and global secondary indexes,
* configured client (`configure_client`),

and may override any of them.

```crystal
class Animal < Aws::Record::Base
  string_attr :name, hash_key: true
  integer_attr :age
end

class Dog < Animal
  boolean_attr :family_friendly
end

if dog = Dog.find(name: "Sunflower")
  dog.age = 3
  dog.family_friendly = true
  dog.save!
end
```

---

## Differences from the Ruby gem

The full list, with the reason for each, is in [`docs/DIFFERENCES.md`](docs/DIFFERENCES.md). The ones
you will notice first:

* `class MyModel < Aws::Record::Base` replaces `include Aws::Record`. Crystal module metaclasses are not
  supertypes of the including classes' metaclasses, and the gem needs collections of *model classes*.
* Modelling mistakes are **compile** errors: duplicate attributes, an attribute that is both hash and
  range key, storage name collisions, reserved names, unknown attributes passed to `Model.new`, and
  options an operation does not have.
* Attribute names are `String` at run time (APIs still accept `Symbol`), numeric sets are
  `Set(BigDecimal)`, and `date_attr`/`datetime_attr`/`time_attr`/`epoch_time_attr` all read as `Time?` —
  Crystal has one time type. The **wire** formats are byte-identical to the gem's, which
  `spec/aws-record/wire_compat_spec.cr` pins down.
* Transactional writes are built with `Transactions.save/.put/.update/.delete/.check`.
* The DynamoDB client is this shard's own: `Aws::DynamoDB::Client.new(region: "us-east-1")`, with
  `stub_responses: true` for tests. Credentials resolve from explicit values, the environment or
  `~/.aws/credentials`; IMDS, ECS, SSO and `AssumeRole` are out of scope.

## Using with Lucky/Avram

The shard is built to sit next to an [Avram](https://github.com/luckyframework/avram) model layer in a
Lucky app, and `scripts/compat_avram.sh` type-checks the two together on every CI run.

Any model can simply inherit from `Aws::Record::Base`, exactly as in the [Usage](#usage) section. In
an app with several DynamoDB models, though, it pays to give them a shared base, the way Avram apps
have a `BaseModel`: an abstract model with no attributes of its own is allowed, and it only carries
configuration (`configure_client`, `disable_mutation_tracking`, …) that every subclass inherits.
Without it, each model builds its own client — with its own connection pool — from the environment on
first use.

Build the client once, at boot:

```crystal
# config/dynamodb.cr
DYNAMODB = Aws::DynamoDB::Client.new(region: "us-east-1")
```

Keep the shared base in its own file — it is the only place that mentions the client:

```crystal
# src/models/dynamo_record.cr
abstract class DynamoRecord < Aws::Record::Base
  configure_client(client: DYNAMODB)
end
```

Then every model gets a file of its own and looks the same; each one uses `DYNAMODB` without saying so:

```crystal
# src/models/session.cr
class Session < DynamoRecord
  string_attr :sid, hash_key: true
  datetime_attr :created_at
  epoch_time_attr :expires_at
end
```

```crystal
# src/models/cart.cr
class Cart < DynamoRecord
  string_attr :user_id, hash_key: true
  list_attr :items
end
```

In specs, `DynamoRecord.configure_client(client: Aws::DynamoDB::Client.new(stub_responses: true))` in
the spec helper points every model at the stub. Do it before any model is used: as in the Ruby gem, a
subclass remembers the client it resolved on first use, so reconfiguring the base later does not reach
models that already have one (call `configure_client` on those directly).

Things worth knowing:

* **`Aws` is the only top-level constant this shard defines**, and it never reopens a stdlib or
  third-party type — so nothing collides with Avram's and Lucky's `Object#blank?`, `String#squish`,
  `Hash#get` and friends. `scripts/hygiene.sh` enforces both rules on every build.
* **`Aws::DynamoDB` is claimed by this shard.** An app cannot also depend on another shard that defines
  it (for instance `veelenga/aws-dynamodb.cr`).
* **Clients are fiber-safe**: connections come from a mutex-guarded pool, and all class-level state is
  either immutable after class definition or mutex-guarded, which is what Crystal 1.21's parallel
  execution contexts require. Configure clients at boot, not per request.
* **Logging** goes to `Log.for("aws.record")` and `Log.for("aws.dynamodb")`, so Lucky's Dexter setup
  picks it up unchanged.

## Development

Requires Crystal 1.21.0 or newer. Docker is used for coverage and for DynamoDB Local.

```bash
scripts/setup.sh        # shards install + build bin/ameba
scripts/check.sh        # format, hygiene, ameba, specs, docs, examples (the gate)
scripts/check.sh --fast # same without docs/examples/unreachable
scripts/coverage.sh     # kcov coverage in Docker (gate: >= 85 %, target 90 %)
scripts/integration.sh  # the 45 integration specs against DynamoDB Local
scripts/compat_avram.sh # type-check alongside Avram/Lucky
scripts/parity.py       # audit spec parity against ../aws-record-ruby (run by check.sh when present)
```

The gates are: `crystal tool format --check`, `bin/ameba` with zero issues (documentation and typing
rules on for `src/`), `crystal spec --error-on-warnings --order random` green, line coverage of `src/`
at or above 85 % with no record file below 80 %, namespace hygiene, and the Avram compatibility
type-check. Every sample in this README lives in [`examples/`](examples) and is compiled by
`scripts/check.sh`.

Use `./bin/ameba` (built by `scripts/setup.sh`), not a system-installed one: releases before 1.7 do not
parse Crystal 1.21 sources. Never pass `-Dpreview_mt`; on 1.21 it selects the *legacy* scheduler.

## License

Apache-2.0. This project is a derivative work of `aws-record`, Copyright 2016 Amazon.com, Inc. or its
affiliates — see [`NOTICE`](NOTICE).
