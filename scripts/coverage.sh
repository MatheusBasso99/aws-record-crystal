#!/usr/bin/env bash
# Runs the whole unit-spec suite under kcov inside Docker and enforces the coverage gate.
# Env: COVERAGE_MIN (hard fail, default 85), COVERAGE_TARGET (goal, default 90).
set -euo pipefail
cd "$(dirname "$0")/.."
export COVERAGE_MIN=${COVERAGE_MIN:-85} COVERAGE_TARGET=${COVERAGE_TARGET:-90}
docker build -q -t aws-record-crystal-coverage -f docker/Dockerfile.coverage docker >/dev/null
docker run --rm --cap-add=SYS_PTRACE --security-opt seccomp=unconfined \
  -e COVERAGE_MIN -e COVERAGE_TARGET -v "$PWD":/work -w /work aws-record-crystal-coverage bash -c '
    set -e
    shards install --skip-postinstall --skip-executables >/dev/null
    mkdir -p bin && crystal build --debug -o bin/spec_runner spec/spec_runner.cr
    rm -rf coverage
    kcov --clean --include-path=/work/src --exclude-pattern=/work/lib,/work/spec \
         coverage ./bin/spec_runner --tag "~integration"
    python3 scripts/coverage_gate.py
  '
echo "HTML report: coverage/index.html"
