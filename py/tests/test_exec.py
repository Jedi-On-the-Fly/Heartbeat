import json
import os
import shutil
import subprocess

import pytest

from conftest import make_hb
from heartbeat import state, executor

STUB = """#!/usr/bin/env bash
mode="$1"; payload="$(cat)"
case "$mode" in
  execute)
    [ "${STUB_FAIL:-0}" = 1 ] && { echo '{"ok":false,"summary":"forced"}'; exit 0; }
    id=$(printf '%s' "$payload" | python3 -c 'import sys,json;print(json.load(sys.stdin)["task"]["id"])')
    if [ "${STUB_DISTINCT:-0}" = 1 ]; then printf 'done\\n' > "$id.out"; else printf '%s\\n' "$id" >> done.log; fi
    printf '{"ok":true,"summary":"did %s"}\\n' "$id" ;;
  refute) printf '{"refuted":%s,"findings":"Attempted to refute: inspected done.log for the task output, checked the gate criteria for hollowness, re-ran the behavioral check. No hole found."}\\n' "${STUB_REFUTE:-false}" ;;
esac
"""


@pytest.fixture
def stub(tmp_path):
    p = tmp_path / "stub.sh"
    p.write_text(STUB)
    p.chmod(0o755)
    return p


def _dag(tasks_by_phase, review=None):
    phases, gates = [], {}
    prev_gate = None
    for i, (pid, tids) in enumerate(tasks_by_phase):
        g = f"G{pid}"
        phases.append({"id": pid, "gate_entry": prev_gate, "gate_exit": g,
                       "tasks": [{"id": t, "title": f"write {t} to done.log", "requires": []} for t in tids]})
        crit = " && ".join(f'grep -q {t} "$PROJECT_DIR/done.log"' for t in tids)
        gates[g] = {"desc": pid, "criteria": [{"id": "c", "cmd": crit}]}
        if review:
            gates[g]["review"] = {"prompt": "refute"}
        prev_gate = g
    return {"phases": phases, "gates": gates}


def _run(tmp_path, dag, monkeypatch, stub, **env):
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    monkeypatch.setenv("HB_EXEC_CMD", f"bash {stub}")
    monkeypatch.setenv("HB_EXEC_MAX_ITERS", "30")
    for k, v in env.items():
        monkeypatch.setenv(k, v)
    return hb


def test_drive_to_all_done(tmp_path, monkeypatch, stub, capsys):
    hb = _run(tmp_path, _dag([("P0", ["P0T1"]), ("P1", ["P1T1"])]), monkeypatch, stub)
    rc = executor.run(hb)
    out = capsys.readouterr().out
    assert rc == 0 and "HB-EXEC DONE" in out
    s = state.read_state(hb)
    assert "P0" in s["completed_phases"] and "P1" in s["completed_phases"]
    assert (tmp_path / "done.log").read_text().count("\n") == 2


def test_attempt_cap_escalates(tmp_path, monkeypatch, stub, capsys):
    hb = _run(tmp_path, _dag([("P0", ["P0T1"])]), monkeypatch, stub, STUB_FAIL="1", HB_EXEC_ATTEMPT_CAP="3")
    rc = executor.run(hb)
    assert rc == 1 and "attempts_exhausted" in capsys.readouterr().out


def test_strict_refuses_non_behavioral_gate(tmp_path, monkeypatch, stub, capsys):
    dag = _dag([("P0", ["P0T1"])])
    dag["gates"]["GP0"]["criteria"] = [{"id": "c", "cmd": 'test -f "$PROJECT_DIR/x"'}]
    hb = make_hb(tmp_path, dag)
    state.mutate(hb, {"event": "task_started", "task": "P0T1"})
    state.mutate(hb, {"event": "task_done", "task": "P0T1"})
    monkeypatch.setenv("HB_EXEC_CMD", f"bash {stub}")
    monkeypatch.setenv("HB_EXEC_MAX_ITERS", "5")
    monkeypatch.setenv("HB_EXEC_STRICT", "1")
    assert executor.run(hb) == 1
    assert "strict_gate" in capsys.readouterr().out


