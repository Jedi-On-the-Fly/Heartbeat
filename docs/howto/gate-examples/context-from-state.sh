#!/usr/bin/env bash
# Proof for "Keep worker context derived from settled reality": the context the driver hands a
# worker is computed from CURRENT state each time — it reflects what is already done and the
# gate's definition of done — not a stale, carried-over narrative. Drive the real
# assemble_context and prove:
#   1. before a sibling task is done, the context for the next task has no "already completed" note,
#   2. after it is done, the context DOES (recomputed from settled state, so it changed),
#   3. the context always carries the phase's gate criteria (build to pass).
# Prints CONTEXT-FROM-STATE-OK only when the context changes with state and carries the gate.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

p="$(mktemp -d)"; trap 'rm -rf "$p"' EXIT
hb init "$p" >/dev/null 2>&1
python3 -c 'import json,sys;json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_P0","tasks":[{"id":"T1","title":"first"},{"id":"T2","title":"second","requires":["T1"]}]}],"gates":{"GATE_P0":{"desc":"g","criteria":[{"id":"c1","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},open(sys.argv[1],"w"))' "$p/.hb/dag.json"
hb rebuild --dir "$p" >/dev/null 2>&1

# assemble_context for T2, from the REAL executor, given the current state.
ctx(){ python3 -c "import sys;sys.path.insert(0,'$ROOT/py/src');from heartbeat import executor;print(executor.assemble_context('$p/.hb',{'id':'T2','phase':'P0','title':'second'}))"; }

before="$(ctx)"
printf '%s' "$before" | grep -qi 'already completed' && fail "context claims work already done before anything ran — not from settled state"
printf '%s' "$before" | grep -q 'GATE_P0' || fail "context does not carry the phase's gate (the definition of done)"

# Do T1 -> the settled state changes.
hb start T1 --dir "$p" >/dev/null 2>&1; hb done T1 --dir "$p" >/dev/null 2>&1

after="$(ctx)"
printf '%s' "$after" | grep -qi 'already completed in this phase: .*T1' || fail "context did not reflect the newly-completed T1 — it is not recomputed from settled state"
[ "$before" != "$after" ] || fail "the context did not change when the state changed — it is stale, not state-derived"

echo "CONTEXT-FROM-STATE-OK: the worker context is recomputed from settled state (it gains the completed T1) and always carries the gate."
