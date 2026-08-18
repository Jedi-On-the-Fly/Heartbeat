#!/usr/bin/env bash
# Parity proof: codegraph-map is node ≡ python — the same codemap edges (compared as a SET, since
# row/edge order can differ). Fails before the Python module exists (spec-first).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
FX="$ROOT/plugin/adapters/code/fixtures"

jn="$(node "$ROOT/plugin/adapters/code/codegraph-map.js" "$FX/codegraph-rows.json")"
py="$(PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.code.codegraph_map "$FX/codegraph-rows.json")"
python3 -c '
import sys, json
a = json.loads(sys.argv[1]); b = json.loads(sys.argv[2])
sa = set(map(tuple, a.get("edges", []))); sb = set(map(tuple, b.get("edges", [])))
sys.exit(0 if sa == sb and sa else 1)
' "$jn" "$py" || { echo "FAIL: codegraph-map edges differ node vs python"; printf 'NODE=%s\nPY=%s\n' "$jn" "$py"; exit 1; }

echo "CODEGRAPH-MAP-PARITY-OK"
