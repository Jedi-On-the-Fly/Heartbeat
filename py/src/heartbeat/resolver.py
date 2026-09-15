"""Gate-aware resolver — ported from node hb-next-task.js.

A phase is eligible only once its gate_entry has passed. Leased tasks (.hb/leases/<id>)
are runtime claims and are excluded from handout.
"""
import os
from pathlib import Path

from . import lint as lintmod


def _build_context(state, dag, hbdir):
    phases = dag.get("phases") or []
    completed_phases = set(state.get("completed_phases") or [])
    pending_reviews = set(state.get("pending_reviews") or [])
    task_status = {}
    for t in (state.get("completed_tasks") or []):
        task_status[t] = "done"
    for t in (state.get("active_tasks") or []):
        task_status[t] = "active"
    leased = set()
    try:
        for t in os.listdir(Path(hbdir) / "leases"):
            leased.add(t)
            task_status.setdefault(t, "leased")
    except OSError:
        pass
    gate_passed = set()
    for p in phases:
        if p["id"] in completed_phases and p.get("gate_exit"):
            gate_passed.add(p["gate_exit"])
    return dict(phases=phases, completed_phases=completed_phases, pending_reviews=pending_reviews,
                task_status=task_status, leased=leased, gate_passed=gate_passed)


def _live(phase):
    # A parked phase is out of the plan's live surface: its tasks are never offered, it never
    # produces gate_pending/review_pending, and all_done is computed without it. Note that
    # gate_passed (in _build_context) is still computed over ALL phases — parking a completed
    # phase must not re-block downstream phases whose gate_entry it satisfied.
    return not phase.get("parked")


def _eligible(task, ctx):
    if ctx["task_status"].get(task["id"], "pending") != "pending":
        return False
    return all(ctx["task_status"].get(r) == "done" for r in (task.get("requires") or []))


def _view(task, phase):
    return {"id": task["id"], "phase": phase["id"], "title": task.get("title", task["id"]),
            "description": task.get("description", ""), "requires": task.get("requires") or []}


def ready_tasks(state, dag, hbdir, limit=0):
    ctx = _build_context(state, dag, hbdir)
    out = []
    for phase in ctx["phases"]:
        if not _live(phase):
            continue
        if phase["id"] in ctx["completed_phases"]:
            continue
        if phase.get("gate_entry") and phase["gate_entry"] not in ctx["gate_passed"]:
            continue
        for task in (phase.get("tasks") or []):
            if not _eligible(task, ctx):
                continue
            out.append(_view(task, phase))
            if limit and len(out) >= limit:
                return out
    return out


def resolve(state, dag, hbdir):
    ctx = _build_context(state, dag, hbdir)
    phases = ctx["phases"]
    completed_phases = ctx["completed_phases"]
    for phase in phases:
        if not _live(phase):
            continue
        if phase["id"] in completed_phases:
            continue
        if phase.get("gate_entry") and phase["gate_entry"] not in ctx["gate_passed"]:
            continue
        tasks = phase.get("tasks") or []
        for task in tasks:
            if _eligible(task, ctx):
                return _view(task, phase)
        if tasks and all(ctx["task_status"].get(t["id"]) == "done" for t in tasks):
            if phase.get("gate_exit") and phase["gate_exit"] in ctx["pending_reviews"]:
                return {"type": "review_pending", "phase": phase["id"], "gate": phase["gate_exit"]}
            return {"type": "gate_pending", "phase": phase["id"], "gate": phase.get("gate_exit")}

    if not phases:
        return None
    if all(p["id"] in completed_phases for p in phases if _live(p)):
        return {"type": "all_done"}

    def _scan(pred):
        found = []
        for phase in phases:
            if not _live(phase):
                continue
            if phase["id"] in completed_phases:
                continue
            if phase.get("gate_entry") and phase["gate_entry"] not in ctx["gate_passed"]:
                continue
            for t in (phase.get("tasks") or []):
                if pred(t):
                    found.append(t["id"])
        return found

    in_flight = _scan(lambda t: t["id"] in ctx["leased"])
    if in_flight:
        return {"type": "busy", "in_flight": in_flight}

    orphans = _scan(lambda t: ctx["task_status"].get(t["id"]) == "active")
    if orphans:
        return {"type": "deadlock", "cause": "active_orphan",
                "detail": {"tasks": orphans, "hint": "free these IDs (hb fail <id>) or mark them done"}}

    res = lintmod.lint(dag)
    if res["errors"]:
        return {"type": "deadlock", "cause": "dag_invalid", "detail": {"errors": res["errors"][:5]}}
    return {"type": "deadlock", "cause": "unsatisfiable",
            "detail": {"hint": "no eligible task — run: hb lint"}}
