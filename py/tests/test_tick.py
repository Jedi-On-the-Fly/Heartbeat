from conftest import make_hb, two_phase_dag
from heartbeat import state, tick, gate


def test_tick_next_task_and_leases(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag())
    state.reproject(hb)
    out = tick.tick(hb)
    assert out["wakeAgent"] is True
    assert out["data"]["reason"] == "next_task"
    assert out["data"]["next_task"]["id"] == "P0T1"
    assert out["data"]["action"]                      # self-describing
    assert (state.leases_dir(hb) / "P0T1").exists()   # tick leased it
    assert not (hb / ".lock").exists()                # handout lock released


def test_tick_gate_pending(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag(),
                 [{"event": "task_done", "task": "P0T1"}, {"event": "task_done", "task": "P0T2"}])
    state.reproject(hb)
    out = tick.tick(hb)
    assert out["data"]["reason"] == "gate_pending"
    assert out["data"]["next_task"]["gate"] == "GATE_P0"


def test_tick_gate_blocked_after_failure(tmp_path):
    dag = two_phase_dag()
    dag["gates"]["GATE_P0"]["criteria"] = [{"id": "c", "cmd": "false"}]
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    gate.run_gate(hb, "GATE_P0")                       # fails → gate.errors = 1
    out = tick.tick(hb)
    assert out["data"]["reason"] == "gate_blocked"


def test_tick_all_done_then_project_complete(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag(),
                 [{"event": "task_done", "task": "P0T1"}, {"event": "task_done", "task": "P0T2"},
                  {"event": "gate_passed", "gate": "GATE_P0"},
                  {"event": "task_done", "task": "P1T1"}, {"event": "gate_passed", "gate": "GATE_P1"}])
    state.reproject(hb)
    first = tick.tick(hb)
    assert first["wakeAgent"] and first["data"]["reason"] == "all_done"
    second = tick.tick(hb)
    assert second["wakeAgent"] is False and second["data"]["reason"] == "project_complete"


def test_tick_circuit_breaker(tmp_path):
    events = [{"event": "task_failed", "task": "P0T1"} for _ in range(5)]
    hb = make_hb(tmp_path, two_phase_dag(), events)
    state.reproject(hb)
    out = tick.tick(hb)
    assert out["data"]["reason"] == "build_stuck"


def test_review_stuck_escalation(tmp_path, monkeypatch):
    # A never-resolving adversarial review must escalate to review_stuck past STUCK_TICKS
    # (parity with node tick.sh), not wake review_pending forever.
    monkeypatch.setattr(tick, "STUCK_TICKS", 3)
    dag = {"phases": [{"id": "P0", "gate_entry": None, "gate_exit": "G0",
                       "tasks": [{"id": "P0T1", "title": "t", "requires": []}]}],
           "gates": {"G0": {"desc": "g", "review": {"prompt": "r"},
                            "criteria": [{"id": "c", "desc": "d", "cmd": "true"}]}}}
    done_pass = [{"event": "task_done", "task": "P0T1"}, {"event": "gate_passed", "gate": "G0"}]
    wake = {"event": "review_wake", "gate": "G0"}
    hb = make_hb(tmp_path, dag, done_pass + [wake, wake, wake])   # 3 review_wakes >= STUCK_TICKS
    state.reproject(hb)
    assert tick.tick(hb)["data"]["reason"] == "review_stuck"
    d2 = tmp_path / "below"; d2.mkdir()
    hb2 = make_hb(d2, dag, done_pass + [wake])                    # below threshold -> still pending
    state.reproject(hb2)
    assert tick.tick(hb2)["data"]["reason"] == "review_pending"
