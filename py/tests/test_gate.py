import os

from conftest import make_hb, two_phase_dag
from heartbeat import state, gate


def test_relative_dir_gate(tmp_path, monkeypatch):
    # A relative dir must not double-nest $PROJECT_DIR / $HB_DIR (regression: gate blocked
    # because both resolved relative and the criteria ran with cwd = the relative project).
    dag = {
        "phases": [{"id": "P0", "gate_exit": "GATE_R",
                    "tasks": [{"id": "P0T1", "title": "produce out.txt", "requires": []}]}],
        "gates": {"GATE_R": {"desc": "rel", "criteria": [
            {"id": "pd", "desc": "project dir", "cmd": 'grep -q ok "$PROJECT_DIR/out.txt"'},
            {"id": "hd", "desc": "hb dir", "cmd": 'test -f "$HB_DIR/dag.json"'}]}},
    }
    hb = make_hb(tmp_path, dag)
    (tmp_path / "out.txt").write_text("ok\n")
    state.reproject(hb)
    monkeypatch.chdir(tmp_path.parent)                 # drive with a RELATIVE dir from the parent
    rel_hb = f"{tmp_path.name}/.hb"
    assert os.path.isabs(gate._project_dir(rel_hb))    # PROJECT_DIR must be absolute
    res = gate.run_gate(rel_hb, "GATE_R")
    assert res["status"] == "passed" and res["failed"] == 0


def test_gate_pass_advances_phase(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag())
    state.reproject(hb)
    res = gate.run_gate(hb, "GATE_P0")   # criteria are `true` → pass
    assert res["status"] == "passed" and res["failed"] == 0
    s = state.read_state(hb)
    assert "P0" in s["completed_phases"]


def test_gate_fail_blocks(tmp_path):
    dag = two_phase_dag()
    dag["gates"]["GATE_P0"]["criteria"] = [{"id": "c", "desc": "d", "cmd": "false"}]
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    res = gate.run_gate(hb, "GATE_P0")
    assert res["status"] == "blocked" and res["failed"] == 1
    assert state.read_state(hb)["gate"]["errors"] == 1


def test_unknown_gate(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag())
    assert gate.run_gate(hb, "NOPE")["status"] == "unknown"


def test_review_gate_announces_review(tmp_path):
    dag = two_phase_dag()
    dag["gates"]["GATE_P0"]["review"] = {"prompt": "refute"}
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    res = gate.run_gate(hb, "GATE_P0")
    assert res["status"] == "review_pending"
    assert state.read_state(hb)["pending_reviews"] == ["GATE_P0"]


def test_check_is_read_only(tmp_path):
    hb = make_hb(tmp_path, two_phase_dag())
    state.reproject(hb)
    res = gate.run_gate(hb, "GATE_P0", check=True)
    assert res["status"] == "would_pass"
    # no side effects: phase NOT advanced, no gate_passed event
    assert "P0" not in state.read_state(hb)["completed_phases"]


def test_behavioral_gate_reads_real_file(tmp_path):
    # a genuinely behavioral criterion: content check, run via the real shell
    dag = two_phase_dag()
    dag["gates"]["GATE_P0"]["criteria"] = [{"id": "c", "desc": "d",
                                            "cmd": 'test "$(cat "$PROJECT_DIR/out.txt")" = ok'}]
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    assert gate.run_gate(hb, "GATE_P0", check=True)["status"] == "would_block"
    (tmp_path / "out.txt").write_text("ok\n")
    assert gate.run_gate(hb, "GATE_P0", check=True)["status"] == "would_pass"


def test_failing_criterion_output_surfaced(tmp_path):
    # Issue: a blocked gate printed WHICH criterion failed but never WHY — the criterion's
    # output was swallowed, so every diagnosis began by re-running the cmd by hand.
    dag = two_phase_dag()
    dag["gates"]["GATE_P0"]["criteria"] = [
        {"id": "q", "desc": "quiet pass", "cmd": "echo QUIET-OK"},
        {"id": "b", "desc": "boom", "cmd": "echo BOOM-DETAIL >&2; false"}]
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    res = gate.run_gate(hb, "GATE_P0", check=True)
    text = "\n".join(res["lines"])
    assert "BOOM-DETAIL" in text        # the WHY is surfaced (stderr captured too)
    assert "cmd:" in text               # and the failing cmd (matches the node runner)
    assert "QUIET-OK" not in text       # a PASSING criterion's output stays quiet


