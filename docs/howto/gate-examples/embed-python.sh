#!/usr/bin/env bash
# Proof for "Embed HeartBeat in a Python app": the core is a stdlib library, so a program can
# drive a project directly — no CLI subprocess. This exercises the public API
# (heartbeat.state.mutate / heartbeat.gate.run_gate / heartbeat.state.project) end to end and
# asserts the phase completes, with a control that a missing artifact leaves it incomplete.
# Prints EMBED-PYTHON-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }

python3 - <<'PY' || { echo "FAIL: library-driven run did not behave as claimed"; exit 1; }
import os, sys, json, tempfile, shutil
sys.path.insert(0, os.environ["PYTHONPATH"])
from heartbeat import state as st, gate      # the public library API — no CLI

DAG = {"phases": [{"id": "P0", "gate_entry": None, "gate_exit": "GA0",
                   "tasks": [{"id": "T1", "title": "make out.txt"}]}],
       "gates": {"GA0": {"desc": "g", "criteria": [{"id": "c", "cmd": 'grep -q ok "$PROJECT_DIR/out.txt"'}]}}}

def make():
    p = tempfile.mkdtemp(); hb = os.path.join(p, ".hb"); os.mkdir(hb)
    json.dump(DAG, open(os.path.join(hb, "dag.json"), "w"))
    open(os.path.join(hb, "events.jsonl"), "w").write(json.dumps({"event": "initialized"}) + "\n")
    return p, hb

def completed(hb):
    return "P0" in st.project(st.read_events(hb), st.read_dag(hb))["completed_phases"]

# 1. Drive the whole phase through the library and complete it.
p, hb = make()
st.mutate(hb, {"event": "task_started", "task": "T1"})
open(os.path.join(p, "out.txt"), "w").write("ok\n")            # do the work
st.mutate(hb, {"event": "task_done", "task": "T1"})
res = gate.run_gate(hb, "GA0")                                  # run the real gate, in-process
assert res["status"] == "passed", res
assert completed(hb), "library-driven project did not complete"
shutil.rmtree(p)

# 2. Control: no artifact -> the library gate does not pass -> phase not completed.
p, hb = make()
st.mutate(hb, {"event": "task_started", "task": "T1"})
st.mutate(hb, {"event": "task_done", "task": "T1"})            # (no out.txt written)
res = gate.run_gate(hb, "GA0")
assert res["status"] == "blocked", res
assert not completed(hb), "control: phase completed with no artifact — the library gate is hollow"
shutil.rmtree(p)

print("embed library run passed")
PY

echo "EMBED-PYTHON-OK: a project runs to completion driven only through the Python library API; a missing artifact leaves it incomplete."
