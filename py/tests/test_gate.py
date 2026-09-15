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
