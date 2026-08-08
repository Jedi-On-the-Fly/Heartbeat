#!/usr/bin/env bash
# Proof for "Read the event log": events.jsonl is the authoritative, append-only record; state
# is a projection of it. Complete a phase, then prove the log is well-formed and drives state:
#   1. every line is valid JSON,
#   2. the expected events appear in order (initialized; task_started < task_done < gate_passed),
#   3. reprojecting the log reproduces the completed phase,
#   4. control: drop the gate_passed event and the reprojection no longer shows completion
#      (state is derived from the log, not stored elsewhere).
# Prints EVENT-LOG-OK only when all hold.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }

p="$(mktemp -d)"; trap 'rm -rf "$p"' EXIT
hb init "$p" >/dev/null 2>&1
python3 -c 'import json,sys;json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GA0","tasks":[{"id":"T1","title":"make out.txt"}]}],"gates":{"GA0":{"desc":"g","criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},open(sys.argv[1],"w"))' "$p/.hb/dag.json"
hb rebuild --dir "$p" >/dev/null 2>&1
hb start T1 --dir "$p" >/dev/null 2>&1; printf 'ok\n' > "$p/out.txt"; hb done T1 --dir "$p" >/dev/null 2>&1; hb gate GA0 --dir "$p" >/dev/null 2>&1

python3 - "$p/.hb" <<'PY' || { echo "FAIL: event-log assertions did not hold"; exit 1; }
import sys, json
sys.path.insert(0, __import__("os").environ["PYTHONPATH"])
from heartbeat import state as st
hb = sys.argv[1]
lines = [l for l in open(hb + "/events.jsonl").read().splitlines() if l.strip()]
# 1. every line is valid JSON
evs = [json.loads(l) for l in lines]                     # raises -> FAIL if any line is malformed
names = [e.get("event") for e in evs]
# 2. ordering
assert names[0] == "initialized", names
i_s, i_d, i_g = names.index("task_started"), names.index("task_done"), names.index("gate_passed")
assert i_s < i_d < i_g, names
# 3. reprojecting the log reproduces the completed phase
dag = st.read_dag(hb)
assert "P0" in st.project(evs, dag)["completed_phases"]
# 4. control: without the gate_passed event, the projection shows no completion
trimmed = [e for e in evs if e.get("event") != "gate_passed"]
assert "P0" not in st.project(trimmed, dag)["completed_phases"], "completion survived removing gate_passed — state not log-derived"
print("event-log assertions passed")
PY

echo "EVENT-LOG-OK: the log is valid JSON in order (task_started < task_done < gate_passed) and the state reprojects from it."
