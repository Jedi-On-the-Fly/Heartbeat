#!/usr/bin/env bash
# Parity proof: docs-map is node ≡ python — the same codemap (edges as a SET + tasks as a map,
# order-insensitive, since file-scan order differs across runtimes/OS). Fails before the Python
# module exists (spec-first).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
FX="$ROOT/plugin/adapters/docs/fixtures"

jn="$(node "$ROOT/plugin/adapters/docs/docs-map.js" "$FX/corpus")"
py="$(PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.docs.docs_map "$FX/corpus")"
python3 -c '
import sys, json
a = json.loads(sys.argv[1]); b = json.loads(sys.argv[2])
ea = set(map(tuple, a.get("edges", []))); eb = set(map(tuple, b.get("edges", [])))
ta = {k: tuple(v) for k, v in (a.get("tasks") or {}).items()}
tb = {k: tuple(v) for k, v in (b.get("tasks") or {}).items()}
sys.exit(0 if ea == eb and ea and ta == tb and ta else 1)
' "$jn" "$py" || { echo "FAIL: docs-map codemap differs node vs python"; printf 'NODE=%s\nPY=%s\n' "$jn" "$py"; exit 1; }

echo "DOCS-MAP-PARITY-OK"