def test_review_refuted_routes_to_gate_blocked(tmp_path, monkeypatch, stub, capsys):
    hb = _run(tmp_path, _dag([("P0", ["P0T1"])], review=True), monkeypatch, stub, STUB_REFUTE="true")
    assert executor.run(hb) == 1
    assert "STOP: gate_blocked" in capsys.readouterr().out


def test_parallel_in_place(tmp_path, monkeypatch, stub, capsys):
    hb = _run(tmp_path, _dag([("P0", ["A", "B", "C"])]), monkeypatch, stub, HB_MAX_CONCURRENCY="3")
    rc = executor.run(hb)
    out = capsys.readouterr().out
    assert rc == 0 and "fan-out 3" in out and "HB-EXEC DONE" in out
    log = (tmp_path / "done.log").read_text()
    assert all(x in log for x in ("A", "B", "C"))


@pytest.mark.skipif(not shutil.which("git"), reason="git required")
def test_parallel_worktree_isolation(tmp_path, monkeypatch, stub, capsys):
    dag = {"phases": [{"id": "WP", "gate_entry": None, "gate_exit": "GWP",
                       "tasks": [{"id": "WA", "title": "WA.out", "requires": []},
                                 {"id": "WB", "title": "WB.out", "requires": []}]}],
           "gates": {"GWP": {"criteria": [{"id": "c", "cmd": 'test -f "$PROJECT_DIR/WA.out" && test -f "$PROJECT_DIR/WB.out"'}]}}}
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    subprocess.run(["git", "-C", str(tmp_path), "init", "-q"])
    subprocess.run(["git", "-C", str(tmp_path), "add", "-A"])
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-C", str(tmp_path),
                    "commit", "-q", "-m", "init"])
    monkeypatch.setenv("HB_EXEC_CMD", f"bash {stub}")
    monkeypatch.setenv("HB_EXEC_MAX_ITERS", "15")
    monkeypatch.setenv("HB_MAX_CONCURRENCY", "2")
    monkeypatch.setenv("STUB_DISTINCT", "1")
    monkeypatch.delenv("HB_NO_GIT", raising=False)
    rc = executor.run(hb)
    out = capsys.readouterr().out
    assert rc == 0 and "worktree-isolated" in out
    assert (tmp_path / "WA.out").exists() and (tmp_path / "WB.out").exists()
    assert not list((hb / "wt").glob("*")) if (hb / "wt").exists() else True


def test_relative_dir_worktree(tmp_path, monkeypatch, stub, capsys):
    # A relative --dir must not double-nest the git worktree (regression: `git -C proj worktree
    # add proj/.hb/wt/...` created proj/proj/... and the concurrent run exhausted attempts).
    dag = {"phases": [{"id": "WP", "gate_entry": None, "gate_exit": "GWP",
                       "tasks": [{"id": "WA", "title": "WA.out", "requires": []},
                                 {"id": "WB", "title": "WB.out", "requires": []}]}],
           "gates": {"GWP": {"criteria": [{"id": "c", "cmd": 'test -f "$PROJECT_DIR/WA.out" && test -f "$PROJECT_DIR/WB.out"'}]}}}
    hb = make_hb(tmp_path, dag)
    state.reproject(hb)
    subprocess.run(["git", "-C", str(tmp_path), "init", "-q"])
    subprocess.run(["git", "-C", str(tmp_path), "add", "-A"])
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-C", str(tmp_path),
                    "commit", "-q", "-m", "init"])
    monkeypatch.setenv("HB_EXEC_CMD", f"bash {stub}")
    monkeypatch.setenv("HB_EXEC_MAX_ITERS", "15")
    monkeypatch.setenv("HB_MAX_CONCURRENCY", "2")
    monkeypatch.setenv("STUB_DISTINCT", "1")
    monkeypatch.delenv("HB_NO_GIT", raising=False)
    monkeypatch.chdir(tmp_path.parent)                 # drive with a RELATIVE dir from the parent
    rc = executor.run(f"{tmp_path.name}/.hb")
    out = capsys.readouterr().out
    assert rc == 0 and "worktree-isolated" in out
    assert (tmp_path / "WA.out").exists() and (tmp_path / "WB.out").exists()
    assert not (tmp_path.parent / tmp_path.name / tmp_path.name).exists()   # no proj/proj double-nest


