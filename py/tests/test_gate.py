from conftest import make_hb, two_phase_dag
from heartbeat import state, gate


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
