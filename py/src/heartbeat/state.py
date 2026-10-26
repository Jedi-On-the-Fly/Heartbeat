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


def dag_shape_problems(hbdir):
    """The shape contract (T186): the structure errors of dag.json as it sits on disk, read through
    the checked file read — never read_dag()'s empty-plan fallback. [] when structurally sound.
    Twin: hb.js dagShapeProblems."""
    from . import lint as lintmod
    dag, err = lintmod.read_dag_file(dag_path(hbdir))
    return [err] if err else lintmod.shape_errors(dag, True)


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
    horizon_closed = []  # phases whose knowledge horizon was closed by a recorded verdict, insertion-ordered

    def gs(g):
        return gate_state.setdefault(g, {"det": False, "rev": False})

    for ev in events:
        e = ev.get("event")
        if e == "initialized":
            completed.clear()
            active.clear()
            gate_state.clear()
            horizon_closed.clear()
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
        elif e == "horizon_closed":
            ph = ev.get("phase")
            if isinstance(ph, str) and ph and ph not in horizon_closed:
                horizon_closed.append(ph)
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
    # Sparse: the key exists only once a horizon was closed — horizon-less projections stay
    # byte-identical (mirrors hb.js).
    if horizon_closed:
        s["horizon_closed"] = list(horizon_closed)

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


def write_dag(hb, dag):
    # Every dag.json rewrite goes through here: tmp + rename, never in place (== hb.js writeDag, T188).
    atomic_write(Path(hb, "dag.json"), json.dumps(dag, indent=2))   # dag-write-guard


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


_SUBSTANTIVE_WS = " \t\n\r\f\v"


def substantive_len(s):
    """Length after trimming ONE explicit whitespace set (ASCII only — the lint _ASCII_WS
    precedent): str.strip() and JS trim() disagree on \\ufeff / \\x85 / \\x1c-\\x1f, so a
    thin-artifact boundary judged with the native trims DIVERGES between the runtimes (a
    refuter catch). Twin: hb.js substantiveLen."""
    return len(str(s).strip(_SUBSTANTIVE_WS))


def unanswered_regate(events, gate):
    """True while the log attests an UNANSWERED revision: a gate_regated with no later
    gate_rearmed. The event log is truth — a hand-cleared, hand-restored or fabricated dag
    marker must not launder an acceptance past the rearm bar (a refuter catch).
    Twin: hb.js unansweredRegate."""
    un = False
    for e in events:
        if e.get("event") == "gate_regated" and e.get("gate") == gate:
            un = True
        elif e.get("event") == "gate_rearmed" and e.get("gate") == gate:
            un = False
    return un


def stale_rearm(events, gate):
    """True when <gate> has a gate_rearmed with NO LATER provenanced gate_passed. "Provenanced" =
    the criteria/runtime evidence fields a real evaluation stamps — `hb import`'s bare synthetic
    pass never counts, so it cannot launder a revision into an acceptance. Review verdicts and the
    executors refuse in this window: acceptance after a revision requires a FRESH pass of the
    revised criteria. Twin: hb.js staleRearm."""
    last = -1
    for i, e in enumerate(events):
        if e.get("event") == "gate_rearmed" and e.get("gate") == gate:
            last = i
    if last == -1:
        return False
    for e in events[last + 1:]:
        if e.get("event") == "gate_passed" and e.get("gate") == gate and \
                ((isinstance(e.get("criteria"), list) and e["criteria"]) or e.get("runtime")):
            return False
    return True


def _canon_crit(c):
    """Identity canonicalization: the (id, cmd) pair as compact JSON — a missing field reads as
    null, a non-dict criteria entry as '!invalid' — so hostile shapes classify IDENTICALLY on
    both runtimes and can never crash the walk (a refuter catch: String()/str() coercions split
    them). The schema's domain for id/cmd is STRINGS, compared byte-exact; out-of-schema values
    compare as a TYPE CLASS (all numbers one token — a second refuter catch: mimicking JS number
    formatting splits at the 2^53/exponent boundaries; the honest limit is class identity, and a
    real weakening still trips on the string cmd). Twin: hb.js canonCrit."""
    if not isinstance(c, dict):
        return "!invalid"

    def f(v):
        if v is None:
            return None
        if isinstance(v, str):
            return v
        if isinstance(v, bool):
            return "!bool:" + ("true" if v else "false")
        if isinstance(v, (int, float)):
            return "!num"
        return "!obj"
    return json.dumps([f(c.get("id")), f(c.get("cmd"))], separators=(",", ":"), ensure_ascii=False)


def drifted_gates(events, gates):
    """The drift tripwire walk (T184). For each gate ever CRITERIA-PINNED (a gate_passed carrying
    a non-empty criteria array — bare/import passes never pin, the stale_rearm precedent), walk
    its pins in log order plus the current dag criteria as the final element; identity is the
    ORDERED (id, cmd) pairs byte-exact (desc/timeout_s are NOT pinned — the honest limit). Any
    ADJACENT difference is UNSANCTIONED DRIFT unless (i) a gate_regated FOR THAT GATE lies
    between the two points (contemporaneous sanction — a still-open declare sanctions the final
    pair, and the regate machinery already fails that gate closed), or (ii) a COMPLETED regate
    cycle — gate_regated then gate_rearmed then a fresh criteria-pinned pass, in order, the WHOLE
    cycle (its gate_regated included) after the pair's later point (ABSOLUTION: late rigor is
    still rigor; the last cycle absolves all earlier drift on that gate; the unsanctioned window
    stays in the log). A gate absent from the dag compares as always-different: removal is the
    same drift. Twin: hb.js driftedGates."""
    pins, regated, rearmed = {}, {}, {}
    for i, e in enumerate(events):
        g = e.get("gate")
        if not g:
            continue
        if e.get("event") == "gate_passed" and isinstance(e.get("criteria"), list) and e["criteria"]:
            pins.setdefault(g, []).append((i, [_canon_crit(c) for c in e["criteria"]]))
        elif e.get("event") == "gate_regated":
            regated.setdefault(g, []).append(i)
        elif e.get("event") == "gate_rearmed":
            rearmed.setdefault(g, []).append(i)
    out = []
    inf = float("inf")
    for g, P in pins.items():
        cur = ((gates.get(g) or {}).get("criteria") or []) if g in gates else None
        S = list(P) + [(inf, None if cur is None else [_canon_crit(c) for c in cur])]
        last_cycle = -1   # start position (the gate_regated) of the LAST completed cycle
        for r in regated.get(g, []):
            m = next((x for x in rearmed.get(g, []) if x > r), None)
            if m is not None and any(pos > m for pos, _ in P):
                last_cycle = max(last_cycle, r)
        same = lambda a, b: a is not None and b is not None and json.dumps(a) == json.dumps(b)
        for i in range(len(S) - 1):
            if same(S[i][1], S[i + 1][1]):
                continue
            sanctioned = any(S[i][0] < r < S[i + 1][0] for r in regated.get(g, []))
            absolved = last_cycle > S[i + 1][0]
            if not (sanctioned or absolved):
                out.append(g)
                break
    return sorted(out)


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
