import json

from conftest import make_hb
from heartbeat import constraints, doctor, gate, state

DAG = {"phases": [{"id": "P0", "title": "t", "gate_entry": None, "gate_exit": "G0", "tasks": [{"id": "t0", "title": "w"}]}],
       "gates": {"G0": {"desc": "gd", "review": {"prompt": "r", "constraints": [
           {"id": "P1", "claim": "c", "subjects": ["a.txt"], "violation": "v"}]},
           "criteria": [{"id": "c", "cmd": "true"}]}}}


def test_record_is_write_once_per_cycle_and_author_is_not_a_doer(tmp_path, monkeypatch):
    hb = make_hb(tmp_path, DAG)
    (hb.parent / "a.txt").write_text("the phase's file\n")   # a gate-time constraint must name a real path
    monkeypatch.setenv("HB_ACTOR", "doer")
    state.mutate(hb, {"event": "task_started", "task": "t0"}); state.mutate(hb, {"event": "task_done", "task": "t0"})
    f = tmp_path / "g.json"
    f.write_text(json.dumps([{"id": "G1", "claim": "x", "subjects": ["a.txt"], "violation": "y"}]))
    dag = state.read_dag(hb)
    assert constraints.record(str(hb), dag, "G0", str(f))[0] == 1          # not review_pending yet
    gate.run_gate(str(hb), "G0")
    assert constraints.record(str(hb), dag, "G0", str(f))[0] == 1          # doer
    monkeypatch.setenv("HB_ACTOR", "author")
    assert constraints.record(str(hb), dag, "G0", str(f), model="m")[0] == 0
    assert constraints.record(str(hb), dag, "G0", str(f))[0] == 1          # write-once this cycle
    ev = [e for e in state.read_events(hb) if e["event"] == "constraints_recorded"][-1]
    assert (ev["ids"], ev["actor"], ev["model"]) == (["G1"], "author", "m")
    assert doctor.doctor(hb)["problems"] == []
    (hb / "constraints" / "G0.json").write_text("[]")
    assert any("sha256 mismatch" in p for p in doctor.doctor(hb)["problems"])


def test_prompt_lists_plan_constraints_and_rule(tmp_path):
    hb = make_hb(tmp_path, DAG)
    p = constraints.compose_author_prompt(str(hb), state.read_dag(hb), "G0")
    assert "P1: c" in p and "do not hunt for bugs" in p and "(unavailable:" in p   # no _start yet
