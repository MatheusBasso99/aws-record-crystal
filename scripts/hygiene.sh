#!/usr/bin/env bash
# Namespace hygiene (CLAUDE.md §5.10): (1) every column-0 line in src/**/*.cr is a require, a comment,
# `end`, or a definition under Aws; (2) no reopening of stdlib / third-party types anywhere in src/.
set -uo pipefail
SRC=${1:-src}
bad1=$(grep -rnE '^\S' --include='*.cr' "$SRC" | grep -vE ':(require |#|end$|module Aws( |::|$)|(abstract )?class Aws::|(abstract )?struct Aws::|alias Aws::|enum Aws::|annotation Aws::|lib Aws)')
bad2=$(grep -rnE '^\s*(abstract )?(class|struct|module|enum) (Object|Reference|Value|Struct|Class|String|Time|Hash|Array|Set|Deque|Int|Int8|Int16|Int32|Int64|Int128|UInt|UInt8|UInt16|UInt32|UInt64|Float|Float32|Float64|Bool|Nil|Char|Slice|Bytes|Symbol|Tuple|NamedTuple|Proc|Pointer|Enumerable|Iterator|Iterable|Indexable|Comparable|Number|JSON|YAML|HTTP|URI|Log|IO|Exception|BigDecimal|BigInt|BigFloat|BigRational|UUID|Random|Mutex|Fiber|Channel|Process|File|Dir|Path|ENV|Crystal|Spec|WebMock|Awscr|Base64|Digest|OpenSSL|Socket|Regex|Range|Math|GC|Atomic|Time::|JSON::|HTTP::|Log::)\b' --include='*.cr' "$SRC")
if [ -n "$bad1$bad2" ]; then echo "NAMESPACE HYGIENE VIOLATIONS:"; echo "$bad1"; echo "$bad2"; exit 1; fi
echo "namespace hygiene: OK"
