#!/usr/bin/env bash
# Parity proof: discovery is node ≡ python — BYTE-identical stdout on the same codemap for every
# direction (deterministic sorted output). Fails before the Python module exists (spec-first).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
FX="$ROOT/plugin/adapters/code/fixtures/discover-codemap.json"

for spec in "dependents repo" "dependencies repo" "both repo" "dependents a"; do
  set -- $spec; dir="$1"; entry="$2"
  jn="$(node "$ROOT/plugin/adapters/code/codegraph-discover.js" "$FX" "$entry" "--$dir")"
  py="$(PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.code.codegraph_discover "$FX" "$entry" "--$dir")"
  [ "$jn" = "$py" ] || { echo "FAIL: node != python for --$dir $entry"; printf 'NODE=%s\nPY=%s\n' "$jn" "$py"; exit 1; }
done

echo "CODE-DISCOVER-PARITY-OK"
