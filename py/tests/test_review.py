import json

import pytest

from heartbeat import cli, review, audit

STUB = """#!/usr/bin/env bash
mode="$1"; cat >/dev/null
case "$mode" in
  refute)  echo '{"refuted":true,"findings":"GATE_P0 only checks the file exists; the task requires auth enforcement — nothing tests that an unauthenticated request is rejected."}' ;;
  execute) echo '{"ok":true,"summary":"x"}' ;;
esac
"""


@pytest.fixture
def stub(tmp_path):
    p = tmp_path / "stub.sh"
    p.write_text(STUB)
    p.chmod(0o755)
    return p


def test_build_prompt_includes_dag_and_findings():
    dag = {"phases": [{"id": "P0", "gate_exit": "G", "tasks": [{"id": "t"}]}],
           "gates": {"G": {"criteria": [{"id": "c", "cmd": "true"}]}}}
    p = review.build_prompt(dag, audit.audit(dag))
    assert "REFUTE" in p and "hollow_gate" in p and "P0" in p


def test_agent_audit_surfaces_concern_and_exits_1(tmp_path, monkeypatch, stub, capsys):
    dag = tmp_path / "d.json"
    dag.write_text(json.dumps({
        "phases": [{"id": "P0", "gate_exit": "G", "tasks": [{"id": "t", "title": "enforce auth"}]}],
        "gates": {"G": {"criteria": [{"id": "c", "cmd": "grep -q ok f"}]}}}))   # behavioral → no det error
    monkeypatch.setenv("HB_EXEC_CMD", f"bash {stub}")
    rc = cli.main(["audit", str(dag), "--agent"])
    out = capsys.readouterr().out
    assert rc == 1                                   # refuted → non-zero even though det is clean
    assert "UNSOUND" in out and "auth" in out.lower()


def test_agent_review_run_returns_verdict(tmp_path, monkeypatch, stub):
    monkeypatch.setenv("HB_EXEC_CMD", f"bash {stub}")
    dag = {"phases": [{"id": "P0", "gate_exit": "G", "tasks": [{"id": "t"}]}],
           "gates": {"G": {"criteria": [{"id": "c", "cmd": "grep -q ok f"}]}}}
    rr = review.run(tmp_path, dag)
    assert rr["refuted"] is True and "auth" in rr["concerns"].lower()


def test_free_review_coercion_is_explicit():
    from heartbeat.refuter_profiles import _to_bool
    assert [_to_bool(v) for v in (True, "true", " YES ", "1", "on", 2)] == [True] * 6
    assert [_to_bool(v) for v in (False, None, "false", "no", "0", "off", "", 0, [])] == [False] * 9
    # ASCII whitespace only (== node): unicode edges are NOT stripped
    assert [_to_bool(v) for v in ("\ufefftrue", "true\u001f", "\u0085true", "\ttrue\n")] == [False, False, False, True]


def test_check_answers_rules():
    from heartbeat.review_policy import check_answers
    ids = ["P1", "G1"]
    assert check_answers("- **P1**: NOT-REPRODUCED — probe\nG1: N/A — reason", ids) == ([], {"violated": 0, "not_reproduced": 1, "na": 1})
    errs, _ = check_answers("P1: `violated` — x\nP1: N/A — y\nG9: N/A — z", ids)
    assert any("P1 is answered VIOLATED" in e for e in errs) and any("answered twice" in e for e in errs)
    assert any("G9 is not a constraint" in e for e in errs) and any("G1 has no answer line" in e for e in errs)
