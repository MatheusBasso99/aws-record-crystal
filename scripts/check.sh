#!/usr/bin/env bash
# Usage: scripts/check.sh [--fast] [extra args for `crystal spec`]
set -euo pipefail
cd "$(dirname "$0")/.."
FAST=0; if [ "${1:-}" = "--fast" ]; then FAST=1; shift; fi
[ -x bin/ameba ] || scripts/setup.sh
echo "== format";  crystal tool format --check src spec examples compat/avram_app/src
echo "== hygiene"; scripts/hygiene.sh src
echo "== ameba";   ./bin/ameba
echo "== specs";   crystal spec --error-on-warnings --order random --tag '~integration' "$@"
if [ "$FAST" = 0 ]; then
  echo "== typecheck the single-entry spec runner (also what coverage/unreachable use)"
  crystal build --no-codegen spec/spec_runner.cr
  echo "== examples (every README sample)"
  crystal build --no-codegen examples/all_examples.cr
  echo "== docs";  crystal docs --output=docs/api >/dev/null
  echo "== unreachable (informational — review at phase boundaries, record in PORT_STATUS.md)"
  crystal tool unreachable --format json spec/spec_runner.cr | head -c 4000; echo
fi
echo "ALL GREEN"
