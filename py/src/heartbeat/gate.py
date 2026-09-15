"""Behavioral gate runner — ported from gate.sh.

Gate `cmd`s are user-authored shell one-liners (the DAG contract) run via the system
shell with $PROJECT_DIR/$HB_DIR in the environment and a per-criterion timeout. A pass
appends gate_passed and (optionally) commits+tags a git restore point.
"""
import os
import shutil
import subprocess
import time
from pathlib import Path

from . import state as st

# Default sized for a REAL criterion (a test suite, a build step) — 5s killed legitimate work.
# A criterion sets its own budget with `timeout_s` in dag.json, which WINS over this default:
# the DAG (versioned config) outranks the environment (a blunt global).
GATE_TIMEOUT_S = int(os.environ.get("GATE_TIMEOUT_S", "60"))
GATE_OUT_LINES = int(os.environ.get("GATE_OUT_LINES", "20"))   # tail of a FAILING criterion's output to surface


def _project_dir(hbdir):
    # ABSOLUTE so a relative --dir doesn't double-nest: the gate runs with cwd=PROJECT_DIR,
    # and a criterion like grep "$PROJECT_DIR/out.txt" must not resolve to <proj>/<proj>/out.txt.
    # (Matches the node runtime, whose gate.sh absolutizes via `cd && pwd`.)
    return os.path.abspath(str(Path(hbdir).parent))


def _env(hbdir):
    env = dict(os.environ)
    env["PROJECT_DIR"] = _project_dir(hbdir)
    env["HB_DIR"] = os.path.abspath(str(hbdir))   # absolute for the same reason as PROJECT_DIR
    return env


