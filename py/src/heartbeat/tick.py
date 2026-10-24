"""Stage A — the tick. Ported from tick.sh with the same priority order.

Returns {"wakeAgent": bool, "data": {...}}. On a wake, data.action is injected from the
PROTOCOL map so any driver knows the exact next action from the JSON alone.
"""
import json
import os
import shutil
import time
from pathlib import Path

from . import state as st
from . import resolver as rv
from . import doctor as doc
from .protocol import PROTOCOL

LOCK_STALE_S = int(os.environ.get("LOCK_STALE_S", "1800"))
HEARTBEAT_STALE_S = int(os.environ.get("HEARTBEAT_STALE_S", "180"))
STUCK_TICKS = int(os.environ.get("STUCK_TICKS", "3"))
HB_MAX_CONCURRENCY = int(os.environ.get("HB_MAX_CONCURRENCY", "1"))
HB_ROT_CHECK = os.environ.get("HB_ROT_CHECK", "1")


def _wake(data):
    r = data.get("reason")
    if r and r in PROTOCOL:
        data["action"] = PROTOCOL[r]
    return {"wakeAgent": True, "data": data}


def _sleep(data):
    return {"wakeAgent": False, "data": data}


def _flag(hbdir, name):
    return Path(hbdir) / name


def _rm(p):
    try:
        Path(p).unlink()
    except OSError:
        pass


def _flag_text(p):
    try:
        return Path(p).read_text()
    except OSError:
        return None


def _replan_wake(hbdir, nxt, phase):
    _flag(hbdir, ".replan-alerted").write_text(phase)
    return _wake({"reason": "replan_pending", "phase": phase, "next_task": nxt})


def tick(hbdir):
    hbdir = Path(hbdir)
    lock = hbdir / ".lock"
    try:
        lock.mkdir()
    except FileExistsError:
        age = time.time() - lock.stat().st_mtime
        if age < LOCK_STALE_S:
            return _sleep({"reason": "already_running", "lock_age_s": int(age)})
        shutil.rmtree(lock, ignore_errors=True)
        lock.mkdir()
    try:
        return _body(hbdir)
    finally:
        shutil.rmtree(lock, ignore_errors=True)


