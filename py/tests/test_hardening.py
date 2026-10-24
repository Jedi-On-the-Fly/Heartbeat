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
    (tmp_path / "real.md").write_text("Refutation for GA0: inspected A0T1 in done.log, re-ran the gate. No hole found.\nHOLES: none\n")
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
    (tmp_path / "real.md").write_text("Refutation for GA0: inspected A0T1 in done.log, re-ran the gate. No hole.\nHOLES: none\n")
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
    (tmp_path / "real.md").write_text("Refutation for GA0: inspected A0T1 in done.log, re-ran the gate. No hole.\nHOLES: none\n")
    cli.main(["review", "GA0", "pass", "--artifact", str(tmp_path / "real.md"), "--dir", str(tmp_path)])
    (hb / "reviews" / "GA0.md").unlink()
    assert any("artifact" in p for p in doctor.doctor(hb)["problems"])


# ── executor drives the validated review pass ──
EXEC_STUB = """#!/usr/bin/env bash
mode="$1"; payload="$(cat)"
case "$mode" in
  execute) id=$(printf '%s' "$payload" | python3 -c 'import sys,json;print(json.load(sys.stdin)["task"]["id"])'); printf '%s\\n' "$id" >> done.log; printf '{"ok":true,"summary":"did %s"}\\n' "$id" ;;
  refute)  printf '{"refuted":false,"findings":"Attempted to refute GA0: inspected done.log for the task output, re-ran the behavioral gate. No hole found.\\\\nHOLES: none"}\\n' ;;
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


# ── hostile criteria shapes: every static reader survives, lint owns the loud error ──────────
# A criteria entry that is not an object, or whose cmd is not a string, is out of the dag
# schema's domain. The contract (mirrored in hb-lint.js/hb.js/hb-audit.js, parity case
# lint:hostile-criteria): lint ERRORS on it with identical bytes across runtimes; doctor and
# the artifact scans skip it without crashing (the lint error surfaces as a `dag:` problem);
# audit classifies it as non-behavioral (an all-garbage gate is hollow) — never a traceback.

HOSTILE_CRITERIA = {
    "intcmd":    [{"id": "c1", "desc": "d", "cmd": 7}],
    "nullcmd":   [{"id": "c1", "desc": "d", "cmd": None}],
    "listentry": [["garbage"]],
    "nullentry": [None],
    "strentry":  ["garbage"],
}


def _hostile_dag(crit):
    return {"project": "t",
            "phases": [{"id": "H", "title": "h", "gate_entry": None, "gate_exit": "GATE_H",
                        "tasks": [{"id": "h1", "title": "t", "requires": [], "description": "w"}]}],
            "gates": {"GATE_H": {"desc": "g", "criteria": crit}}}


@pytest.mark.parametrize("shape", sorted(HOSTILE_CRITERIA))
def test_hostile_criteria_lint_errors_loudly(shape):
    from heartbeat import lint as lintmod
    r = lintmod.lint(_hostile_dag(HOSTILE_CRITERIA[shape]))          # must not raise
    assert any("criteria entry" in e and "GATE_H" in e for e in r["errors"]), r


@pytest.mark.parametrize("shape", sorted(HOSTILE_CRITERIA))
def test_hostile_criteria_doctor_reports_never_crashes(tmp_path, shape):
    hb = make_hb(tmp_path, _hostile_dag(HOSTILE_CRITERIA[shape]))
    state.reproject(hb)
    d = doctor.doctor(str(hb))                                        # must not raise
    assert any(p.startswith("dag: ") and "criteria entry" in p for p in d["problems"]), d


@pytest.mark.parametrize("shape", sorted(HOSTILE_CRITERIA))
def test_hostile_criteria_audit_hollow_never_crashes(shape):
    r = audit.audit(_hostile_dag(HOSTILE_CRITERIA[shape]))            # must not raise
    assert any(f["rule"] == "hollow_gate" for f in r["findings"]), r  # garbage is not behavioral


def test_empty_cmd_is_vacuous_not_behavioral():
    # A zero-byte cmd runs as `''` → exit 0 → a trivial pass; it must never count as the
    # behavioral criterion that saves a gate from hollow_gate.
    assert audit.classify("") == "vacuous"
    assert audit.classify(None) == "vacuous"
    r = audit.audit(_hostile_dag([{"id": "c1", "desc": "d", "cmd": ""}]))
    assert any(f["rule"] == "hollow_gate" for f in r["findings"]), r
