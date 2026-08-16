# Intentional differences from the `aws-record` Ruby gem

Every deviation from the Ruby gem's behavior or API is recorded here, with the reason.
Spec files that assert a divergent behavior carry a comment pointing at the relevant section.

## Model definition

- **`class MyModel < Aws::Record::Base` instead of `include Aws::Record`.** Crystal module metaclasses are
  not supertypes of the including classes' metaclasses, so heterogeneous collections of *model classes*
  (`BatchRead`'s table→class map, `Transactions.transact_find`, `ItemCollection#multi_model_filter`,
  `TableConfig#model_class`) are impossible with a module. An abstract base class makes all of them work.

## Types

## Time and dates

## Client and options

## Errors

## Spec techniques

## Not implemented (out of scope)