def _body(hbdir):
    # 2. state integrity (self-heal by reprojecting; only wake if the log is unusable)
    try:
        json.loads((hbdir / "state.json").read_text())
    except Exception:
        try:
            st.reproject(hbdir)
        except Exception:
            return _wake({"reason": "state_corrupted"})
    # 3. dag integrity
    try:
        json.loads((hbdir / "dag.json").read_text())
    except Exception:
        return _wake({"reason": "dag_corrupted"})

    # 4. reclaim stale leases
    leases = hbdir / "leases"
    if leases.is_dir():
        reclaimed = False
        for d in list(leases.iterdir()):
            if not d.is_dir():
                continue
            beat = d / "beat"
            ref, threshold = ((beat.stat().st_mtime, HEARTBEAT_STALE_S) if beat.exists()
                              else (d.stat().st_mtime, LOCK_STALE_S))
            if time.time() - ref >= threshold:
                st.append_event(hbdir, {"event": "lease_expired", "task": d.name})
                shutil.rmtree(d, ignore_errors=True)
                reclaimed = True
        if reclaimed:
            st.reproject(hbdir)

    # 5. doctor-driven checks: criteria drift (outranks rot; EVERY tick until cured —
    # no once-only flag: laundering must never fade into a waiting sleep), then rot.
    # The guard lines are strip-clean COMPLETE statements, never a block header (a refuter
    # catch: a marker on a structural `if` strips into an IndentationError — red for the
    # wrong reason, the detach-wave lesson).
    _dft = st.drifted_gates(st.read_events(hbdir), st.read_dag(hbdir).get("gates") or {}) if HB_ROT_CHECK != "0" else []   # drift-guard: tick — the per-tick doctor filter, widened to the drift problem
    if _dft: return _wake({"reason": "criteria_drift", "count": len(_dft), "gates": _dft})   # drift-guard: tick — human-needed, every tick until cured
    if HB_ROT_CHECK != "0" and doc.has_rot(hbdir):
        if not _flag(hbdir, ".rot-alerted").exists():
            _flag(hbdir, ".rot-alerted").touch()
            return _wake({"reason": "gate_rot", "hint": "a completed phase's gate references a deleted file — run: hb doctor"})
        return _sleep({"reason": "gate_rot_waiting"})
    _rm(_flag(hbdir, ".rot-alerted"))

    state = st.project(st.read_events(hbdir), st.read_dag(hbdir))

    # 6. circuit breaker
    if state["build_stuck_count"] >= 5:
        if not _flag(hbdir, ".stuck-alerted").exists():
            _flag(hbdir, ".stuck-alerted").touch()
            return _wake({"reason": "build_stuck", "build_stuck_count": state["build_stuck_count"]})
        return _sleep({"reason": "stuck_waiting_human", "build_stuck_count": state["build_stuck_count"]})
    _rm(_flag(hbdir, ".stuck-alerted"))

    # 8. gate errors from a previous run — with a circuit breaker (mirrors the build_stuck breaker):
    # a persistently blocked gate must not re-wake the agent every tick forever.
    gbt_file = _flag(hbdir, ".gate-blocked-ticks")
    if state["gate"]["errors"] > 0:
        try:
            gbt = int(gbt_file.read_text().strip() or "0")
        except Exception:
            gbt = 0
        gbt += 1
        gbt_file.write_text(str(gbt))
        if gbt >= int(os.environ.get("GATE_BLOCKED_MAX", "5")):
            return _sleep({"reason": "gate_blocked_waiting_human", "gate_errors": state["gate"]["errors"], "ticks": gbt})
        return _wake({"reason": "gate_blocked", "gate_errors": state["gate"]["errors"], "ticks": gbt})
    _rm(gbt_file)

    # 9. next task
    dag = st.read_dag(hbdir)
    nxt = rv.resolve(state, dag, hbdir)
    if nxt is None:
        return _sleep({"reason": "no_pending_tasks"})
    typ = nxt.get("type", "task")

    if typ == "all_done":
        _rm(_flag(hbdir, ".replan-alerted"))
        if not _flag(hbdir, ".all-done-alerted").exists():
            _flag(hbdir, ".all-done-alerted").touch()
            return _wake({"reason": "all_done", "next_task": nxt})
        return _sleep({"reason": "project_complete"})
    if typ == "replan_pending":
        # The flagged last phase completed: a replan decision is owed. Wake ONCE per horizon
        # phase — the flag stores the phase id, so a stale flag never silences a newer horizon.
        # No event: the log records decisions, not notifications (== tick.sh).
        _rm(_flag(hbdir, ".deadlock-alerted"))
        rp_phase = str(nxt.get("phase") or "")
        if _flag_text(_flag(hbdir, ".replan-alerted")) != rp_phase: return _replan_wake(hbdir, nxt, rp_phase)  # horizon-guard: tick
        return _sleep({"reason": "replan_waiting", "phase": rp_phase})
    if typ == "deadlock":
        if not _flag(hbdir, ".deadlock-alerted").exists():
            _flag(hbdir, ".deadlock-alerted").touch()
            return _wake({"reason": "deadlock", "next_task": nxt})
        return _sleep({"reason": "deadlock_waiting", "detail": nxt})
    if typ == "busy":
        _rm(_flag(hbdir, ".deadlock-alerted"))
        return _sleep({"reason": "at_capacity", "detail": nxt})
    if typ == "gate_pending":
        _rm(_flag(hbdir, ".deadlock-alerted"))
        # A pending regate needs a DIFFERENT actor's rearm — waking gate_pending forever over it
        # would busy-loop every unattended run (refusals append no event, so no breaker trips).
        # Sleep a non-PROTOCOL reason instead (the gate_blocked_waiting_human precedent; == tick.sh).
        _rgt = st.regate_blocks((st.read_dag(hbdir).get("gates") or {}).get(nxt.get("gate")))   # regate-guard: tick-sleep (fail-closed predicate)
        if _rgt is not None: return _sleep({"reason": "regate_pending_waiting", "gate": nxt.get("gate")})   # regate-guard: tick-sleep
        return _wake({"reason": "gate_pending", "next_task": nxt})
    if typ == "review_pending":
        _rm(_flag(hbdir, ".deadlock-alerted"))
        gate = nxt.get("gate")
        _rgr = st.regate_blocks((st.read_dag(hbdir).get("gates") or {}).get(gate))   # regate-guard: tick-sleep (fail-closed predicate)
        if _rgr is not None: return _sleep({"reason": "regate_pending_waiting", "gate": gate})   # regate-guard: tick-sleep
        # Mirror tick.sh: an adversarial review that never resolves is escalated past STUCK_TICKS
        # (review_stuck, single-alert) instead of waking review_pending forever — a liveness guard.
        noreview = _review_wakes_since_verdict(hbdir, gate)
        if gate and noreview >= STUCK_TICKS:
            if not _flag(hbdir, ".review-stuck-alerted").exists():
                _flag(hbdir, ".review-stuck-alerted").touch()
                st.append_event(hbdir, {"event": "review_stalled", "gate": gate})
                return _wake({"reason": "review_stuck", "gate": gate, "no_review": noreview,
                              "hint": "the adversarial review isn't resolving — run the refuter, then: hb review %s pass|fail" % gate})
            return _sleep({"reason": "review_waiting", "gate": gate})
        _rm(_flag(hbdir, ".review-stuck-alerted"))
        st.append_event(hbdir, {"event": "review_wake", "gate": gate})
        return _wake({"reason": "review_pending", "next_task": nxt})

    # a real task
    _rm(_flag(hbdir, ".all-done-alerted"))
    _rm(_flag(hbdir, ".replan-alerted"))
    _rm(_flag(hbdir, ".deadlock-alerted"))
    task_id = nxt.get("id")

    in_flight = len([d for d in (list(leases.iterdir()) if leases.is_dir() else []) if d.is_dir()])
    if task_id and in_flight >= HB_MAX_CONCURRENCY:
        return _sleep({"reason": "at_capacity", "in_flight": in_flight, "max": HB_MAX_CONCURRENCY})

    noprog = _wakes_since_progress(hbdir, task_id)
    if task_id and noprog >= STUCK_TICKS:
        if not _flag(hbdir, ".noprogress-alerted").exists():
            _flag(hbdir, ".noprogress-alerted").touch()
            return _wake({"reason": "build_stuck", "signal": "no_progress", "task": task_id, "no_progress": noprog})
        return _sleep({"reason": "stuck_waiting_human", "signal": "no_progress", "task": task_id})
    _rm(_flag(hbdir, ".noprogress-alerted"))

    if task_id:
        st.acquire_lease(hbdir, task_id)
        st.append_event(hbdir, {"event": "wake", "task": task_id})
    return _wake({"reason": "next_task", "next_task": nxt})


def _wakes_since_progress(hbdir, task_id):
    n = 0
    for ev in reversed(st.read_events(hbdir)):
        if ev.get("task") == task_id and ev.get("event") in ("task_started", "task_done", "task_failed"):
            break
        if ev.get("event") == "wake" and ev.get("task") == task_id:
            n += 1
    return n


def _review_wakes_since_verdict(hbdir, gate):
    # review_wake events for `gate` since its last verdict (mirrors tick.sh's noreview count).
    n = 0
    for ev in reversed(st.read_events(hbdir)):
        if ev.get("gate") == gate and ev.get("event") in ("review_passed", "review_failed", "gate_passed"):
            break
        if ev.get("event") == "review_wake" and ev.get("gate") == gate:
            n += 1
    return n
