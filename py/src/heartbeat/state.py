"""Event-sourced state — events.jsonl is authoritative, state.json is a projection.

Ported from the node hb.js projector with identical semantics. Every mutation is:
append event -> reproject the whole log -> atomic write, guarded by a write-lock.
"""
import json
import os
import shutil
import time
from pathlib import Path

LOCK_STALE_S = int(os.environ.get("LOCK_STALE_S", "1800"))


def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def events_path(hbdir):
    return Path(hbdir) / "events.jsonl"


def state_path(hbdir):
    return Path(hbdir) / "state.json"


def dag_path(hbdir):
    return Path(hbdir) / "dag.json"


def leases_dir(hbdir):
    return Path(hbdir) / "leases"


def read_dag(hbdir):
    try:
        return json.loads(dag_path(hbdir).read_text())
    except Exception:
        return {"phases": [], "gates": {}}


def read_events(hbdir):
    out = []
    try:
        text = events_path(hbdir).read_text()
    except OSError:
        return out
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except Exception:
            pass  # skip malformed audit line
    return out


def initial_state(dag):
    phases = dag.get("phases") or []
    first = phases[0]["id"] if phases else None
    return {
        "current_phase": first,
        "active_tasks": [],
        "completed_tasks": [],
        "completed_phases": [],
        "pending_reviews": [],
        "build_stuck_count": 0,
        "gate": {"errors": 0},
        "last_event": "initialized",
        "last_updated": now_iso(),
    }


def phase_by_gate_exit(dag, gate):
    for p in (dag.get("phases") or []):
        if p.get("gate_exit") == gate:
            return p["id"]
    return None


def project(events, dag):
    """Pure: (events, dag) -> state. Deterministic except last_updated."""
    s = initial_state(dag)
    completed, active = set(), set()
    gate_state = {}

    def gs(g):
        return gate_state.setdefault(g, {"det": False, "rev": False})

    for ev in events:
        e = ev.get("event")
        if e == "initialized":
            completed.clear()
            active.clear()
            gate_state.clear()
            s["build_stuck_count"] = 0
            s["gate"]["errors"] = 0
        elif e == "task_started":
            t = ev.get("task")
            if t and t not in completed:
                active.add(t)
        elif e == "task_done":
            t = ev.get("task")
            if t:
                completed.add(t)
                active.discard(t)
            s["build_stuck_count"] = 0
        elif e == "task_failed":
            t = ev.get("task")
            if t:
                active.discard(t)
            s["build_stuck_count"] += 1
        elif e == "lease_expired":
            t = ev.get("task")
            if t:
                active.discard(t)
        elif e == "gate_passed":
            gs(ev.get("gate"))["det"] = True
            s["gate"]["errors"] = 0
            s["build_stuck_count"] = 0
        elif e == "gate_failed":
            gs(ev.get("gate"))["det"] = False
            s["gate"]["errors"] = 1
            s["build_stuck_count"] += 1
        elif e == "review_passed":
            gs(ev.get("gate"))["rev"] = True
        elif e == "review_failed":
            g = gs(ev.get("gate"))
            g["det"] = False
            g["rev"] = False
            s["gate"]["errors"] = 1
            s["build_stuck_count"] += 1
        if e:
            s["last_event"] = e

    phases = dag.get("phases") or []
    gates = dag.get("gates") or {}
    completed_phases = set()
    pending_reviews = []
    for ph in phases:
        g = ph.get("gate_exit")
        if not g:
            continue
        st = gate_state.get(g)
        if not st or not st["det"]:
            continue
        if gates.get(g, {}).get("review") and not st["rev"]:
            continue  # deterministic pass, review owed
        completed_phases.add(ph["id"])
    for g, gv in gates.items():
        st = gate_state.get(g)
        if gv.get("review") and st and st["det"] and not st["rev"]:
            pending_reviews.append(g)

    s["completed_tasks"] = sorted(completed)
    s["active_tasks"] = sorted(active)
    s["completed_phases"] = sorted(completed_phases)
    s["pending_reviews"] = pending_reviews

    cur = None
    for ph in phases:
        if ph["id"] not in completed_phases:
            cur = ph["id"]
            break
    if cur is None and phases:
        cur = phases[-1]["id"]
    s["current_phase"] = cur
    s["last_updated"] = now_iso()
    return s


def atomic_write(path, data):
    path = Path(path)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(data)
    os.replace(tmp, path)


def atomic_write_bytes(path, data):
    path = Path(path)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, path)


def append_event(hbdir, ev):
    ev.setdefault("ts", now_iso())
    ev.setdefault("actor", os.environ.get("HB_ACTOR", "unknown"))   # identity for adversarial review
    with open(events_path(hbdir), "a") as f:
        f.write(json.dumps(ev) + "\n")


def reproject(hbdir):
    s = project(read_events(hbdir), read_dag(hbdir))
    atomic_write(state_path(hbdir), json.dumps(s, indent=2))
    return s


def regate_blocks(gate_value):
    """Fail-closed regate predicate: a gate carrying a `regate` key BLOCKS evaluation/acceptance
    unless the record is a well-formed dict whose pending is exactly False (a rearmed revision).
    A malformed record (wrong type, truthy junk) blocks — lint names it; a permissive read would
    let a hand-mangled marker silently disarm the perimeter, and the two runtimes' truthiness
    rules disagree on []/{} (a refuter catch). Returns the blocking record ({} when unreadable)
    or None when clear. Twin: hb.js regateBlocks."""
    gv = gate_value or {}
    if "regate" not in gv:
        return None
    r = gv["regate"]
    if isinstance(r, dict) and r.get("pending") is False:
        return None
    return r if isinstance(r, dict) else {}


def with_wlock(hbdir, fn):
    wlock = Path(hbdir) / ".wlock"
    deadline = time.time() + 5
    while True:
        try:
            wlock.mkdir()
            break
        except FileExistsError:
            try:
                age = time.time() - wlock.stat().st_mtime
                if age > LOCK_STALE_S:
                    shutil.rmtree(wlock, ignore_errors=True)
                    continue
            except OSError:
                pass
            if time.time() > deadline:
                raise RuntimeError("hb: write-lock timeout")
            time.sleep(0.05)
    try:
        return fn()
    finally:
        shutil.rmtree(wlock, ignore_errors=True)


def mutate(hbdir, ev):
    first = []
    def _do():
        append_event(hbdir, ev)
        # The plan's start anchor, at the ONE layer every live entry point (CLI, MCP, exec)
        # shares. "Is this the first task_started?" is decided INSIDE the lock (exactly one
        # caller can see a count of 1); the tree hash runs AFTER it, so a large project never
        # holds other writers past the lock timeout.
        if ev.get("event") == "task_started":
            from . import anchors
            first.append(anchors.is_first_start(hbdir))
        return reproject(hbdir)
    s = with_wlock(hbdir, _do)
    if first and first[0]:
        from . import anchors
        anchors.try_anchor(hbdir, "_start")
    return s


def acquire_lease(hbdir, task):
    leases_dir(hbdir).mkdir(parents=True, exist_ok=True)
    try:
        (leases_dir(hbdir) / task).mkdir()
        return True
    except FileExistsError:
        return False


def release_lease(hbdir, task):
    shutil.rmtree(leases_dir(hbdir) / task, ignore_errors=True)


def read_state(hbdir):
    try:
        return json.loads(state_path(hbdir).read_text())
    except Exception:
        return None
