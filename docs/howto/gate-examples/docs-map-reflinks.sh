#!/usr/bin/env bash
# Proof: docs-map captures REFERENCE-STYLE citations (`[text][ref]` + collapsed `[text][]` with
# `[ref]: x.md` definitions), not only inline `[](x.md)` — an inline-only parser silently drops them
# (the same class as the code adapter's dropped edge kinds). Inline links still work (regression).
# node ≡ python (set-equal). Prints DOCS-REFLINKS-OK. Fails before docs-map learns reference links.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
FX="$ROOT/plugin/adapters/docs/fixtures/refcorpus"

jn="$(node "$ROOT/plugin/adapters/docs/docs-map.js" "$FX")"
# a→b (ref [m]), a→c (collapsed [background][]), a→d (inline) must all be present
for pair in "a b" "a c" "a d"; do
  set -- $pair
  node -e '
    const es=JSON.parse(process.argv[1]).edges.map(e=>e[0]+"|"+e[1]);
    if(!es.includes(process.argv[2]+"|"+process.argv[3])){console.error("missing citation edge",process.argv[2]+"->"+process.argv[3],es);process.exit(1);}
  ' "$jn" "$1" "$2" || { echo "FAIL: docs-map dropped the $1->$2 citation"; exit 1; }
done

# node ≡ python (set-equal — order may differ)
py="$(PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.docs.docs_map "$FX")"
python3 -c '
import sys, json
a=json.loads(sys.argv[1]); b=json.loads(sys.argv[2])
sys.exit(0 if set(map(tuple,a["edges"]))==set(map(tuple,b["edges"])) else 1)
' "$jn" "$py" || { echo "FAIL: docs-map edges differ node vs python"; printf 'NODE=%s\nPY=%s\n' "$jn" "$py"; exit 1; }

echo "DOCS-REFLINKS-OK"
