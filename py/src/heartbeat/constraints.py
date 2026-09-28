"""Gate-time constraint author (constraint-first review) — node twin: the constraint section of hb.js.

A CONSTRAINED gate has non-empty plan-time review.constraints. At review time an author who did not
do the work writes G-id constraints from the plan + what the phase changed; HeartBeat records them
once per REVIEW CYCLE (a deterministic pass leaving the gate review_pending, until its review
verdict) as .hb/constraints/<gate>.json + a constraints_recorded {gate, ids, sha256, actor, model}.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
from pathlib import Path

from . import anchors
from . import lint as lintmod
from . import state as st


def plan_constraints(dag, gate):
    cs = ((((dag.get("gates") or {}).get(gate) or {}).get("review")) or {}).get("constraints")
    return cs if isinstance(cs, list) else []


def phase_doers(dag, gate, events):
    ph = next((p for p in (dag.get("phases") or []) if p.get("gate_exit") == gate), None)
    ids = {t["id"] for t in ((ph or {}).get("tasks") or [])}
    return {e.get("actor") for e in events if e.get("event") == "task_done" and e.get("task") in ids
            and e.get("actor") and e.get("actor") != "unknown"}


def review_cycle(hbdir, dag, gate):
    """A cycle starts after the gate's last REVIEW VERDICT — re-running the gate while the review is
    owed (a new gate_passed) must NOT start a new cycle, or a second author could re-record a weaker set."""
    events = st.read_events(hbdir)
    pending = gate in (st.project(events, dag).get("pending_reviews") or [])
    start = max((i for i, e in enumerate(events)
                 if e.get("event") in ("review_failed", "review_passed") and e.get("gate") == gate), default=-1)
    recorded = any(i > start and e.get("event") == "constraints_recorded" and e.get("gate") == gate
                   for i, e in enumerate(events))
    return pending, recorded, events


SAFE_GATE_ID = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.-]*")


def compose_author_prompt(hbdir, dag, gate):
    ph = next((p for p in (dag.get("phases") or []) if p.get("gate_exit") == gate), None) or {"id": "?", "tasks": []}
    gv = (dag.get("gates") or {}).get(gate) or {}
    title = ph.get("title") or ph["id"]
    L = [f"You are the CONSTRAINT AUTHOR for HeartBeat gate {gate} (phase {ph['id']}: {title}).",
         "Write falsifiable constraints on the behaviour this phase claims to deliver — do not hunt for bugs "
         "and do not judge the work; a separate refuter will test each constraint you write.",
         "", f"## Phase {ph['id']}: {title}"]
    if isinstance(ph.get("desc"), str) and ph["desc"]:
        L.append(ph["desc"])
    L.append("Tasks:")
    for t in (ph.get("tasks") or []):
        d = t.get("description")
        L.append(f"  - {t['id']}: {t.get('title') or ''}{(' — ' + d) if d else ''}")
    L += ["", f"## Gate {gate}", gv["desc"] if isinstance(gv.get("desc"), str) and gv["desc"] else "(no description)",
          "", "## Plan-time constraints (fixed at plan time — do not repeat them)"]
    for c in plan_constraints(dag, gate):
        L.append(f"  - {c.get('id')}: {c.get('claim')}")
        L.append(f"      subjects: {', '.join(c.get('subjects') or [])}")
        L.append(f"      violated if: {c.get('violation')}")
    L.append("")
    try:
        ch, why = anchors.changed(hbdir, gate), None
    except ValueError as e:
        ch, why = None, str(e)
    L.append(f"## What this phase changed ({ch['base']} → {ch['target']})" if ch else "## What this phase changed")
    if not ch:
        L.append(f"  (unavailable: {why})")
    else:
        for k, t in (("A", ch["added"]), ("M", ch["modified"]), ("D", ch["deleted"])):
            for p in t:
                L.append(f"  {k} {anchors.safe_path(p)}")
        if not (ch["added"] or ch["modified"] or ch["deleted"]):
            L.append("  (no changes)")
    L += ["", "## Your output", "A JSON array, ids G1..Gn in order:",
          '[{"id": "G1", "claim": "…", "subjects": ["…"], "violation": "…"}]',
          "- claim: a property of the changed behaviour that the plan-time constraints do not already pin",
          "- subjects: the files/areas it covers (from the change list above)",
          "- violation: the concrete, observable result that would falsify it",
          "Record it (as an actor who did not do this phase's work):",
          f"  hb constraints {gate} --record <file.json>"]
    return "\n".join(L)


def _no_constant(c):
    raise ValueError(f"{c} is not valid JSON")   # NaN/Infinity: node's JSON.parse rejects them too


def record(hbdir, dag, gate, file, model=None):
    """Returns (rc, out, err). Check-then-write happens under ONE write lock, so two concurrent
    records cannot both see "not recorded"."""
    if not SAFE_GATE_ID.fullmatch(gate):
        return 1, "", f"hb constraints --record: gate id '{gate}' is not usable as a file name"
    actor = os.environ.get("HB_ACTOR")
    norm = lambda a: str(a).strip().lower()  # noqa: E731
    try:
        raw = Path(file).read_bytes()
    except OSError as e:
        return 1, "", f"hb constraints --record: cannot read {file} ({e.strerror or e})"
    try:
        lst = json.loads(raw.decode("utf-8"), parse_constant=_no_constant)
    except (ValueError, UnicodeDecodeError) as e:
        return 1, "", f"hb constraints --record: {file} is not valid JSON ({e})"
    if not isinstance(lst, list) or not lst:
        return 1, "", "hb constraints --record: expected a non-empty JSON array of {id G<n>, claim, subjects, violation}"
    errs = lintmod.constraint_errors(lst, "G")
    if errs:
        return 1, "", "hb constraints --record: " + "; ".join(errs)
    ids = [c["id"] for c in lst]

    def _locked():
        pending, recorded, events = review_cycle(hbdir, dag, gate)
        if not pending:
            return f"hb constraints --record: {gate} is not awaiting review — record after its deterministic pass (review_pending)"
        if recorded:
            return (f"hb constraints --record: a constraint set is already recorded for {gate} in this review cycle "
                    "— it is write-once until the review verdict")
        if not actor or norm(actor) == "unknown":
            return "hb constraints --record: set HB_ACTOR to the author's identity (the author must not have done this phase's work)"
        if any(norm(d) == norm(actor) for d in phase_doers(dag, gate, events)):
            return f"hb constraints --record: '{actor}' did this phase's work — the constraint author must be a different actor"
        d = Path(hbdir) / "constraints"
        d.mkdir(parents=True, exist_ok=True)
        st.atomic_write_bytes(d / f"{gate}.json", raw)   # tmp + rename: replaces a planted symlink
        st.append_event(hbdir, {"event": "constraints_recorded", "gate": gate, "ids": ids,
                                "sha256": hashlib.sha256(raw).hexdigest(), "actor": actor, "model": model})
        st.reproject(hbdir)
        return None

    err = st.with_wlock(hbdir, _locked)
    if err:
        return 1, "", err
    return 0, f"constraints recorded for {gate}: {', '.join(ids)} (.hb/constraints/{gate}.json)", ""


def doctor_problems(hbdir):
    """Recorded gate-time constraints must still be the bytes that were recorded."""
    last = {}
    for e in st.read_events(hbdir):
        if e.get("event") == "constraints_recorded":
            last[e.get("gate")] = e
    out = []
    for g, e in last.items():
        try:
            raw = (Path(hbdir) / "constraints" / f"{g}.json").read_bytes()
        except OSError:
            out.append(f"{g} recorded constraints .hb/constraints/{g}.json are missing — the review's targets can no longer be inspected")
            continue
        if hashlib.sha256(raw).hexdigest() != e.get("sha256"):
            out.append(f"{g} recorded constraints .hb/constraints/{g}.json changed since recording (sha256 mismatch) — the review's targets were altered")
    return out
