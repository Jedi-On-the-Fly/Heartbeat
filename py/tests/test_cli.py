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


def test_gate_all_announces_scope_and_reports_elapsed(tmp_path, capsys):
    # Issue: the pre-push hook (which runs `hb gate --all`) was silent until the very end —
    # a blocked push was indistinguishable from a dead terminal. The sweep now announces its
    # scope up front and its verdict carries the elapsed total.
    proj = str(tmp_path / "proj")
    cli.main(["init", proj])
    rc, out = _run(capsys, "gate", "--all", "--dir", proj)
    assert rc == 0
    first = out.splitlines()[0]
    assert "re-verifying" in first and "ever-passed" in first   # scope announced FIRST
    assert "ALL GATES PASS" in out and "in " in out.rsplit("(", 1)[-1]


def test_park_unpark_roundtrip_by_gate_id(tmp_path, capsys):
    # hb park accepts a GATE id (resolved to the phase carrying it as gate_exit); unpark
    # restores; an unknown id is refused. No hand-editing of dag.json required.
    import json
    proj = str(tmp_path / "proj")
    cli.main(["init", proj])
    dagp = tmp_path / "proj" / ".hb" / "dag.json"
    first_gate = next(iter(json.loads(dagp.read_text())["gates"]))
    rc, out = _run(capsys, "park", first_gate, "--reason", "abandoned", "--dir", proj)
    assert rc == 0
    d = json.loads(dagp.read_text())
    target = next(p for p in d["phases"] if p.get("gate_exit") == first_gate)
    assert target["parked"] is True and target["parked_reason"] == "abandoned"
    rc, _ = _run(capsys, "unpark", target["id"], "--dir", proj)   # unpark by PHASE id
    assert rc == 0
    d = json.loads(dagp.read_text())
    assert "parked" not in next(p for p in d["phases"] if p["id"] == target["id"])
    rc, _ = _run(capsys, "park", "NOPE", "--dir", proj)
    assert rc != 0
