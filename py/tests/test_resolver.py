from conftest import make_hb, two_phase_dag
from heartbeat import state, resolver


def _state(hb):
    return state.reproject(hb)


def test_next_task_first(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag())
    r = resolver.resolve(_state(hb), state.read_dag(hb), hb)
    assert r["id"] == "P0T1"


def test_requires_gate_before_next_phase(tmp_path):
    # P0 tasks done but gate NOT passed → gate_pending, never P1T1
    hb = make_hb(tmp_path, two_phase_dag(),
                 [{"event": "task_done", "task": "P0T1"},
                  {"event": "task_done", "task": "P0T2"}])
    r = resolver.resolve(_state(hb), state.read_dag(hb), hb)
    assert r.get("type") == "gate_pending" and r["gate"] == "GATE_P0"


def test_phase_closed_serves_next_phase(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag(),
                 [{"event": "task_done", "task": "P0T1"},
                  {"event": "task_done", "task": "P0T2"},
                  {"event": "gate_passed", "gate": "GATE_P0"}])
    r = resolver.resolve(_state(hb), state.read_dag(hb), hb)
    assert r["id"] == "P1T1"


def test_all_done(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag(),
                 [{"event": "task_done", "task": "P0T1"}, {"event": "task_done", "task": "P0T2"},
                  {"event": "gate_passed", "gate": "GATE_P0"},
                  {"event": "task_done", "task": "P1T1"}, {"event": "gate_passed", "gate": "GATE_P1"}])
    r = resolver.resolve(_state(hb), state.read_dag(hb), hb)
    assert r.get("type") == "all_done"


def test_ready_excludes_leased(tmp_path):
    dag = {"phases": [{"id": "X", "gate_entry": None, "gate_exit": "GX",
                       "tasks": [{"id": "A", "requires": []}, {"id": "B", "requires": []}]}],
           "gates": {"GX": {"criteria": [{"id": "c", "cmd": "true"}]}}}
    hb = make_hb(tmp_path, dag)
    s = state.reproject(hb)
    assert {t["id"] for t in resolver.ready_tasks(s, dag, hb)} == {"A", "B"}
    state.acquire_lease(hb, "A")
    assert {t["id"] for t in resolver.ready_tasks(s, dag, hb)} == {"B"}


def test_deadlock_dag_invalid(tmp_path):
    dag = {"phases": [{"id": "X", "gate_entry": None, "gate_exit": "GX",
                       "tasks": [{"id": "A", "requires": ["NOPE"]}]}],
           "gates": {"GX": {"criteria": [{"id": "c", "cmd": "true"}]}}}
    hb = make_hb(tmp_path, dag)
    r = resolver.resolve(state.reproject(hb), dag, hb)
    assert r.get("type") == "deadlock" and r["cause"] == "dag_invalid"


def test_parked_phase_skipped_and_all_done_reachable(tmp_path):
    # Issue: retiring a drafted phase meant hand-editing dag.json (and naive deletion dangles
    # gate_exit). A phase with parked:true is out of the plan's live surface: its tasks are
    # never offered and all_done is reachable without it.
    from conftest import make_hb
    from heartbeat import state, resolver
    dag = {"phases": [
        {"id": "P0", "gate_exit": "G0", "tasks": [{"id": "T1", "title": "t", "requires": []}]},
        {"id": "P9", "parked": True, "gate_exit": "GP9",
         "tasks": [{"id": "T9", "title": "future", "requires": []}]}],
        "gates": {"G0": {"desc": "g", "criteria": [{"id": "c", "cmd": "true"}]},
                  "GP9": {"desc": "p", "criteria": [{"id": "c", "cmd": "true"}]}}}
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    s = state.project(state.read_events(hb), dag)
    ready = resolver.ready_tasks(s, dag, hb)
    assert [t["id"] for t in ready] == ["T1"]          # T9 never offered
    state.mutate(hb, {"event": "task_done", "task": "T1"})
    state.mutate(hb, {"event": "gate_passed", "gate": "G0"})
    s = state.project(state.read_events(hb), dag)
    assert resolver.resolve(s, dag, hb) == {"type": "all_done"}   # P9 does not block the plan
