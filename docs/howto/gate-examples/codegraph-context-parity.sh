#!/usr/bin/env bash
# Parity proof: codegraph-context is node ≡ python — BYTE-IDENTICAL rendered subgraph text.
# Fails before the Python module exists (spec-first).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
FX="$ROOT/plugin/adapters/code/fixtures"

jn="$(node "$ROOT/plugin/adapters/code/codegraph-context.js" "$FX/context.codemap.json" TA)"
py="$(PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.code.codegraph_context "$FX/context.codemap.json" TA)"
[ "$jn" = "$py" ] || { echo "FAIL: codegraph-context text differs node vs python"; diff <(printf '%s' "$jn") <(printf '%s' "$py"); exit 1; }

echo "CODEGRAPH-CONTEXT-PARITY-OK"
