# Port status — aws-record 2.15.1 (c97f732) → aws-record-crystal

Updated: 2026-08-16. Gates: format ✅ ameba ✅ specs ✅ (246 examples) hygiene ✅ integration ✅ (phase 1 done)

## Phase 0 — Bootstrap

- [x] Scaffold replaced: `src/aws-record-crystal.cr`, `src/aws-record.cr`, `src/aws-record/version.cr`,
      `spec/spec_helper.cr`, `spec/spec_runner.cr`, `spec/aws-record/version_spec.cr`
- [x] Tooling: `shard.yml`, `.ameba.yml`, `.gitignore`, `scripts/*`, `docker/*`, `.github/workflows/ci.yml`
- [x] `compat/avram_app/` fixture (reduced; grows with the port)
- [x] `LICENSE` (Apache-2.0), `NOTICE`, `README.md`, `CHANGELOG.md`, `docs/DIFFERENCES.md`, `PORT_STATUS.md`
- [x] `scripts/setup.sh` → `bin/ameba` builds; `scripts/check.sh` green on the skeleton
- [x] `scripts/coverage.sh` runs

## Phase 1 — DynamoDB client (`Aws::DynamoDB`)

- [x] `value.cr` + `attribute_value.cr` (+ specs, incl. round-trip over all Value shapes) — 72 examples
- [x] `errors.cr` (+ specs) — 20 examples
- [x] `config.cr` + `credentials.cr` (+ specs, ENV isolation) — 44 examples
- [x] `types/*` — Input structs (`merge`/`to_wire`) + Output structs (`from_json`) — 29 examples
- [x] `http.cr` (connection pool, SigV4 signing, user agent)
- [x] `retry.cr` (+ specs) — 11 examples
- [x] `client.cr` — 17 operations
- [x] `paginator.cr` (+ specs) — 6 examples
- [x] `waiters.cr` (+ specs, in `client.cr`) — 8 examples
- [x] `stub.cr` — `stub_responses` / `api_requests` / `before_request` (+ specs) — 21 examples
- [x] `spec/aws-record/dynamodb/client_spec.cr` — webmock, exact wire JSON per operation — 33 examples
- [x] DynamoDB Local smoke test (`spec/integration/smoke_spec.cr`, green via `scripts/integration.sh`)

## Phase 2 — Marshalers + Attribute + time parsing (parity 0/106)

- [ ] `time_parsing.cr` (new; lenient parse cascade)
- [ ] `marshalers/marshaler.cr` (new abstract base)
- [ ] string_marshaler (0/9)
- [ ] boolean_marshaler (0/5)
- [ ] integer_marshaler (0/7)
- [ ] float_marshaler (0/7)
- [ ] date_marshaler (0/7)
- [ ] date_time_marshaler (0/10)
- [ ] time_marshaler (0/11)
- [ ] epoch_time_marshaler (0/11)
- [ ] list_marshaler (0/7)
- [ ] map_marshaler (0/7)
- [ ] string_set_marshaler (0/8)
- [ ] numeric_set_marshaler (0/8)
- [ ] `attribute.cr` + `DefaultMarshaler` (0/9)
- [ ] `spec/aws-record/wire_compat_spec.cr` (§4.6 table, every row)

## Phase 3 — Model core (parity 0/47)

- [ ] `errors.cr` (record layer)
- [ ] `key_attributes.cr`
- [ ] `model_attributes.cr`
- [ ] `item_data.cr`
- [ ] `client_configuration.cr` (0/2)
- [ ] `attributes.cr` (instance side) (0/27)
- [ ] `base.cr` — `Aws::Record::Base`, DSL macros, `__aws_record_finalize`, `RecordClassMethods` (0/18)
- [ ] compile-error fixtures (`spec/fixtures/compile_errors/*.cr`) + runner helper
- [ ] `scripts/compat_avram.sh` green with the full `compat/avram_app/src/app.cr`

## Phase 4 — Item operations + dirty tracking (parity 0/89)

- [ ] `dirty_tracking.cr` (0/52)
- [ ] `item_operations.cr` (0/37)

## Phase 5 — Query/scan, ItemCollection, BuildableSearch (parity 0/25)

- [ ] `item_collection.cr` (0/18)
- [ ] `buildable_search.cr`
- [ ] `query.cr` (0/7)

## Phase 6 — Secondary indexes, TableMigration, TableConfig (parity 0/79)

- [ ] `secondary_indexes.cr` (0/11)
- [ ] `table_migration.cr` (0/21)
- [ ] `table_config.cr` (0/47)

## Phase 7 — Batch + Transactions (parity 0/26)

- [ ] `batch_write.cr`, `batch_read.cr`, `batch.cr` (0/14)
- [ ] `transactions.cr` (0/12)

## Phase 8 — Integration specs (DynamoDB Local) (0/45 scenarios)

- [ ] tables (0/4), on_demand_tables (0/1)
- [ ] items (0/5), item_updates (0/5), item_default_values (0/1)
- [ ] secondary_indexes (0/2)
- [ ] search (0/6)
- [ ] batch (0/1)
- [ ] transactions (0/7)
- [ ] table_config (0/11)
- [ ] inheritance (0/2)

