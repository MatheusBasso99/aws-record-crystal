#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
shards install
shards build ameba          # -> bin/ameba (1.7.0-dev). NEVER use the brew ameba (1.6.4) — false Lint/Syntax on 1.21 code.
./bin/ameba --version
