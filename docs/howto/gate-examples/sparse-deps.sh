#!/usr/bin/env bash
# Proof for "Write dependencies that don't over-constrain": over-constrained `requires` edges
# needlessly serialize work. Two lint-clean DAGs with the SAME three tasks — one chained
# A->B->C, one with only real deps — differ only in their edges, and hb ready proves it: the
# chained DAG offers 1 runnable task, the sparse one offers 3. Deterministic. Prints
# SPARSE-DEPS-OK only when both ready-set sizes match (1 and 3) and both DAGs lint clean.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

CHAINED='{"phases":[{"id":"P","title":"work","gate_entry":null,"gate_exit":"G","tasks":[{"id":"A","title":"produce A.out","requires":[]},{"id":"B","title":"produce B.out","requires":["A"]},{"id":"C","title":"produce C.out","requires":["B"]}]}],"gates":{"G":{"desc":"all","criteria":[{"id":"c","desc":"done","cmd":"true"}]}}}'
SPARSE='{"phases":[{"id":"P","title":"work","gate_entry":null,"gate_exit":"G","tasks":[{"id":"A","title":"produce A.out","requires":[]},{"id":"B","title":"produce B.out","requires":[]},{"id":"C","title":"produce C.out","requires":[]}]}],"gates":{"G":{"desc":"all","criteria":[{"id":"c","desc":"done","cmd":"true"}]}}}'

ready_count(){ # json -> number of runnable tasks at the start
  local p="$tmp/p"; rm -rf "$p"; bash "$ROOT/plugin/bootstrap.sh" "$p" >/dev/null 2>&1 </dev/null
  printf '%s' "$1" > "$p/.hb/dag.json"
  node "$ROOT/plugin/templates/hb-lint.js" "$p/.hb/dag.json" >/dev/null 2>&1 || { echo "LINT_ERR"; return; }
  node "$p/.hb/hb.js" rebuild >/dev/null 2>&1
  node "$p/.hb/hb.js" ready | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).length' 2>/dev/null
}

chained=$(ready_count "$CHAINED")
sparse=$(ready_count "$SPARSE")

[ "$chained" = "1" ] || { echo "FAIL: over-constrained DAG offered '$chained' runnable tasks, expected 1"; exit 1; }
[ "$sparse" = "3" ]  || { echo "FAIL: sparse DAG offered '$sparse' runnable tasks, expected 3"; exit 1; }

echo "SPARSE-DEPS-OK: same three tasks — chained requires gives 1 runnable, sparse gives 3 (both lint clean)."