def test_failing_criterion_output_tail_truncated(tmp_path):
    # The surfaced output is a TAIL (GATE_OUT_LINES, default 20) with a LOUD truncation
    # marker — a chatty test runner must not bury the gate summary (the original reason
    # the output was discarded), and a silent cut would misreport what the criterion said.
    dag = two_phase_dag()
    dag["gates"]["GATE_P0"]["criteria"] = [
        {"id": "c", "desc": "chatty", "cmd": 'i=1; while [ $i -le 30 ]; do echo "line-$i"; i=$((i+1)); done; false'}]
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    text = "\n".join(gate.run_gate(hb, "GATE_P0", check=True)["lines"])
    assert "line-30" in text and "line-11" in text      # the tail is kept
    assert "line-10\n" not in text + "\n"               # earlier lines are cut
    assert "(+10 earlier output lines)" in text         # and the cut is LOUD


def test_criterion_timeout_s_overrides_default(tmp_path):
    # Issue: GATE_TIMEOUT_S (one global) killed any real criterion (a ~10s test suite) while
    # authors had no per-criterion dial. dag.json now sets `timeout_s` per criterion, and it
    # WINS over the runner default — the DAG (config) outranks the environment (blunt global).
    dag = two_phase_dag()
    dag["gates"]["GATE_P0"]["criteria"] = [
        {"id": "slow", "desc": "needs 2s", "timeout_s": 5, "cmd": "sleep 2"}]
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    res = gate.eval_gate(hb, "GATE_P0", timeout=1)     # runner default of 1s would kill it
    assert res["failed"] == 0                          # criterion's own 5s wins

    dag["gates"]["GATE_P0"]["criteria"] = [
        {"id": "hang", "desc": "hangs", "timeout_s": 1, "cmd": "sleep 3"}]
    (tmp_path / ".hb" / "dag.json").write_text(__import__("json").dumps(dag))
    res = gate.eval_gate(hb, "GATE_P0", timeout=30)    # generous default must NOT rescue it
    assert res["failed"] == 1                          # criterion's own 1s kills it


def test_invalid_timeout_s_fails_loud(tmp_path):
    # An invalid timeout_s is a LOUD runtime failure of the criterion (the zero-criteria-floor
    # precedent) — never a silent fallback to the default.
    dag = two_phase_dag()
    dag["gates"]["GATE_P0"]["criteria"] = [
        {"id": "bad", "desc": "typo", "timeout_s": "abc", "cmd": "true"}]
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    res = gate.eval_gate(hb, "GATE_P0")
    assert res["failed"] == 1                          # a passing cmd cannot absolve it
    assert "invalid timeout_s" in "\n".join(res["lines"])


def test_default_timeout_survives_a_real_suite():
    # The default must be one a real test-suite criterion survives (60s), not 5s.
    assert gate.GATE_TIMEOUT_S >= 60 or "GATE_TIMEOUT_S" in os.environ


def test_criterion_lines_carry_duration(tmp_path):
    # Issue: a multi-minute sweep never reported how long anything took — no way to tell
    # "slow" from "hung" from inside the run. Every result line now carries its duration.
    import re
    dag = two_phase_dag()
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    res = gate.run_gate(hb, "GATE_P0", check=True)
    for ln in res["lines"]:
        if ln.lstrip().startswith(("✓", "✗")):
            assert re.search(r"\(\d+s\)$", ln), ln


def test_eval_gate_streams_lines_and_reports_progress(tmp_path):
    # eval_gate exposes progress: `emit` receives each line AS PRODUCED (the CLI streams
    # instead of dumping everything after the gate finishes), and `progress` fires before
    # each criterion runs with its effective budget — the "what is running now" signal.
    dag = two_phase_dag()
    dag["gates"]["GATE_P0"]["criteria"] = [
        {"id": "c1", "desc": "one", "cmd": "true"},
        {"id": "c2", "desc": "two", "timeout_s": 7, "cmd": "true"}]
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    seen, prog = [], []
    res = gate.eval_gate(hb, "GATE_P0", emit=seen.append,
                         progress=lambda cid, desc, eff: prog.append((cid, eff)))
    assert seen == res["lines"]                      # every line was streamed
    assert prog == [("c1", gate.GATE_TIMEOUT_S), ("c2", 7)]   # fired per criterion, with the WINNING budget


def test_all_dedupes_identical_criteria(tmp_path):
    # Issue: 15 of 44 criteria byte-identical (`php tests/run.php`) → the sweep ran the same
    # 10s suite 15 times to learn one bit. Byte-identical (cmd, effective-timeout) pairs now
    # run ONCE per --all sweep — observed by a counter file — and every reuse is LOUD.
    dag = {"phases": [
        {"id": p, "gate_exit": g, "tasks": [{"id": f"T{p}", "title": "t", "requires": []}]}
        for p, g in (("P0", "G0"), ("P1", "G1"), ("P2", "G2"))],
        "gates": {g: {"desc": g, "criteria": [
            {"id": "c", "desc": "suite", "cmd": 'echo run >> "$PROJECT_DIR/runs.txt"'}]}
            for g in ("G0", "G1", "G2")}}
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    for g in ("G0", "G1", "G2"):
        assert gate.run_gate(hb, g)["status"] == "passed"   # arm each (records gate_passed)
    (tmp_path / "runs.txt").write_text("")                  # reset the counter pre-sweep
    r = gate.run_all(hb)
    assert r["ok"]
    assert (tmp_path / "runs.txt").read_text().count("run") == 1   # ran ONCE, not 3×
    assert r["deduped"] == 2
    text = "\n".join(ln for res in r["gates"].values() for ln in res["lines"])
    assert text.count("deduped") == 2                       # every reuse is loud, never silent


