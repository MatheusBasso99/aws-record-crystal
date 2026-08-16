# Changelog

All notable changes to this project are documented in this file.

## 0.1.0 — initial port of aws-record 2.15.1 (commit c97f732)

Unreleased: the shard is feature complete and green on every gate, but nothing is tagged or published
yet — the license choice still needs the maintainer's confirmation (see `PORT_STATUS.md`).

### Added

* `Aws::Record::Base` — the model base class, with the attribute DSL (`string_attr`, `boolean_attr`,
  `integer_attr`, `float_attr`, `date_attr`, `datetime_attr`, `time_attr`, `epoch_time_attr`,
  `list_attr`, `map_attr`, `string_set_attr`, `numeric_set_attr`, `atomic_counter`, `attr`), typed
  accessors, keys, table names, mutation tracking and client configuration, all generated at compile
  time and inherited by subclasses.
* Item operations: `save`, `save!`, `update`, `update!`, `delete!`, `find`, `find_with_opts`,
  `find_all`, `tfind_opts`, `transact_check_expression`, `key_values`, `save_values`, plus dirty
  tracking (`dirty?`, `<attr>_dirty?`, `<attr>_was`, `rollback!`, `clean!`, `reload!`).
* Search: `query`, `scan`, `build_query`, `build_scan` (`Aws::Record::BuildableSearch`) and the lazy,
  `Enumerable`, self-paginating `Aws::Record::ItemCollection` with `multi_model_filter`.
* Tables: `Aws::Record::SecondaryIndexes` (LSI/GSI), `Aws::Record::TableMigration` and
  `Aws::Record::TableConfig` (`migrate!`, `compatible?`, `exact_match?`, TTL, provisioned and
  pay-per-request billing).
* Batch and transactions: `Aws::Record::Batch.read`/`.write`, `BatchRead`, `BatchWrite`, and
  `Aws::Record::Transactions.transact_find`/`.transact_write` with `save`/`put`/`update`/`delete`/`check`
  action builders.
* `Aws::DynamoDB` — a minimal, typed DynamoDB client written for this shard: 17 operations with typed
  input/output shapes, SigV4 signing over a mutex-guarded connection pool, retries with full jitter,
  one error class per DynamoDB error code, pagination, table waiters, and response stubbing
  (`stub_responses`, `api_requests`, `before_request`) for tests.
* Full spec parity with the gem: 372/372 unit examples (descriptions match one for one) and 45/45
  Cucumber scenarios rewritten as `integration`-tagged specs that run against DynamoDB Local.
* Data written by this shard is byte-identical to data written by the Ruby gem, pinned by
  `spec/aws-record/wire_compat_spec.cr` (date, time, datetime and epoch formats; update expression
  placeholder tokens; empty string and empty set handling; `persist_nil`).

### Intentional differences from the Ruby gem

The complete list, with reasons, is in `docs/DIFFERENCES.md`.

* `class MyModel < Aws::Record::Base` replaces `include Aws::Record`.
* Modelling mistakes, unknown attributes and options an operation does not have are compile errors
  rather than runtime errors.
* Attribute names are `String` at run time (APIs accept `Symbol` too); numeric sets are
  `Set(BigDecimal)`; `date_attr`, `datetime_attr`, `time_attr` and `epoch_time_attr` all read as
  `Time?` while keeping the gem's wire formats.
* `Aws::Record::TimeParsing.parse` replaces Ruby's lenient `Date.parse`/`Time.parse`; custom formatters
  are `Proc(Time, String)`.
* Transactional write items are built by `Transactions.save/.put/.update/.delete/.check`;
  `Model.find_all` and `Model.transact_find` take an `Array(Hash(String, Aws::Record::RawValue))`.
* `increment_<name>!` and `#assign_attributes` honour `database_attribute_name`, where the gem does not.
* Credential resolution covers explicit values, the environment and `~/.aws/credentials`; IMDS, ECS,
  SSO and `AssumeRole` are not implemented.
