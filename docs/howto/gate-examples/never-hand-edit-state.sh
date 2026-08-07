#!/usr/bin/env bash
# Proof for "Never hand-edit HeartBeat state": state.json is a derived projection of the event
# log — edit it by hand and HeartBeat notices and overwrites it. Drive the real hb CLI:
#   1. complete a phase, then hand-edit state.json to a wrong-but-valid value,
#   2. hb doctor flags the drift ("differs from the event-log projection"),
#   3. the CLI (rebuild) overwrites the hand-edit back to the true projection — the log wins,
#   4. control: an in-sync state.json produces no drift.
# Prints STATE-DISCIPLINE-OK only when the drift is flagged and the log discards the edit.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }
has_P0(){ python3 -c "import sys,json;sys.exit(0 if 'P0' in json.load(open('$1')).get('completed_phases',[]) else 1)"; }

p="$(mktemp -d)"; trap 'rm -rf "$p"' EXIT
hb init "$p" >/dev/null 2>&1
python3 -c 'import json,sys;json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_P0","tasks":[{"id":"T1","title":"make out.txt"}]}],"gates":{"GATE_P0":{"desc":"g","criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},open(sys.argv[1],"w"))' "$p/.hb/dag.json"
hb rebuild --dir "$p" >/dev/null 2>&1
hb start T1 --dir "$p" >/dev/null 2>&1; printf 'ok\n' > "$p/out.txt"; hb done T1 --dir "$p" >/dev/null 2>&1; hb gate GATE_P0 --dir "$p" >/dev/null 2>&1
has_P0 "$p/.hb/state.json" || fail "setup: phase P0 did not complete"

# 4 (control first): in sync -> no drift.
hb doctor --dir "$p" 2>&1 | grep -qi 'differs from the event-log projection' && fail "control: doctor reports drift on an in-sync state.json"

# 1. Hand-edit state.json to a wrong-but-valid value (claims nothing is done).
printf '{"completed_phases":[],"completed_tasks":[]}' > "$p/.hb/state.json"
has_P0 "$p/.hb/state.json" && fail "setup: the hand-edit did not actually change the file"

# 2. doctor flags the drift.
hb doctor --dir "$p" 2>&1 | grep -qi 'differs from the event-log projection' \
  || fail "doctor did not flag the hand-edited state.json as drift"

# 3. the CLI overwrites the hand-edit from the log — the log wins, the edit is discarded.
hb rebuild --dir "$p" >/dev/null 2>&1
has_P0 "$p/.hb/state.json" || fail "rebuild did not overwrite the hand-edit — P0 not restored from the log"
hb doctor --dir "$p" 2>&1 | grep -qi 'differs from the event-log projection' && fail "drift persists after rebuild"

echo "STATE-DISCIPLINE-OK: a hand-edited state.json is flagged as drift, and the event log overwrites the edit on rebuild."
