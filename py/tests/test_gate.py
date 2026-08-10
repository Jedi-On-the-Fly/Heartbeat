import os

from conftest import make_hb, two_phase_dag
from heartbeat import state, gate


def test_relative_dir_gate(tmp_path, monkeypatch):
    # A relative dir must not double-nest $PROJECT_DIR / $HB_DIR (regression: gate blocked
    # because both resolved relative and the criteria ran with cwd = the relative project).
    dag = {
        "phases": [{"id": "P0", "gate_exit": "GATE_R",
                    "tasks": [{"id": "P0T1", "title": "produce out.txt", "requires": []}]}],
        "gates": {"GATE_R": {"desc": "rel", "criteria": [
            {"id": "pd", "desc": "project dir", "cmd": 'grep -q ok "$PROJECT_DIR/out.txt"'},
            {"id": "hd", "desc": "hb dir", "cmd": 'test -f "$HB_DIR/dag.json"'}]}},
    }
    hb = make_hb(tmp_path, dag)
    (tmp_path / "out.txt").write_text("ok\n")
    state.reproject(hb)
    monkeypatch.chdir(tmp_path.parent)                 # drive with a RELATIVE dir from the parent
    rel_hb = f"{tmp_path.name}/.hb"
    assert os.path.isabs(gate._project_dir(rel_hb))    # PROJECT_DIR must be absolute
    res = gate.run_gate(rel_hb, "GATE_R")
    assert res["status"] == "passed" and res["failed"] == 0


def test_gate_pass_advances_phase(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag())
    state.reproject(hb)
    res = gate.run_gate(hb, "GATE_P0")   # criteria are `true` → pass
    assert res["status"] == "passed" and res["failed"] == 0
    s = state.read_state(hb)
    assert "P0" in s["completed_phases"]


def test_gate_fail_blocks(tmp_path):
    dag = two_phase_dag()
    dag["gates"]["GATE_P0"]["criteria"] = [{"id": "c", "desc": "d", "cmd": "false"}]
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    res = gate.run_gate(hb, "GATE_P0")
    assert res["status"] == "blocked" and res["failed"] == 1
    assert state.read_state(hb)["gate"]["errors"] == 1


def test_unknown_gate(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag())
    assert gate.run_gate(hb, "NOPE")["status"] == "unknown"


def test_review_gate_announces_review(tmp_path):
    dag = two_phase_dag()
    dag["gates"]["GATE_P0"]["review"] = {"prompt": "refute"}
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    res = gate.run_gate(hb, "GATE_P0")
    assert res["status"] == "review_pending"
    assert state.read_state(hb)["pending_reviews"] == ["GATE_P0"]


def test_check_is_read_only(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag())
    state.reproject(hb)
    res = gate.run_gate(hb, "GATE_P0", check=True)
    assert res["status"] == "would_pass"
    # no side effects: phase NOT advanced, no gate_passed event
    assert "P0" not in state.read_state(hb)["completed_phases"]


def test_behavioral_gate_reads_real_file(tmp_path):
    # a genuinely behavioral criterion: content check, run via the real shell
    dag = two_phase_dag()
    dag["gates"]["GATE_P0"]["criteria"] = [{"id": "c", "desc": "d",
                                            "cmd": 'test "$(cat "$PROJECT_DIR/out.txt")" = ok'}]
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    assert gate.run_gate(hb, "GATE_P0", check=True)["status"] == "would_block"
    (tmp_path / "out.txt").write_text("ok\n")
    assert gate.run_gate(hb, "GATE_P0", check=True)["status"] == "would_pass"
