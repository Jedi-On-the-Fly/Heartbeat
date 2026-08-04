from conftest import make_hb, two_phase_dag
from heartbeat import state


def test_initial_projection_empty(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag())
    s = state.reproject(hb)
    assert s["current_phase"] == "P0"
    assert s["completed_tasks"] == []
    assert s["completed_phases"] == []
    assert s["build_stuck_count"] == 0


def test_task_lifecycle(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag(),
                 [{"event": "task_started", "task": "P0T1"},
                  {"event": "task_done", "task": "P0T1"}])
    s = state.reproject(hb)
    assert s["completed_tasks"] == ["P0T1"]
    assert s["active_tasks"] == []


def test_gate_pass_advances_phase(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag(),
                 [{"event": "task_done", "task": "P0T1"},
                  {"event": "task_done", "task": "P0T2"},
                  {"event": "gate_passed", "gate": "GATE_P0"}])
    s = state.reproject(hb)
    assert "P0" in s["completed_phases"]
    assert s["current_phase"] == "P1"


def test_failed_task_bumps_stuck_count(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag(),
                 [{"event": "task_failed", "task": "P0T1"},
                  {"event": "task_failed", "task": "P0T1"}])
    s = state.reproject(hb)
    assert s["build_stuck_count"] == 2
    assert "P0T1" not in s["completed_tasks"]


def test_review_gate_holds_phase_until_review_passes(tmp_path):
    dag = two_phase_dag()
    dag["gates"]["GATE_P0"]["review"] = {"prompt": "refute"}
    # deterministic gate passed but review still owed → phase NOT complete, review pending
    hb = make_hb(tmp_path, dag, [{"event": "gate_passed", "gate": "GATE_P0"}])
    s = state.reproject(hb)
    assert "P0" not in s["completed_phases"]
    assert s["pending_reviews"] == ["GATE_P0"]
    # now record the review pass → phase completes
    state.append_event(hb, {"event": "review_passed", "gate": "GATE_P0"})
    s = state.reproject(hb)
    assert "P0" in s["completed_phases"]
    assert s["pending_reviews"] == []


def test_lease_expired_returns_task_to_pending(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag(),
                 [{"event": "task_started", "task": "P0T1"},
                  {"event": "lease_expired", "task": "P0T1"}])
    s = state.reproject(hb)
    assert s["active_tasks"] == []
    assert "P0T1" not in s["completed_tasks"]


def test_mutate_and_leases_atomic(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag())
    assert state.acquire_lease(hb, "P0T1") is True
    assert state.acquire_lease(hb, "P0T1") is False   # atomic: second claim fails
    s = state.mutate(hb, {"event": "task_started", "task": "P0T1"})
    assert "P0T1" in s["active_tasks"]
    state.release_lease(hb, "P0T1")
    assert not (state.leases_dir(hb) / "P0T1").exists()
