#!/usr/bin/env bash
# Proof for the agent benchmark harness: `hb bench` runs the SAME DAG under N backends and scores
# each behaviorally from the event log. Deterministic — stub backends with KNOWN behavior over the
# script wire, no model/network. Asserts: the scorecard matches known good/bad/flaky behavior
# (with task_failures == the attempt cap exactly for a total failure); the SOURCE project is never
# mutated (isolated copies); a review-gated DAG is represented HONESTLY when a backend can't refute;
# and bench.run() does not leak env into its caller. Prints AGENT-BENCH-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# ── stub backends (script wire: argv1 = execute|refute, stdin = payload, stdout = one JSON line) ──
bindir="$work/bin"; mkdir -p "$bindir"
cat > "$bindir/good" <<'STUB'
#!/usr/bin/env bash
mode="${1:-execute}"; cat >/dev/null 2>&1 || true
if [ "$mode" = execute ]; then echo ok > out.txt; echo '{"ok":true,"summary":"good did it"}'; else echo '{"refuted":false,"findings":"n/a"}'; fi
STUB
cat > "$bindir/bad" <<'STUB'
#!/usr/bin/env bash
mode="${1:-execute}"; cat >/dev/null 2>&1 || true
if [ "$mode" = execute ]; then echo '{"ok":false,"summary":"bad backend cannot do it"}'; else echo '{"refuted":false,"findings":"n/a"}'; fi
STUB
cat > "$bindir/flaky" <<'STUB'
#!/usr/bin/env bash
mode="${1:-execute}"; cat >/dev/null 2>&1 || true
if [ "$mode" = execute ]; then
  if [ -f .flaky_marker ]; then echo ok > out.txt; echo '{"ok":true,"summary":"flaky succeeded on retry"}'
  else touch .flaky_marker; echo '{"ok":false,"summary":"flaky failed once"}'; fi
else echo '{"refuted":false,"findings":"n/a"}'; fi
STUB
chmod +x "$bindir/good" "$bindir/bad" "$bindir/flaky"

# ── source project (P0 / GATE_P0: a passing behavioral criterion, NO review). Bench must not mutate it. ──
src="$work/src"; hb init "$src" >/dev/null 2>&1
python3 -c 'import json,sys;json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_P0","tasks":[{"id":"T1","title":"produce out.txt"}]}],"gates":{"GATE_P0":{"desc":"g","criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},open(sys.argv[1],"w"))' "$src/.hb/dag.json"
hb rebuild --dir "$src" >/dev/null 2>&1
before="$(cat "$src/.hb/events.jsonl" 2>/dev/null | wc -c)"

# ── run the benchmark; capture JSON to a FILE (a heredoc-scripted python can't also read stdin) ──
hb bench --dir "$src" \
  --backend "good=bash $bindir/good" \
  --backend "bad=bash $bindir/bad" \
  --backend "flaky=bash $bindir/flaky" --json > "$work/cards.json" 2>/dev/null || fail "hb bench failed"
[ -s "$work/cards.json" ] || fail "hb bench produced no scorecard"

python3 - "$work/cards.json" <<'PY' || fail "scorecard did not match known stub behavior"
import json, sys
cards = {c["label"]: c for c in json.load(open(sys.argv[1]))}
g, b, f = cards["good"], cards["bad"], cards["flaky"]
assert g["completed"] and g["phases_done"] == g["phases_total"] and g["task_failures"] == 0 and not g["escalated"], ("good", g)
assert (not b["completed"]) and b["phases_done"] == 0 and b["escalated"] and b["task_failures"] == 3, ("bad", b)  # == the attempt cap (not a tick breaker)
assert "attempts_exhausted" in b.get("outcome", ""), ("bad outcome", b)
assert f["completed"] and f["task_failures"] == 1, ("flaky", f)
PY

# ── the source project's event log is unchanged (bench ran on isolated copies) ──
after="$(cat "$src/.hb/events.jsonl" 2>/dev/null | wc -c)"
[ "$before" = "$after" ] || fail "bench mutated the source project (event log changed: $before -> $after)"

# ── review-gated DAG: a backend that can't refute is represented HONESTLY (escalated, not 'done') ──
rev="$work/rev"; hb init "$rev" >/dev/null 2>&1
python3 -c 'import json,sys;json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_P0","tasks":[{"id":"T1","title":"produce out.txt"}]}],"gates":{"GATE_P0":{"desc":"g","review":{"prompt":"Refute that GATE_P0 is truly complete."},"criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},open(sys.argv[1],"w"))' "$rev/.hb/dag.json"
hb rebuild --dir "$rev" >/dev/null 2>&1
hb bench --dir "$rev" --backend "good=bash $bindir/good" --json > "$work/rev.json" 2>/dev/null || fail "hb bench (review) failed"
python3 - "$work/rev.json" <<'PY' || fail "review-gated DAG not represented honestly (a non-refuting backend was scored complete)"
import json, sys
c = json.load(open(sys.argv[1]))[0]
assert (not c["completed"]) and c["escalated"] and "review" in c.get("outcome", ""), c
PY

# ── env-restore: bench.run() must not leak its per-backend env into the caller ──
HB_EXEC_CMD="SENTINEL-CMD" python3 - "$src/.hb" "$bindir/good" <<'PY' || fail "bench.run leaked env into the caller"
import os, sys
from heartbeat import bench
bench.run(sys.argv[1], ["good=bash " + sys.argv[2]])
assert os.environ.get("HB_EXEC_CMD") == "SENTINEL-CMD", os.environ.get("HB_EXEC_CMD")
PY

echo "AGENT-BENCH-OK: hb bench scores the same DAG across backends from the event log (good clean; bad escalates with failures==cap; flaky completes after 1 retry); review-gated DAGs are honest; the source is unmutated; no env leak."