# ── `hb exec config` prints the resolved config and must NOT run (parity with the plugin) ──
def test_exec_config_prints_and_does_not_run(tmp_path, monkeypatch, stub, capsys):
    from heartbeat import cli
    hb = _run(tmp_path, _dag([("P0", ["P0T1"])]), monkeypatch, stub)
    before = (hb / "events.jsonl").read_text()
    rc = cli.main(["exec", "config", "--dir", str(tmp_path)])
    out = capsys.readouterr().out
    assert rc == 0
    cfg = json.loads(out)                      # config prints valid JSON...
    assert cfg.get("backend")                  # ...naming the resolved backend
    assert (hb / "events.jsonl").read_text() == before   # ...and it did NOT run (no events)


def test_exec_config_unknown_action_rejected(tmp_path, monkeypatch, stub):
    from heartbeat import cli
    hb = _run(tmp_path, _dag([("P0", ["P0T1"])]), monkeypatch, stub)
    before = (hb / "events.jsonl").read_text()
    rc = cli.main(["exec", "frobnicate", "--dir", str(tmp_path)])
    assert rc != 0                                         # unknown action is a usage error
    assert (hb / "events.jsonl").read_text() == before     # and does not run


def test_exec_config_run_still_drives(tmp_path, monkeypatch, stub, capsys):
    from heartbeat import cli
    _run(tmp_path, _dag([("P0", ["P0T1"])]), monkeypatch, stub)
    rc = cli.main(["exec", "run", "--dir", str(tmp_path)])
    out = capsys.readouterr().out
    assert rc == 0 and "HB-EXEC DONE" in out               # `exec run` unchanged


def test_context_hook_injects_provider_output(tmp_path, monkeypatch):
    # Seam 2: a configured context_cmd's stdout is appended to the task context, delimited.
    hb = make_hb(tmp_path, _dag([("P0", ["P0T1"])]))
    monkeypatch.setenv("HB_EXEC_CONTEXT_CMD", "echo CTX-$HB_TASK_ID")
    ctx = executor.assemble_context(hb, {"id": "P0T1", "phase": "P0", "title": "t"})
    assert "<<HB-CONTEXT>>" in ctx and "CTX-P0T1" in ctx


def test_context_hook_absent_by_default(tmp_path, monkeypatch):
    hb = make_hb(tmp_path, _dag([("P0", ["P0T1"])]))
    monkeypatch.delenv("HB_EXEC_CONTEXT_CMD", raising=False)
    ctx = executor.assemble_context(hb, {"id": "P0T1", "phase": "P0", "title": "t"})
    assert "<<HB-CONTEXT>>" not in ctx                      # byte-unchanged when unconfigured


def test_inprocess_author_mode_and_unknown_mode(monkeypatch, tmp_path):
    from heartbeat import executor, backends
    from heartbeat.backends._fileblocks import author_reply

    class Fake:
        @staticmethod
        def refute(p):
            return {"refuted": False, "findings": 'here:\n```json\n[{"id":"G1","claim":"c","subjects":["a"],"violation":"v"}]\n```'}

        @staticmethod
        def execute(p):
            raise AssertionError("an unknown mode must never fall through to execute")

    monkeypatch.setattr(backends, "get", lambda name: Fake)
    cfg = {"backend": "ollama", "cmd": None, "heartbeat_s": 60}
    (tmp_path / ".hb").mkdir()
    r = executor.dispatch(cfg, "author", {"prompt": "x"}, str(tmp_path / ".hb"), None)
    assert r == {"ok": True, "constraints": [{"id": "G1", "claim": "c", "subjects": ["a"], "violation": "v"}]}
    assert "error" in executor.dispatch(cfg, "bogus", {}, str(tmp_path / ".hb"), None)
    assert author_reply("no list here")["ok"] is False
