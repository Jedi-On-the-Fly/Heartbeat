#!/usr/bin/env bash
# Proof for "Stop and resume a project": the event log is truth and state.json is a disposable
# projection, so a dead session is recovered by reprojecting — the completed work survives and
# the run continues from the NEXT task, not a redo. Drive the real hb CLI and prove:
#   1. complete phase 1, then simulate a dead session by DELETING state.json,
#   2. resume via rebuild: phase 1 is still completed (reconstructed from events, not memory),
#   3. the next tick points to phase 2's task (continue), not phase 1 (no redo).
# Prints STOP-RESUME-OK only when the completed work survives and the run continues.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

p="$(mktemp -d)"; trap 'rm -rf "$p"' EXIT
hb init "$p" >/dev/null 2>&1
python3 -c 'import json,sys;json.dump({"phases":[
  {"id":"P0","gate_entry":None,"gate_exit":"GATE_P0","tasks":[{"id":"P0T1","title":"make out1.txt"}]},
  {"id":"P1","gate_entry":"GATE_P0","gate_exit":"GATE_P1","tasks":[{"id":"P1T1","title":"make out2.txt"}]}],
  "gates":{"GATE_P0":{"desc":"p0","criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out1.txt\""}]},
           "GATE_P1":{"desc":"p1","criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out2.txt\""}]}}},open(sys.argv[1],"w"))' "$p/.hb/dag.json"
hb rebuild --dir "$p" >/dev/null 2>&1

# Complete phase 1.
hb start P0T1 --dir "$p" >/dev/null 2>&1; printf 'ok\n' > "$p/out1.txt"; hb done P0T1 --dir "$p" >/dev/null 2>&1; hb gate GATE_P0 --dir "$p" >/dev/null 2>&1
hb state --dir "$p" | python3 -c "import sys,json;sys.exit(0 if 'P0' in json.load(sys.stdin).get('completed_phases',[]) else 1)" \
  || fail "setup: phase 1 did not complete"

# 1. Simulate a dead session: the projection is gone.
rm -f "$p/.hb/state.json"
[ -f "$p/.hb/state.json" ] && fail "could not remove state.json"

# 2. Resume: `hb rebuild` reprojects the ON-DISK state.json from the event log. (Assert the
#    file rebuild WRITES — `hb state` alone would reproject in memory even without it, so it
#    wouldn't prove the resume step did anything.)
hb rebuild --dir "$p" >/dev/null 2>&1
[ -f "$p/.hb/state.json" ] || fail "resume: rebuild did not recreate state.json on disk"
python3 -c "import sys,json;sys.exit(0 if 'P0' in json.load(open('$p/.hb/state.json')).get('completed_phases',[]) else 1)" \
  || fail "after resume, the rebuilt state.json does not show completed phase 1 — state did not come from the event log"

# 3. The run CONTINUES from phase 2's task, not a redo of phase 1.
nxt="$(hb tick --dir "$p" 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['data'].get('reason'), (d['data'].get('next_task') or {}).get('id'))")"
[ "$nxt" = "next_task P1T1" ] || fail "after resume the tick did not continue to phase 2's task (got: $nxt)"

echo "STOP-RESUME-OK: state.json deleted; rebuild reconstructs completed phase 1 from the log and the run continues at P1T1."
