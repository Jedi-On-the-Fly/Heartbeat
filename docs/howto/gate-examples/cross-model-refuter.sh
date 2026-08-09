#!/usr/bin/env bash
# Proof for the cross-model refuter: the adversarial `refute` runs on a DIFFERENT backend/model
# than the `execute` doer. Deterministic — a doer stub + a DISTINCT refuter stub over the script
# wire, no model/network. Asserts (both runtimes) that the REFUTER stub (not the doer) produced the
# stored review, under a distinct actor, with the refuter identity recorded; that the model override
# reaches the refute call end-to-end; and that WITHOUT a distinct refuter the doer does the refute
# (backward compatible). Prints CROSS-MODEL-REFUTER-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
command -v node    >/dev/null 2>&1 || { echo "node absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# ── stubs (script-wire: argv1 = execute|refute, stdin = payload JSON, stdout = one JSON line) ──
bindir="$work/bin"; mkdir -p "$bindir"
cat > "$bindir/doer" <<'STUB'
#!/usr/bin/env bash
mode="${1:-execute}"; cat >/dev/null 2>&1 || true
if [ "$mode" = execute ]; then echo ok > out.txt; echo '{"ok":true,"summary":"doer-stub did the task"}'
else echo "{\"refuted\":false,\"findings\":\"DOER-STUB attempt on GATE_P0: examined the phase and could not refute (model=${HB_EXEC_MODEL:-none})\"}"; fi
STUB
cat > "$bindir/refuter" <<'STUB'
#!/usr/bin/env bash
mode="${1:-execute}"; cat >/dev/null 2>&1 || true
if [ "$mode" = execute ]; then echo '{"ok":false,"summary":"refuter must not execute"}'
else echo "{\"refuted\":false,\"findings\":\"REFUTER-STUB (distinct model) attempt on GATE_P0: could not refute; saw model=${HB_EXEC_MODEL:-none}\"}"; fi
STUB
chmod +x "$bindir/doer" "$bindir/refuter"

# review-gated project: P0 / GATE_P0 (review block + a passing behavioral criterion)
write_dag(){ python3 -c 'import json,sys;json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_P0","tasks":[{"id":"T1","title":"produce out.txt"}]}],"gates":{"GATE_P0":{"desc":"g","review":{"prompt":"Refute that GATE_P0 is truly complete."},"criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},open(sys.argv[1],"w"))' "$1"; }
mkproj_py(){ local p; p="$(mktemp -d)"; hb init "$p" >/dev/null 2>&1; write_dag "$p/.hb/dag.json"; hb rebuild --dir "$p" >/dev/null 2>&1; echo "$p"; }
done_P0(){ hb state --dir "$1" | python3 -c "import sys,json;sys.exit(0 if 'P0' in json.load(sys.stdin).get('completed_phases',[]) else 1)"; }

# ── PY: doer + a DISTINCT refuter (with a model override) ─────────────────────
p="$(mkproj_py)"
PATH="$bindir:$PATH" HB_EXEC_CMD="doer" HB_REFUTE_CMD="refuter" HB_REFUTE_MODEL="SENTINEL-MODEL" \
  HB_EXEC_MAX_ITERS=30 hb exec run --dir "$p" >/dev/null 2>&1
done_P0 "$p" || fail "py: phase did not complete under a distinct refuter"
art="$p/.hb/reviews/GATE_P0.attempt.md"
[ -f "$art" ] || fail "py: no review artifact written"
grep -q "REFUTER-STUB" "$art" || fail "py: the refuter did not run the refute (no REFUTER-STUB in the artifact)"
grep -q "SENTINEL-MODEL" "$art" || fail "py: the model override did not reach the refute call"
grep -q "DOER-STUB" "$art" && fail "py: the DOER ran the refute (cross-model routing failed)"
grep -q "^Refuter:" "$art" || fail "py: refuter provenance not recorded"
python3 - "$p" <<'PY' || fail "py: reviewer actor not distinct from the doer"
import json, sys
evs = [json.loads(l) for l in open(sys.argv[1] + "/.hb/events.jsonl") if l.strip()]
doer_actors = {e.get("actor") for e in evs if e.get("event") == "task_done"}
rev = [e for e in evs if e.get("event") == "review_passed"]
assert rev and rev[-1].get("reviewer") and rev[-1]["reviewer"] not in doer_actors, (rev, doer_actors)
PY
rm -rf "$p"

# ── PY control: no distinct refuter -> the DOER does the refute (backward compat) ──
p="$(mkproj_py)"
PATH="$bindir:$PATH" HB_EXEC_CMD="doer" HB_EXEC_MAX_ITERS=30 hb exec run --dir "$p" >/dev/null 2>&1
grep -q "DOER-STUB" "$p/.hb/reviews/GATE_P0.attempt.md" || fail "control: without HB_REFUTE_CMD the doer did not do the refute (backward compat broken)"
rm -rf "$p"

# ── PLUGIN: doer + a DISTINCT refuter (cmd + model override) ──────────────────
pg="$work/plugin-proj"
bash "$ROOT/plugin/bootstrap.sh" "$pg" >/dev/null 2>&1 </dev/null
write_dag "$pg/.hb/dag.json"; node "$pg/.hb/hb.js" rebuild >/dev/null 2>&1
PATH="$bindir:$PATH" HB_EXEC_CMD="doer" HB_REFUTE_CMD="refuter" HB_REFUTE_MODEL="SENTINEL-MODEL" \
  HB_EXEC_MAX_ITERS=30 node "$pg/.hb/hb-exec.js" run >/dev/null 2>&1
part="$pg/.hb/reviews/GATE_P0.attempt.md"
[ -f "$part" ] || fail "plugin: no review artifact written"
grep -q "REFUTER-STUB" "$part" || fail "plugin: the refuter did not run the refute"
grep -q "SENTINEL-MODEL" "$part" || fail "plugin: the model override did not reach the refute call"
grep -q "DOER-STUB" "$part" && fail "plugin: the DOER ran the refute (cross-model routing failed)"

echo "CROSS-MODEL-REFUTER-OK: the refuter runs on a distinct backend/model from the doer (both runtimes), under a distinct actor, with provenance; the doer refutes only when no distinct refuter is set."
