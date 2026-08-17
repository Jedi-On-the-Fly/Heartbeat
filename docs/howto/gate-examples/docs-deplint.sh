#!/usr/bin/env bash
# Proof: the docs/research adapter proves the generalization — docs-map turns a markdown CITATION
# graph into the SAME codemap contract, and the UNCHANGED code deplint.js validates a docs authoring
# DAG on it. It asserts: (1) docs-map emits the FULL codemap (edges + tasks) equal to the fixture —
# citer->cited edges, external/non-corpus links excluded, one task per section; (2) the unchanged
# engine on docs data reports a correctly-DIRECTED missing (citing task requires cited task, not the
# reverse) on the unordered plan and clean on the ordered plan. Fails before docs-map.js exists.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
DM="$ROOT/plugin/adapters/docs/docs-map.js"
DL="$ROOT/plugin/adapters/code/deplint.js"      # the UNCHANGED code engine — reused as-is
FX="$ROOT/plugin/adapters/docs/fixtures"

# (1) docs-map emits the FULL codemap (edges AND tasks) == expected; external link excluded
got="$(node "$DM" "$FX/corpus")"
node -e '
  const fs=require("fs");
  const g=JSON.parse(process.argv[1]), e=JSON.parse(fs.readFileSync(process.argv[2],"utf8"));
  const es=a=>new Set((a||[]).map(x=>x[0]+"|"+x[1]));
  const ge=es(g.edges), ee=es(e.edges);
  if(ge.size!==ee.size){console.error("edge count mismatch",[...ge]);process.exit(1);}
  for(const k of ee) if(!ge.has(k)){console.error("missing edge",k);process.exit(1);}
  for(const k of ge) if(!ee.has(k)){console.error("unexpected edge",k);process.exit(1);}
  const keys=o=>Object.keys(o||{}).sort().join(",");
  if(keys(g.tasks)!==keys(e.tasks)){console.error("task keys mismatch",keys(g.tasks));process.exit(1);}
  for(const k of Object.keys(e.tasks)) if((g.tasks[k]||[]).join(",")!==e.tasks[k].join(",")){console.error("task map mismatch",k);process.exit(1);}
' "$got" "$FX/docs.codemap.json" || { echo "FAIL: docs-map output != expected (edges or tasks)"; exit 1; }
# the remote URL https://example.com/results.md (basename collides with corpus id 'results') must
# NOT become a phantom local edge — this makes the http filter load-bearing (a real negative test)
node -e 'const g=JSON.parse(process.argv[1]); if((g.edges||[]).some(e=>e[0]==="method"&&e[1]==="results")){process.exit(1)}' "$got" \
  || { echo "FAIL: a remote .md URL leaked a phantom edge (http filter not load-bearing)"; exit 1; }

# (2) the UNCHANGED engine generalizes — correctly directed missing on unordered, clean on ordered
un="$(node "$DL" "$FX/docs-unordered.dag.json" "$FX/docs.codemap.json")"
echo "$un" | grep -qE 'missing=[1-9]'                     || { echo "FAIL: no missing on the unordered docs plan"; exit 1; }
echo "$un" | grep -q 'method should require background'   || { echo "FAIL: missing suggestion wrong/undirected"; exit 1; }
echo "$un" | grep -q 'background should require method'    && { echo "FAIL: reversed (backwards) suggestion present"; exit 1; } || true
node "$DL" "$FX/docs-clean.dag.json" "$FX/docs.codemap.json" | grep -q 'missing=0' || { echo "FAIL: clean docs plan reported a missing edge"; exit 1; }

echo "DOCS-DEPLINT-OK"
