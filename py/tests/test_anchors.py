from conftest import make_hb, two_phase_dag
from heartbeat import anchors, gate, state


def test_first_live_start_anchors_and_changed_sees_worktree(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag())
    (tmp_path / "a.txt").write_text("a\n")
    (tmp_path / "b.txt").write_text("b\n")
    state.mutate(hb, {"event": "task_started", "task": "P0T1"})
    start = anchors.read_anchor(hb, "_start")
    assert set(start["files"]) == {"a.txt", "b.txt"} and start["commit"] is None
    (tmp_path / "a.txt").write_text("a2\n"); (tmp_path / "b.txt").unlink(); (tmp_path / "n.txt").write_text("n\n")
    c = anchors.changed(hb, "GATE_P0")
    assert (c["added"], c["modified"], c["deleted"], c["target"]) == (["n.txt"], ["a.txt"], ["b.txt"], "worktree")


def test_replayed_history_takes_no_start_anchor(tmp_path):
    # a log that already holds a task_started (legacy / replay) must not get a misleading _start
    hb = make_hb(tmp_path, two_phase_dag(), [{"event": "task_started", "task": "P0T1"}])
    state.mutate(hb, {"event": "task_started", "task": "P0T2"})
    assert anchors.read_anchor(hb, "_start") is None


def test_accepted_gate_is_frozen_at_its_own_anchor(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag())
    (tmp_path / "a.txt").write_text("a\n")
    for t in ("P0T1", "P0T2"):
        state.mutate(hb, {"event": "task_started", "task": t}); state.mutate(hb, {"event": "task_done", "task": t})
    (tmp_path / "n.txt").write_text("n\n")
    assert gate.run_gate(str(hb), "GATE_P0")["status"] == "passed"
    assert anchors.read_anchor(hb, "GATE_P0") is not None
    (tmp_path / "late.txt").write_text("later phase\n")
    assert anchors.changed(hb, "GATE_P0")["added"] == ["n.txt"]
    assert anchors.changed(hb, "GATE_P1")["added"] == ["late.txt"]


def test_walk_skips_excluded_dirs_and_hb(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag())
    (tmp_path / "node_modules" / "m").mkdir(parents=True); (tmp_path / "node_modules" / "m" / "i.js").write_text("x")
    (tmp_path / "src").mkdir(); (tmp_path / "src" / "k.py").write_text("k")
    assert list(anchors.list_project_files(hb)) == ["src/k.py"]
