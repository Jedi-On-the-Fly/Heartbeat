#!/usr/bin/env bash
# Proof (real corpus): run docs-map over the repo's OWN markdown (docs/howto/) — real cross-linked
# docs — and assert a NON-EMPTY citation graph, node ≡ python (set-equal). A deterministic regression
# guard on real input (the analog of real-codegraph-map.sh for the docs provider — but no external
# tool, so it gates). Prints REAL-DOCS-MAP-OK.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
CORPUS="$ROOT/docs/howto"

jn="$(node "$ROOT/plugin/adapters/docs/docs-map.js" "$CORPUS")"
n="$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).edges.length))' "$jn")"
[ "$n" -gt 0 ] || { echo "FAIL: docs-map produced an EMPTY graph over the real corpus (parser regression?)"; exit 1; }

py="$(PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.docs.docs_map "$CORPUS")"
python3 -c '
import sys, json
a=json.loads(sys.argv[1]); b=json.loads(sys.argv[2])
sys.exit(0 if set(map(tuple,a["edges"]))==set(map(tuple,b["edges"])) and a["edges"] else 1)
' "$jn" "$py" || { echo "FAIL: docs-map differs node vs python on the real corpus"; exit 1; }

echo "REAL-DOCS-MAP-OK ($n citation edges over docs/howto/, node ≡ python)"
