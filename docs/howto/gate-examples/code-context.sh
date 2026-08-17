#!/usr/bin/env bash
# Proof: codegraph-context emits a real SUBGRAPH for a task — the symbols it touches AND their
# DIRECT graph neighbors (dependencies + dependents) — not an echo of the task's own symbols and
# not the whole graph. Fixture context.codemap.json: task TA touches symA; symA depends on symB
# and is used by symZ (both direct neighbors); symU only touches symB (NOT a neighbor of symA).
# So the block must name symA, symB, symZ and must NOT name symU. Fails before the provider exists.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
CC="$ROOT/plugin/adapters/code/codegraph-context.js"
FX="$ROOT/plugin/adapters/code/fixtures"

out="$(node "$CC" "$FX/context.codemap.json" TA)"
echo "$out" | grep -q 'symA' || { echo "FAIL: missing the touched symbol symA";        exit 1; }
echo "$out" | grep -q 'symB' || { echo "FAIL: missing the dependency neighbor symB";    exit 1; }
echo "$out" | grep -q 'symZ' || { echo "FAIL: missing the dependent neighbor symZ";      exit 1; }
echo "$out" | grep -q 'symU' && { echo "FAIL: unrelated symbol symU leaked into the subgraph"; exit 1; } || true

echo "CODE-CONTEXT-OK"