def test_all_dedup_respects_timeout_and_failure(tmp_path):
    # Same cmd under a DIFFERENT effective timeout is NOT deduped (a pass under 60s proves
    # nothing about a 1s budget), and a cached FAILURE still fails every referencing gate.
    cmd = 'echo x >> "$PROJECT_DIR/n.txt"'
    dag = {"phases": [
        {"id": p, "gate_exit": g, "tasks": [{"id": f"T{p}", "title": "t", "requires": []}]}
        for p, g in (("P0", "GA"), ("P1", "GB"))],
        "gates": {"GA": {"desc": "a", "criteria": [{"id": "a", "desc": "d", "cmd": cmd}]},
                  "GB": {"desc": "b", "criteria": [{"id": "b", "desc": "d", "timeout_s": 30, "cmd": cmd}]}}}
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    for g in ("GA", "GB"):
        gate.run_gate(hb, g)                                # arm both
    (tmp_path / "n.txt").write_text("")
    r = gate.run_all(hb)
    assert (tmp_path / "n.txt").read_text().count("x") == 2   # different budget → both ran
    assert r["deduped"] == 0
    # cached failure: regress BOTH gates to one shared failing cmd
    import json
    fail_cmd = 'echo f >> "$PROJECT_DIR/f.txt"; false'
    dag["gates"]["GA"]["criteria"][0]["cmd"] = fail_cmd
    dag["gates"]["GB"]["criteria"][0] = {"id": "b", "desc": "d", "cmd": fail_cmd}
    (tmp_path / ".hb" / "dag.json").write_text(json.dumps(dag))
    r = gate.run_all(hb)
    assert not r["ok"]
    assert (tmp_path / "f.txt").read_text().count("f") == 2   # one run + one flake probe
    assert sum(res["failed"] for res in r["gates"].values()) == 2   # but BOTH gates fail


def test_sweep_flake_probe_labels_but_never_absolves(tmp_path):
    # Issue: a transient failure was reported exactly like a real regression. In a sweep, a
    # failing criterion is re-run ONCE: pass on re-run → labeled FLAKY; fail again → labeled
    # reproduced. The verdict NEVER changes — observed nondeterminism is itself a contract
    # violation and fails closed. The probe is sweep-only.
    flaky_cmd = '[ -f "$PROJECT_DIR/flag" ] || { : > "$PROJECT_DIR/flag"; false; }'
    dag = {"phases": [
        {"id": p, "gate_exit": g, "tasks": [{"id": f"T{p}", "title": "t", "requires": []}]}
        for p, g in (("P0", "GFLK"), ("P1", "GDET"))],
        "gates": {"GFLK": {"desc": "f", "criteria": [{"id": "k", "desc": "flaky", "cmd": flaky_cmd}]},
                  "GDET": {"desc": "d", "criteria": [{"id": "d", "desc": "det", "cmd": "true"}]}}}
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    gate.run_gate(hb, "GFLK")            # fails, creates flag
    assert gate.run_gate(hb, "GFLK")["status"] == "passed"   # arms it
    gate.run_gate(hb, "GDET")            # arms GDET (cmd true)
    import json
    dag["gates"]["GDET"]["criteria"][0]["cmd"] = "false"     # regress GDET deterministically
    (tmp_path / ".hb" / "dag.json").write_text(json.dumps(dag))
    (tmp_path / "flag").unlink()                             # re-arm the flake
    r = gate.run_all(hb)
    assert not r["ok"]                                       # flake still blocks (fail-closed)
    assert r["flaky"] == 1
    text = "\n".join(ln for res in r["gates"].values() for ln in res["lines"])
    assert "FLAKY" in text                                   # flake labeled
    assert "reproduced" in text                              # regression labeled affirmatively
    # sweep-only: a plain eval_gate (no probe) runs the cmd exactly once
    dag["gates"]["GDET"]["criteria"][0]["cmd"] = 'echo p >> "$PROJECT_DIR/probes.txt"; false'
    (tmp_path / ".hb" / "dag.json").write_text(json.dumps(dag))
    gate.eval_gate(hb, "GDET")
    assert (tmp_path / "probes.txt").read_text().count("p") == 1