def _run_cmd(cmd, hbdir, timeout):
    # Run under bash to MATCH plugin/templates/gate.sh (`bash -c`) — shell=True uses /bin/sh (often dash),
    # which silently rejects bash-isms ([[ ]], arrays) a node gate accepts. Fall back to sh only if bash
    # is genuinely absent (documented divergence). Capture output so a blocked gate is diagnosable.
    shell = shutil.which("bash") or "/bin/sh"
    try:
        r = subprocess.run([shell, "-c", cmd], cwd=_project_dir(hbdir), env=_env(hbdir),
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        return r.returncode == 0, (r.stdout or b"").decode("utf-8", "replace")
    except Exception as e:
        return False, str(e)


def eval_gate(hbdir, gate_id, timeout=None, emit=None, progress=None):
    """Run the criteria; no side effects. Returns None for an unknown gate.

    Progress hooks (a multi-minute sweep must not be silent — "slow" and "hung" have to be
    distinguishable from inside the run): `emit(line)` receives each output line AS PRODUCED,
    and `progress(id, desc, effective_timeout_s)` fires before each criterion runs.
    """
    timeout = GATE_TIMEOUT_S if timeout is None else timeout
    gate = (st.read_dag(hbdir).get("gates") or {}).get(gate_id)
    if gate is None:
        return None
    lines = []

    def _add(ln):
        lines.append(ln)
        if emit:
            emit(ln)

    criteria = gate.get("criteria") or []
    if not criteria:
        # Hollow-gate floor: a zero-criteria gate proves nothing — refuse it at runtime.
        _add(f"  ✗ [--] gate {gate_id} has NO criteria — a gate must assert something")
        return {"passed": 0, "failed": 1, "lines": lines}
    passed = failed = 0
    results = []
    for c in criteria:
        eff = timeout
        ts = c.get("timeout_s")
        if ts is not None:
            if isinstance(ts, int) and not isinstance(ts, bool) and ts >= 1:
                eff = ts   # per-criterion budget WINS over the runner default
            else:
                # Invalid timeout_s is a LOUD runtime failure of the criterion (the
                # zero-criteria-floor precedent) — never a silent fallback to the default.
                _add(f"  ✗ [{c.get('id')}] {c.get('desc', '')}")
                _add(f"      invalid timeout_s: {ts!r} (must be a positive integer)")
                results.append({"id": c.get("id"), "cmd": c.get("cmd", ""), "exit": 1})
                failed += 1
                continue
        if progress:
            progress(c.get("id"), c.get("desc", ""), eff)
        t0 = time.monotonic()
        ok, out = _run_cmd(c.get("cmd", ""), hbdir, eff)
        dt = int(time.monotonic() - t0 + 0.5)
        _add(f"  {'✓' if ok else '✗'} [{c.get('id')}] {c.get('desc', '')} ({dt}s)")
        if not ok:
            # Surface the WHY, not just the WHICH: the failing cmd (matches the node runner) and a
            # TAIL of its captured output — full output would bury the gate summary (a chatty test
            # runner), so the cut is bounded (GATE_OUT_LINES) and LOUD, never silent. A passing
            # criterion's output stays quiet.
            _add(f"      cmd: {c.get('cmd', '')}")
            if out.strip():
                tail = out.strip().splitlines()
                extra = len(tail) - GATE_OUT_LINES
                if extra > 0:
                    _add(f"      … (+{extra} earlier output lines)")
                    tail = tail[-GATE_OUT_LINES:]
                for ln in tail:
                    _add(f"      {ln}")
        results.append({"id": c.get("id"), "cmd": c.get("cmd", ""), "exit": 0 if ok else 1})
        passed += 1 if ok else 0
        failed += 0 if ok else 1
    return {"passed": passed, "failed": failed, "lines": lines, "results": results}


def run_gate(hbdir, gate_id, check=False, emit=None, progress=None):
    res = eval_gate(hbdir, gate_id, emit=emit, progress=progress)
    if res is None:
        return {"status": "unknown", "gate": gate_id}
    if check:
        res.update(status="would_pass" if res["failed"] == 0 else "would_block", gate=gate_id)
        return res
    if res["failed"] == 0:
        # Evidence provenance: per-criterion {id,cmd,exit}, the commit tested, the runtime.
        commit = None
        if shutil.which("git"):   # git is optional — never crash a gate pass on a git-less machine
            commit = subprocess.run(["git", "-C", _project_dir(hbdir), "rev-parse", "HEAD"],
                                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.decode().strip() or None
        st.mutate(hbdir, {"event": "gate_passed", "gate": gate_id, "pass": res["passed"], "fail": 0,
                          "criteria": res.get("results", []), "commit": commit, "runtime": "python"})
        review = bool((st.read_dag(hbdir).get("gates") or {}).get(gate_id, {}).get("review"))
        # A review-gated phase's restore point (commit+tag) is created at review acceptance
        # (cli.py review pass), NOT here — the tag must never certify an un-reviewed state.
        if not review:
            _git_snapshot(hbdir, gate_id)
        res.update(status="review_pending" if review else "passed", gate=gate_id)
    else:
        st.mutate(hbdir, {"event": "gate_failed", "gate": gate_id, "pass": res["passed"], "fail": res["failed"]})
        res.update(status="blocked", gate=gate_id)
    return res


def armed_gates(hbdir):
    """Split defined gates into (armed, planned): armed = has a recorded gate_passed event.
    Filter on the event log (truth), not the projection: gate_failed/review_failed reset the
    projection's det flag, and a once-proven gate must stay armed through a recorded failure."""
    passed_ever = {e.get("gate") for e in st.read_events(hbdir) if e.get("event") == "gate_passed"}
    gates = st.read_dag(hbdir).get("gates") or {}
    return [g for g in gates if g in passed_ever], [g for g in gates if g not in passed_ever]


def run_all(hbdir, emit=None, progress=None):
    # Regression semantics: a gate that has EVER passed keeps acting as a gate (re-verified here);
    # a gate that has never passed — a drafted/planned future phase — has nothing to regress from
    # and is SKIPPED, loudly (returned in "skipped" so callers must report it, never hide it).
    armed, skipped = armed_gates(hbdir)
    total_fail = 0
    report = {}
    t0 = time.monotonic()
    for g in armed:
        res = eval_gate(hbdir, g, emit=emit, progress=progress)
        report[g] = res
        total_fail += res["failed"]
    return {"ok": total_fail == 0, "gates": report, "skipped": skipped,
            "elapsed_s": int(time.monotonic() - t0 + 0.5)}


def _git(pd, *args, **kw):
    return subprocess.run(["git", "-C", pd, *args],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kw)


def _git_snapshot(hbdir, gate_id):
    if os.environ.get("HB_NO_GIT") or os.environ.get("HB_GIT_AUTOCOMMIT", "1") == "0":
        return
    if not shutil.which("git"):   # git is optional
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