## Phase 9 — Docs, README, CHANGELOG, release hygiene

- [ ] README ported (usage, differences, Lucky/Avram, development) + compiling examples
- [ ] Doc comments complete; `crystal docs` clean
- [ ] CHANGELOG 0.1.0 entry
- [ ] `crystal tool unreachable` reviewed; `crystal tool macro_code_coverage` run once
- [ ] Final summary

## Parity table (unit)

| Ruby spec file | examples | ported | notes |
| --- | ---: | ---: | --- |
| record_spec.rb | 18 | 0 | |
| record/attribute_spec.rb | 9 | 0 | |
| record/attributes_spec.rb | 27 | 0 | |
| record/batch_spec.rb | 14 | 0 | |
| record/client_configuration_spec.rb | 2 | 0 | |
| record/dirty_tracking_spec.rb | 52 | 0 | |
| record/item_collection_spec.rb | 18 | 0 | |
| record/item_operations_spec.rb | 37 | 0 | |
| record/marshalers/boolean_marshaler_spec.rb | 5 | 0 | |
| record/marshalers/date_marshaler_spec.rb | 7 | 0 | |
| record/marshalers/date_time_marshaler_spec.rb | 10 | 0 | |
| record/marshalers/epoch_time_marshaler_spec.rb | 11 | 0 | |
| record/marshalers/float_marshaler_spec.rb | 7 | 0 | |
| record/marshalers/integer_marshaler_spec.rb | 7 | 0 | |
| record/marshalers/list_marshaler_spec.rb | 7 | 0 | |
| record/marshalers/map_marshaler_spec.rb | 7 | 0 | |
| record/marshalers/numeric_set_marshaler_spec.rb | 8 | 0 | |
| record/marshalers/string_marshaler_spec.rb | 9 | 0 | |
| record/marshalers/string_set_marshaler_spec.rb | 8 | 0 | |
| record/marshalers/time_marshaler_spec.rb | 11 | 0 | |
| record/query_spec.rb | 7 | 0 | |
| record/secondary_indexes_spec.rb | 11 | 0 | |
| record/table_config_spec.rb | 47 | 0 | |
| record/table_migration_spec.rb | 21 | 0 | |
| record/transactions_spec.rb | 12 | 0 | |
| **total** | **372** | **0** | |

## Coverage history

| phase | total % | lowest file | note |
| --- | --- | --- | --- |
| 0 | n/a | n/a | `src/` is only the version constant |

## Intentional differences (mirror of docs/DIFFERENCES.md, one line each)

- `class MyModel < Aws::Record::Base` replaces `include Aws::Record` (Crystal module metaclasses are not
  supertypes of including classes' metaclasses).

## Known limitations / follow-ups

- **Licensing needs maintainer confirmation.** The scaffold shipped MIT; the Ruby gem is Apache-2.0 with a
  `NOTICE`, and this port is a derivative work, so `LICENSE` was replaced with Apache-2.0 and a `NOTICE`
  crediting Amazon was added, and `shard.yml` says `license: Apache-2.0`. **Do not publish or tag before the
  maintainer confirms this.**
- Credential providers are limited to static / ENV / shared-file. IMDS, ECS, SSO and AssumeRole are out of
  scope for this port (documented as an extension point).

## Crystal gotchas found during the port (do not re-discover)

- `Tuple#each`'s block restriction is `Union(*T)`, which does **not** unify with a recursive alias:
  iterating a `Hash(String, Value)` as an enumerable fails to compile. Never let a `Hash(String, Value)`
  reach a generic `Enumerable` code path, and never destructure it with `|(key, value)|`.
- Crystal splits a union argument across overloads by *overload*, not by union member: an `Enumerable`
  overload receives every enumerable member of the union at once. Recognise them explicitly.
- `Item?` stringifies at macro time as `"Item | ::Nil"`; use `decl.type.types[0]` for the non-nil part.
- `def initialize(...) : Nil` is valid and is what satisfies ameba's `Typing/MethodReturnTypeRestriction`.
- ameba does not expand macros, so code generated by a macro is exempt from `Documentation` and `Typing`;
  the macro definition itself still needs a doc comment.
- `out` is a keyword: never name a local `out` (use `resp`/`output`).

## Session log

- 2026-08-15 — Phase 0 bootstrap: tooling, gates, scripts, CI, status file. Next: Phase 1 (`Aws::DynamoDB`
  client), starting with `value.cr` + `attribute_value.cr`.
- 2026-08-16 — Phase 1 complete: `Aws::DynamoDB` client (Value/AttributeValue, Errors, Config/Credentials,
  17 typed operations, SigV4 transport with a pooled connection, retries with full jitter, paginator,
  waiters, response stubbing) with 246 unit examples plus a DynamoDB Local smoke test.
  `crystal tool unreachable` is empty. Next: Phase 2 (marshalers + `Attribute` + time parsing).
