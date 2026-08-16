# aws-record-crystal

Object mapping abstraction for [Amazon DynamoDB](https://aws.amazon.com/dynamodb/) — a Crystal port of
Amazon's [`aws-record`](https://github.com/aws/aws-record-ruby) Ruby gem (version 2.15.1).

It ships its own minimal, typed DynamoDB client (`Aws::DynamoDB`) so the shard has no dependency on
an AWS SDK for Crystal (there isn't one).

> **Status: work in progress.** See [`PORT_STATUS.md`](PORT_STATUS.md) for what is done and what is next,
> and [`docs/DIFFERENCES.md`](docs/DIFFERENCES.md) for every intentional behavior difference from the Ruby gem.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  aws-record-crystal:
    github: matheusbasso/aws-record-crystal
```

Then run `shards install`.

## Usage

```crystal
require "aws-record-crystal"

class Forum < Aws::Record::Base
  string_attr :forum_uuid, hash_key: true
  integer_attr :post_count
  string_set_attr :tags
end
```

Full usage documentation lands in Phase 9 of the port (see `PORT_STATUS.md`).

## Development

Requires Crystal 1.21.0 or newer. Docker is used for coverage and the integration suite.

```bash
scripts/setup.sh        # shards install + build bin/ameba
scripts/check.sh        # format, namespace hygiene, ameba, specs, docs (the gate)
scripts/check.sh --fast # same without docs/unreachable
scripts/coverage.sh     # kcov coverage in Docker (gate: >= 90%)
scripts/integration.sh  # integration specs against DynamoDB Local
scripts/compat_avram.sh # type-check alongside Avram/Lucky
```

## License

Apache-2.0. This project is a derivative work of `aws-record`, Copyright 2016 Amazon.com, Inc. or its
affiliates — see [`NOTICE`](NOTICE).
