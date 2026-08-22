import json
from pathlib import Path

from heartbeat import audit

FIX = Path(__file__).resolve().parents[2] / "tests" / "fixtures" / "audit"


def _load(name):
    return json.loads((FIX / f"{name}.json").read_text())


def test_hollow_gate_is_error():
    r = audit.audit(_load("hollow"))
    assert r["errors"] >= 1 and any(f["rule"] == "hollow_gate" for f in r["findings"])


def test_existence_only_is_hollow():
    r = audit.audit(_load("existence"))
    rules = {f["rule"] for f in r["findings"]}
    assert "existence" in rules and "hollow_gate" in rules


def test_nondeterministic_is_warn_not_error():
    r = audit.audit(_load("nondeterministic"))
    assert r["errors"] == 0 and any(f["rule"] == "nondeterministic" for f in r["findings"])


def test_good_dag_is_clean():
    assert audit.audit(_load("good"))["errors"] == 0


def test_behavioral_sibling_not_hollow():
    d = {"phases": [{"id": "P", "gate_exit": "G", "tasks": [{"id": "t", "title": "x"}]}],
         "gates": {"G": {"criteria": [{"id": "a", "cmd": "grep -q ok f"}, {"id": "b", "cmd": "test -f f"}]}}}
    assert audit.audit(d)["errors"] == 0


def test_classify():
    assert audit.classify("true") == "vacuous"
    assert audit.classify("test -f x") == "existence"
    assert audit.classify("grep -q ok f") == "behavioral"
