#!/usr/bin/env bash
# Proof for "Run tasks in parallel": HeartBeat fans independent tasks out concurrently, each
# in its OWN git worktree so writes can't collide, then merges them back and cleans up — and
# hb ready only ever hands out the truly-runnable set. Deterministic: a tiny stub worker, no
# model. Prints PARALLEL-FANOUT-OK only when every claim holds.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
command -v git  >/dev/null 2>&1 || { echo "git absent"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# A stub worker (the wire protocol): execute writes one distinct file per task; refute finds nothing.
stub="$tmp/stub.sh"
cat > "$stub" <<'STUBEOF'
#!/usr/bin/env bash
mode="$1"; payload="$(cat)"
case "$mode" in
  execute)
    id=$(printf '%s' "$payload" | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).task.id' 2>/dev/null)
    printf 'done\n' > "$id.out"
    printf '{"ok":true,"summary":"did %s"}\n' "$id" ;;
  refute) printf '{"refuted":false,"findings":"inspected the output; no hole."}\n' ;;
esac
STUBEOF

set_dag(){ # hbdir json  — overwrite the DAG and reproject
  printf '%s' "$2" > "$1/dag.json"
  node "$1/hb.js" rebuild >/dev/null 2>&1
}

# ── 1. hb ready hands out only the runnable set (excludes a requires-dependent task) ──
pr="$tmp/ready"; bash "$ROOT/plugin/bootstrap.sh" "$pr" >/dev/null 2>&1 </dev/null
hr="$pr/.hb"
set_dag "$hr" '{"phases":[{"id":"P","title":"deps","gate_entry":null,"gate_exit":"G","tasks":[{"id":"A","title":"produce A.out","requires":[]},{"id":"B","title":"produce B.out","requires":[]},{"id":"C","title":"produce C.out","requires":["A"]}]}],"gates":{"G":{"desc":"all","criteria":[{"id":"c","desc":"all","cmd":"true"}]}}}'
ready_ids=$(node "$hr/hb.js" ready | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).map(t=>t.id).sort().join(",")' 2>/dev/null)
[ "$ready_ids" = "A,B" ] || { echo "FAIL: ready set was '$ready_ids', expected 'A,B' (C requires A, must be excluded)"; exit 1; }

# ── 2. worktree-isolated concurrent fan-out: two independent tasks, distinct files, clean merge ──
pw="$tmp/wt"; HB_NO_GIT="" bash "$ROOT/plugin/bootstrap.sh" "$pw" >/dev/null 2>&1 </dev/null
hw="$pw/.hb"
set_dag "$hw" '{"phases":[{"id":"WP","title":"iso","gate_entry":null,"gate_exit":"GWP","tasks":[{"id":"WA","title":"produce WA.out","requires":[]},{"id":"WB","title":"produce WB.out","requires":[]}]}],"gates":{"GWP":{"desc":"both merged","criteria":[{"id":"c","desc":"both files","cmd":"test -f \"$PROJECT_DIR/WA.out\" && test -f \"$PROJECT_DIR/WB.out\""}]}}}'
out=$(HB_NO_GIT="" HB_MAX_CONCURRENCY=2 HB_EXEC_CMD="bash $stub" HB_EXEC_MAX_ITERS=15 node "$hw/hb-exec.js" run 2>&1)

printf '%s' "$out" | grep -q "worktree-isolated" || { echo "FAIL: run was not worktree-isolated"; echo "$out"; exit 1; }
[ -f "$pw/WA.out" ] && [ -f "$pw/WB.out" ] || { echo "FAIL: both tasks' distinct files were not merged into the main tree"; exit 1; }
[ -z "$(ls -A "$hw/wt" 2>/dev/null)" ] || { echo "FAIL: worktrees were not cleaned up"; exit 1; }
[ -z "$(git -C "$pw" branch --list 'hb-exec/*')" ] || { echo "FAIL: temp branches were not cleaned up"; exit 1; }

echo "PARALLEL-FANOUT-OK: hb ready gives only the runnable set; worktree-isolated fan-out merged both distinct files and cleaned up."
