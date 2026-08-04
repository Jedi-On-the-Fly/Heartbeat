import json
import os
import sys
from pathlib import Path

# Deterministic defaults (mirror the node suite globals) — set BEFORE importing the
# package so tick.py's module constants pick them up.
os.environ.setdefault("STUCK_TICKS", "999")   # don't trip no-progress on repeated ticks
os.environ.setdefault("HB_ROT_CHECK", "0")    # rot check off unless a test opts in
os.environ.setdefault("HB_NO_GIT", "1")       # no git commits in throwaway projects

# Allow `import heartbeat` from src/ without installing.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))


def make_hb(tmp_path, dag, events=None):
    """Create a .hb/ dir with dag.json + events.jsonl (list of event dicts)."""
    hb = tmp_path / ".hb"
    hb.mkdir()
    (hb / "dag.json").write_text(json.dumps(dag))
    lines = [json.dumps({"event": "initialized"})] + [json.dumps(e) for e in (events or [])]
    (hb / "events.jsonl").write_text("\n".join(lines) + "\n")
    return hb


def two_phase_dag():
    return {
        "phases": [
            {"id": "P0", "title": "p0", "gate_entry": None, "gate_exit": "GATE_P0",
             "tasks": [{"id": "P0T1", "title": "a", "requires": []},
                       {"id": "P0T2", "title": "b", "requires": ["P0T1"]}]},
            {"id": "P1", "title": "p1", "gate_entry": "GATE_P0", "gate_exit": "GATE_P1",
             "tasks": [{"id": "P1T1", "title": "c", "requires": []}]},
        ],
        "gates": {
            "GATE_P0": {"desc": "g0", "criteria": [{"id": "c", "desc": "d", "cmd": "true"}]},
            "GATE_P1": {"desc": "g1", "criteria": [{"id": "c", "desc": "d", "cmd": "true"}]},
        },
    }
