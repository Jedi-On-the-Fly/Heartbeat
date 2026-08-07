#!/usr/bin/env python3
"""Live end-to-end proof for the pure-Python port.

Drives a real project with a LOCAL model via the in-process backend. The gate runs
PYTHON (imports and calls the model-written code), so the whole path is node/bash-free.
Non-deterministic (depends on the model) → intentionally NOT part of the pytest suite.

    python3 real-backend.py [backend] [model]     # default: ollama qwen2.5:7b-instruct
"""
import json
import os
import shutil
import sys
import tempfile
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "src"))
from heartbeat import scaffold, executor, state  # noqa: E402

HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
try:
    urllib.request.urlopen(HOST + "/api/tags", timeout=3)
except Exception:
    print(f"ollama not reachable at {HOST} — skipping live test")
    sys.exit(0)

backend = sys.argv[1] if len(sys.argv) > 1 else "ollama"
model = sys.argv[2] if len(sys.argv) > 2 else "qwen2.5:7b-instruct"

os.environ["HB_NO_GIT"] = "1"
tmp = tempfile.mkdtemp()
proj = Path(tmp) / "real"
scaffold.init(proj)
hb = proj / ".hb"

dag = {
    "phases": [{"id": "M0", "title": "model writes code", "gate_entry": None, "gate_exit": "GM0",
                "tasks": [{"id": "M0T1", "title": "create greeting.py", "requires": [],
                           "description": "Create a file greeting.py at the project root defining a function "
                                          "greet(name) that returns the string 'Hello, ' followed by the name."}]}],
    "gates": {"GM0": {"desc": "greet composes the greeting", "criteria": [
        {"id": "g1", "desc": "greet('Ada') == 'Hello, Ada'",
         "cmd": "cd \"$PROJECT_DIR\" && python3 -c \"import greeting; assert greeting.greet('Ada')=='Hello, Ada'\""}]}},
}
(hb / "dag.json").write_text(json.dumps(dag, indent=2))
state.reproject(hb)

os.environ["HB_EXEC_BACKEND"] = backend
os.environ["HB_EXEC_MODEL"] = model
if backend in ("agno", "crewai", "langgraph", "openai-agents"):
    os.environ.setdefault("HB_EXEC_PROVIDER", "ollama")
os.environ["HB_EXEC_MAX_ITERS"] = "8"

print(f"▶ pure-Python HeartBeat — backend={backend}, model={model}")
print("  Task: write greeting.py  ·  Gate: PYTHON imports it and asserts greet('Ada')=='Hello, Ada'")
print("─" * 60)
executor.run(hb)
print("─" * 60)

ok = "M0" in (state.read_state(hb) or {}).get("completed_phases", [])
if ok:
    print("✅ REAL RUN PASSED — the local model wrote working code and the PYTHON gate ran it green.")
    print("--- greeting.py (model output) ---")
    print((proj / "greeting.py").read_text())
else:
    print("❌ REAL RUN did not complete the phase.")
    if (proj / "greeting.py").exists():
        print((proj / "greeting.py").read_text())
shutil.rmtree(tmp, ignore_errors=True)
sys.exit(0 if ok else 1)
