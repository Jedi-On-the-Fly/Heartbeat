import os
import subprocess

from conftest import make_hb, two_phase_dag
from heartbeat import doctor, gate, state


def _git_project(tmp_path, monkeypatch):
    monkeypatch.delenv("HB_NO_GIT", raising=False)
    env = {"GIT_CONFIG_GLOBAL": os.devnull, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
           "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
    for k, v in env.items():
        monkeypatch.setenv(k, v)
    hb = make_hb(tmp_path, two_phase_dag())
    (tmp_path / "a.txt").write_text("a\n")
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "add", "-A"], cwd=tmp_path, check=True)
    subprocess.run(["git", "commit", "-qm", "b"], cwd=tmp_path, check=True)
    for t in ("P0T1", "P0T2"):
        state.mutate(hb, {"event": "task_started", "task": t}); state.mutate(hb, {"event": "task_done", "task": t})
    return hb


def test_tag_failure_is_recorded_and_reported(tmp_path, monkeypatch, capsys):
    hb = _git_project(tmp_path, monkeypatch)
    os.chmod(tmp_path / ".git" / "refs" / "tags", 0o555)
    try:
        assert gate.run_gate(str(hb), "GATE_P0")["status"] == "passed"
    finally:
        os.chmod(tmp_path / ".git" / "refs" / "tags", 0o755)
    evs = state.read_events(hb)
    assert any(e["event"] == "restore_point_failed" and e["step"] == "tag" for e in evs)
    assert "restore point for GATE_P0: git tag failed" in capsys.readouterr().err
    assert next(e for e in evs if e["event"] == "gate_passed")["git"] == {"autocommit": True}


def test_doctor_flags_missing_tag_only_under_recorded_autocommit(tmp_path, monkeypatch):
    hb = _git_project(tmp_path, monkeypatch)
    gate.run_gate(str(hb), "GATE_P0")
    assert doctor.doctor(hb)["problems"] == []
    subprocess.run(["git", "tag", "-d", "GATE_P0"], cwd=tmp_path, stdout=subprocess.DEVNULL, check=True)
    assert any("no git tag GATE_P0" in p for p in doctor.doctor(hb)["problems"])
    # history that predates 1.32 (no anchors, no recorded git policy) is never flagged
    (hb / "anchors" / "_start.json").unlink(); (hb / "anchors" / "GATE_P0.json").unlink()
    evs = [{k: v for k, v in e.items() if k != "git"} for e in state.read_events(hb)]
    (hb / "events.jsonl").write_text("".join(__import__("json").dumps(e) + "\n" for e in evs))
    assert doctor.doctor(hb)["problems"] == []
