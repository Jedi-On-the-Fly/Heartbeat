"""Behavioral gate runner — ported from gate.sh.

Gate `cmd`s are user-authored shell one-liners (the DAG contract) run via the system
shell with $PROJECT_DIR/$HB_DIR in the environment and a per-criterion timeout. A pass
appends gate_passed and (optionally) commits+tags a git restore point.
"""
import os
import subprocess
from pathlib import Path

from . import state as st

GATE_TIMEOUT_S = int(os.environ.get("GATE_TIMEOUT_S", "5"))


def _project_dir(hbdir):
    return str(Path(hbdir).parent)


def _env(hbdir):
    env = dict(os.environ)
    env["PROJECT_DIR"] = _project_dir(hbdir)
    env["HB_DIR"] = str(hbdir)
    return env


def _run_cmd(cmd, hbdir, timeout):
    try:
        r = subprocess.run(cmd, shell=True, cwd=_project_dir(hbdir), env=_env(hbdir),
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout)
        return r.returncode == 0
    except Exception:
        return False


def eval_gate(hbdir, gate_id, timeout=None):
    """Run the criteria; no side effects. Returns None for an unknown gate."""
    timeout = GATE_TIMEOUT_S if timeout is None else timeout
    gate = (st.read_dag(hbdir).get("gates") or {}).get(gate_id)
    if gate is None:
        return None
    criteria = gate.get("criteria") or []
    if not criteria:
        # Hollow-gate floor: a zero-criteria gate proves nothing — refuse it at runtime.
        return {"passed": 0, "failed": 1,
                "lines": [f"  ✗ [--] gate {gate_id} has NO criteria — a gate must assert something"]}
    passed = failed = 0
    lines = []
    for c in criteria:
        ok = _run_cmd(c.get("cmd", ""), hbdir, timeout)
        lines.append(f"  {'✓' if ok else '✗'} [{c.get('id')}] {c.get('desc', '')}")
        passed += 1 if ok else 0
        failed += 0 if ok else 1
    return {"passed": passed, "failed": failed, "lines": lines}


def run_gate(hbdir, gate_id, check=False):
    res = eval_gate(hbdir, gate_id)
    if res is None:
        return {"status": "unknown", "gate": gate_id}
    if check:
        res.update(status="would_pass" if res["failed"] == 0 else "would_block", gate=gate_id)
        return res
    if res["failed"] == 0:
        st.mutate(hbdir, {"event": "gate_passed", "gate": gate_id, "pass": res["passed"], "fail": 0})
        _git_snapshot(hbdir, gate_id)
        review = bool((st.read_dag(hbdir).get("gates") or {}).get(gate_id, {}).get("review"))
        res.update(status="review_pending" if review else "passed", gate=gate_id)
    else:
        st.mutate(hbdir, {"event": "gate_failed", "gate": gate_id, "pass": res["passed"], "fail": res["failed"]})
        res.update(status="blocked", gate=gate_id)
    return res


def run_all(hbdir):
    total_fail = 0
    report = {}
    for g in (st.read_dag(hbdir).get("gates") or {}):
        res = eval_gate(hbdir, g)
        report[g] = res
        total_fail += res["failed"]
    return {"ok": total_fail == 0, "gates": report}


def _git(pd, *args, **kw):
    return subprocess.run(["git", "-C", pd, *args],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kw)


def _git_snapshot(hbdir, gate_id):
    if os.environ.get("HB_NO_GIT") or os.environ.get("HB_GIT_AUTOCOMMIT", "1") == "0":
        return
    pd = _project_dir(hbdir)
    if _git(pd, "rev-parse", "--is-inside-work-tree").returncode != 0:
        return
    phase = next((p for p in (st.read_dag(hbdir).get("phases") or []) if p.get("gate_exit") == gate_id), None)
    msg = (f"heartbeat({phase['id']}): {phase.get('title', phase['id'])} [{gate_id}]"
           if phase else f"heartbeat: {gate_id} passed")
    _git(pd, "add", "-A")
    subprocess.run(["git", "-c", "user.name=HeartBeat", "-c", "user.email=heartbeat@local",
                    "-C", pd, "commit", "--no-verify", "-q", "-m", msg],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    _git(pd, "tag", "-f", gate_id)
