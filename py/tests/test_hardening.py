import pytest

from conftest import make_hb
from heartbeat import state, gate, audit, doctor, cli, executor


def _review_dag():
    return {"phases": [{"id": "A0", "gate_entry": None, "gate_exit": "GA0",
                        "tasks": [{"id": "A0T1", "title": "write A0T1 to done.log"}]}],
            "gates": {"GA0": {"desc": "p", "review": {"prompt": "Refute A0."},
                              "criteria": [{"id": "c", "cmd": 'grep -q A0T1 "$PROJECT_DIR/done.log"'}]}}}


def _ready_for_review(tmp_path):
    hb = make_hb(tmp_path, _review_dag())
    state.reproject(hb)
    (tmp_path / "done.log").write_text("A0T1\n")
    state.mutate(hb, {"event": "task_done", "task": "A0T1"})
    gate.run_gate(hb, "GA0")   # deterministic pass → review_pending
    return hb


# ── gate hollow floor ──
def test_gate_hollow_floor_fails(tmp_path):
    dag = {"phases": [{"id": "P0", "gate_exit": "G0", "tasks": [{"id": "A"}]}], "gates": {"G0": {"criteria": []}}}
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    assert gate.run_gate(hb, "G0")["status"] == "blocked"
    assert gate.run_gate(hb, "G0", check=True)["status"] == "would_block"


# ── audit expansions ──
def test_audit_side_effecting():
    dag = {"phases": [{"id": "P0", "gate_exit": "G0", "tasks": [{"id": "A", "title": "produce out.json"}]}],
           "gates": {"G0": {"criteria": [{"id": "c", "cmd": 'echo ok > "$PROJECT_DIR/out.json"; test -f "$PROJECT_DIR/out.json"'}]}}}
    assert any(f["rule"] == "side_effecting" for f in audit.audit(dag)["findings"])


def test_audit_random_nondeterministic():
    dag = {"phases": [{"id": "P0", "gate_exit": "G0", "tasks": [{"id": "A"}]}],
           "gates": {"G0": {"criteria": [{"id": "c", "cmd": "[ $((RANDOM % 2)) -eq 0 ]"}]}}}
    assert any(f["rule"] == "nondeterministic" for f in audit.audit(dag)["findings"])


# ── review evidence ──
def test_review_pass_requires_artifact(tmp_path):
    hb = _ready_for_review(tmp_path)
    assert cli.main(["review", "GA0", "pass", "--dir", str(tmp_path)]) == 1
    assert "A0" not in state.read_state(hb)["completed_phases"]


def test_review_thin_artifact_rejected(tmp_path):
    hb = _ready_for_review(tmp_path)
    (tmp_path / "thin.md").write_text("ok\n")
    assert cli.main(["review", "GA0", "pass", "--artifact", str(tmp_path / "thin.md"), "--dir", str(tmp_path)]) == 1


def test_review_substantive_artifact_advances(tmp_path):
    hb = _ready_for_review(tmp_path)
    (tmp_path / "real.md").write_text("Refutation for GA0: inspected A0T1 in done.log, re-ran the gate. No hole found.\n")
    assert cli.main(["review", "GA0", "pass", "--artifact", str(tmp_path / "real.md"), "--dir", str(tmp_path)]) == 0
    assert "A0" in state.read_state(hb)["completed_phases"]
    assert (hb / "reviews" / "GA0.md").exists()


def test_review_padding_no_anchor_rejected(tmp_path):
    hb = _ready_for_review(tmp_path)
    (tmp_path / "pad.md").write_text("a" * 60 + "\n")
    assert cli.main(["review", "GA0", "pass", "--artifact", str(tmp_path / "pad.md"), "--dir", str(tmp_path)]) == 1


def test_review_self_review_rejected_then_distinct_accepted(tmp_path, monkeypatch):
    hb = make_hb(tmp_path, _review_dag())
    state.reproject(hb)
    (tmp_path / "done.log").write_text("A0T1\n")
    (tmp_path / "real.md").write_text("Refutation for GA0: inspected A0T1 in done.log, re-ran the gate. No hole.\n")
    monkeypatch.setenv("HB_ACTOR", "agent-A")
    state.mutate(hb, {"event": "task_done", "task": "A0T1"})   # doer = agent-A
    gate.run_gate(hb, "GA0")
    assert cli.main(["review", "GA0", "pass", "--artifact", str(tmp_path / "real.md"), "--dir", str(tmp_path)]) == 1
    assert "A0" not in state.read_state(hb)["completed_phases"]
    monkeypatch.setenv("HB_ACTOR", "agent-B")
    assert cli.main(["review", "GA0", "pass", "--artifact", str(tmp_path / "real.md"), "--dir", str(tmp_path)]) == 0
    assert "A0" in state.read_state(hb)["completed_phases"]


def test_doctor_flags_vanished_review_artifact(tmp_path):
    hb = _ready_for_review(tmp_path)
    (tmp_path / "real.md").write_text("Refutation for GA0: inspected A0T1 in done.log, re-ran the gate. No hole.\n")
    cli.main(["review", "GA0", "pass", "--artifact", str(tmp_path / "real.md"), "--dir", str(tmp_path)])
    (hb / "reviews" / "GA0.md").unlink()
    assert any("artifact" in p for p in doctor.doctor(hb)["problems"])


# ── executor drives the validated review pass ──
EXEC_STUB = """#!/usr/bin/env bash
mode="$1"; payload="$(cat)"
case "$mode" in
  execute) id=$(printf '%s' "$payload" | python3 -c 'import sys,json;print(json.load(sys.stdin)["task"]["id"])'); printf '%s\\n' "$id" >> done.log; printf '{"ok":true,"summary":"did %s"}\\n' "$id" ;;
  refute)  printf '{"refuted":false,"findings":"Attempted to refute GA0: inspected done.log for the task output, re-ran the behavioral gate. No hole found."}\\n' ;;
esac
"""


def test_executor_review_pass_persists_artifact(tmp_path, monkeypatch):
    stub = tmp_path / "stub.sh"
    stub.write_text(EXEC_STUB)
    stub.chmod(0o755)
    hb = make_hb(tmp_path, _review_dag())
    state.reproject(hb)
    monkeypatch.setenv("HB_EXEC_CMD", f"bash {stub}")
    monkeypatch.setenv("HB_EXEC_MAX_ITERS", "25")
    assert executor.run(hb) == 0
    assert "A0" in state.read_state(hb)["completed_phases"]
    assert (hb / "reviews" / "GA0.md").exists()
