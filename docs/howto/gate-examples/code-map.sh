#!/usr/bin/env bash
# Proof: codegraph-map turns CodeGraph's nodes/edges rows into the codemap contract — it
# resolves node id -> qualified_name AND keeps only dependency-bearing edge types
# (calls/imports/inheritance), dropping the rest (here a "contains" edge must NOT survive).
# Prints CODE-MAP-OK. Fails before codegraph-map.js exists (spec-first).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
MAP="$ROOT/plugin/adapters/code/codegraph-map.js"
FX="$ROOT/plugin/adapters/code/fixtures"

out="$(node "$MAP" "$FX/codegraph-rows.json")"

# (1) resolves qualified_name, not raw numeric ids
echo "$out" | grep -q 'auth.go::Login'   || { echo "FAIL: did not resolve id -> qualified_name"; exit 1; }

# (2) the emitted edge set equals the expected set (order-insensitive) — this simultaneously
#     proves qualified_name resolution AND that the non-dependency "contains" edge was filtered out
node -e '
  const fs=require("fs");
  const got=JSON.parse(process.argv[1]).edges.map(e=>e[0]+"|"+e[1]);
  const exp=JSON.parse(fs.readFileSync(process.argv[2],"utf8")).edges.map(e=>e[0]+"|"+e[1]);
  const gs=new Set(got), es=new Set(exp);
  if(gs.size!==es.size){console.error("edge count mismatch",[...gs]);process.exit(1);}
  for(const k of es) if(!gs.has(k)){console.error("missing expected edge",k);process.exit(1);}
  for(const k of gs) if(!es.has(k)){console.error("unexpected edge (filter failed?)",k);process.exit(1);}
' "$out" "$FX/expected-codemap.json" || { echo "FAIL: codemap edges != expected (id-resolution or type-filter wrong)"; exit 1; }

# (3) explicitly assert the non-dependency "contains" pair (db.go::Query -> models.go::User) is gone
node -e '
  const got=JSON.parse(process.argv[1]).edges;
  if(got.some(e=>e[0]==="db.go::Query"&&e[1]==="models.go::User")){console.error("non-dependency contains edge survived");process.exit(1);}
' "$out" || { echo "FAIL: non-dependency edge was not filtered"; exit 1; }

echo "CODE-MAP-OK"
