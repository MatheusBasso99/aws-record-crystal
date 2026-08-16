#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../compat/avram_app"
shards install --skip-postinstall --skip-executables
crystal build --no-codegen --error-on-warnings src/app.cr
echo "compat-avram: OK (Avram $(grep -A1 'name: avram' lib/avram/shard.yml | tail -1 | awk '{print $2}') + aws-record-crystal type-check together)"
