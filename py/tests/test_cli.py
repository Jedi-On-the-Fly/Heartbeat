import json

from heartbeat import cli


def _run(capsys, *argv):
    capsys.readouterr()   # drain anything buffered from prior direct main() calls
    rc = cli.main(list(argv))
    return rc, capsys.readouterr().out


def test_init_scaffolds_project(tmp_path, capsys):
    proj = tmp_path / "proj"
    rc, out = _run(capsys, "init", str(proj))
    assert rc == 0
    hb = proj / ".hb"
    for f in ("dag.json", "state.json", "events.jsonl", "executor.json", "PROTOCOL.md"):
        assert (hb / f).exists(), f
    assert json.loads((hb / "executor.json").read_text())["backend"] == "claude-code"


def test_cli_end_to_end_drive(tmp_path, capsys):
    proj = str(tmp_path / "proj")
    cli.main(["init", proj])
    # first tick → next_task P0T1
    _, out = _run(capsys, "tick", "--dir", proj)
    data = json.loads(out)["data"]
    assert data["reason"] == "next_task" and data["next_task"]["id"] == "P0T1"
    # do the two tasks
    for t in ("P0T1", "P0T2"):
        cli.main(["start", t, "--dir", proj])
        cli.main(["done", t, "--dir", proj])
    # tick → gate_pending
    _, out = _run(capsys, "tick", "--dir", proj)
    assert json.loads(out)["data"]["reason"] == "gate_pending"
    # run the gate (default criterion is `true`) → passes
    rc, out = _run(capsys, "gate", "GATE_P0", "--dir", proj)
    assert rc == 0 and "passed" in out
    # report reflects the completed phase
    _, out = _run(capsys, "report", "--dir", proj)
    assert "✅ P0" in out


def test_cli_lint_and_doctor_and_protocol(tmp_path, capsys):
    proj = str(tmp_path / "proj")
    cli.main(["init", proj])
    assert _run(capsys, "lint", "--dir", proj)[0] == 0
    assert _run(capsys, "doctor", "--dir", proj)[0] == 0
    rc, out = _run(capsys, "protocol", "next_task")
    assert rc == 0 and "hb start" in out


def test_cli_diagnose_gate_blocked(tmp_path, capsys):
    proj = str(tmp_path / "proj")
    cli.main(["init", proj])
    # break the gate, run it (fails), diagnose should name gate_blocked
    import json as _j
    dag_p = tmp_path / "proj" / ".hb" / "dag.json"
    dag = _j.loads(dag_p.read_text())
    dag["gates"]["GATE_P0"]["criteria"] = [{"id": "g1", "cmd": "false"}]
    dag_p.write_text(_j.dumps(dag))
    cli.main(["gate", "GATE_P0", "--dir", proj])
    _, out = _run(capsys, "diagnose", "--dir", proj)
    assert "gate_blocked" in out
