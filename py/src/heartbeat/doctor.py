"""Integrity check (rot detection) + computed root-cause diagnosis. Ported from hb.js."""
import os
import shutil
import subprocess
from pathlib import Path

from . import state as st
from . import lint as lintmod
from . import resolver as rv
from . import gate as gatemod


def _project_dir(hbdir):
    return str(Path(hbdir).parent)


def doctor(hbdir):
    dag = st.read_dag(hbdir)
    state = st.project(st.read_events(hbdir), dag)
    gates = dag.get("gates") or {}
    phases = dag.get("phases") or []
    completed = set(state["completed_phases"])
    pd = _project_dir(hbdir)
    problems, notes = [], []

    gate_to_phase = {p["gate_exit"]: p["id"] for p in phases if p.get("gate_exit")}
    for g, gv in gates.items():
        phase_id = gate_to_phase.get(g)
        is_done = phase_id in completed if phase_id else False
        for c in (gv.get("criteria") or []):
            for rel in lintmod.extract_paths(c.get("cmd", "")):
                if (Path(pd) / rel.rstrip("/")).exists():
                    continue
                if is_done:
                    problems.append(f"{g} [{c.get('id')}] → missing {rel} (phase {phase_id} DONE — gate no longer reproducible)")
                else:
                    notes.append(f"{g} [{c.get('id')}] → missing {rel} (phase {phase_id or '?'} not built yet)")

    for e in lintmod.lint(dag)["errors"]:
        problems.append(f"dag: {e}")

    on_disk = st.read_state(hbdir)
    if on_disk:
        k = lambda s: sorted(s or [])
        if k(on_disk.get("completed_tasks")) != k(state["completed_tasks"]) or \
           k(on_disk.get("completed_phases")) != k(state["completed_phases"]):
            notes.append("state.json differs from the event-log projection — run: hb rebuild")

    # Sev-1: every review_passed must remain backed by a readable, substantive artifact.
    passed_rev = {}
    for e in st.read_events(hbdir):
        if e.get("event") == "review_passed":
            passed_rev[e.get("gate")] = e
        elif e.get("event") == "review_failed":
            passed_rev.pop(e.get("gate"), None)
    for g, e in passed_rev.items():
        rel = e.get("artifact") or f"reviews/{g}.md"
        try:
            body = (Path(hbdir) / rel).read_text()
        except OSError:
            body = None
        if body is None:
            problems.append(f"{g} review_passed but backing artifact {rel} is missing — the refutation can no longer be inspected (Sev-1 rot)")
        elif len(body.strip()) < 40:
            problems.append(f"{g} review_passed but backing artifact {rel} is empty/thin — not a real refutation")

    # Restore points (only once anchors exist — a log that predates them has no _start, never
    # flagged): every ACCEPTED gate (review gate: last review verdict is a pass; review-less: a
    # gate_passed) must have its acceptance anchor, and — if its recorded policy was autocommit-on
    # — its git tag. Node twin: doctor() in hb.js; lines are identical.
    from . import anchors
    if anchors.read_anchor(hbdir, "_start") is not None:
        acc = {}
        for e in st.read_events(hbdir):
            g = e.get("gate")
            rev = bool((gates.get(g) or {}).get("review"))
            if e.get("event") == "review_passed" and rev:
                acc[g] = e
            elif e.get("event") == "review_failed":
                acc.pop(g, None)
            elif e.get("event") == "gate_passed" and not rev and g not in acc:
                acc[g] = e
        for g in gates:
            e = acc.get(g)
            if not e:
                continue
            if anchors.read_anchor(hbdir, g) is None:
                problems.append(f"{g} accepted but has no acceptance anchor (.hb/anchors/{g}.json) — hb changed cannot report its phase")
            if (e.get("git") or {}).get("autocommit") is True:
                tagged = shutil.which("git") and subprocess.run(
                    ["git", "-C", str(pd), "rev-parse", "-q", "--verify", f"refs/tags/{g}"],
                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
                if not tagged:
                    problems.append(f"{g} accepted with autocommit on but has no git tag {g} — no restore point")

    return {"problems": problems, "notes": notes}


def has_rot(hbdir):
    return any("no longer reproducible" in p for p in doctor(hbdir)["problems"])


def diagnose(hbdir, reason=None):
    dag = st.read_dag(hbdir)
    events = st.read_events(hbdir)
    state = st.project(events, dag)
    pd = _project_dir(hbdir)
    out = []

    if not reason:
        if state["gate"]["errors"] > 0:
            reason = "gate_blocked"
        elif has_rot(hbdir):
            reason = "gate_rot"
        elif state["pending_reviews"]:
            reason = "review_stuck"
        elif state["build_stuck_count"] >= 5:
            reason = "build_stuck"
        else:
            r = rv.resolve(state, dag, hbdir)
            if r and r.get("type") == "deadlock":
                reason = "deadlock"

    out.append(f"Diagnosis: {reason or 'no blocker detected'}")
    if not reason:
        out.append("  Not currently blocked. Run: hb state")
        return "\n".join(out)

    if reason == "gate_blocked":
        g = None
        for ev in reversed(events):
            if ev.get("event") in ("gate_failed", "gate_passed"):
                g = ev.get("gate")
                break
        if not g:
            ph = next((p for p in (dag.get("phases") or []) if p["id"] not in state["completed_phases"]), None)
            g = ph and ph.get("gate_exit")
        out.append(f"  Gate: {g}")
        res = gatemod.eval_gate(hbdir, g) if g else None
        for ln in (res["lines"] if res else []):
            if "✗" in ln:
                out.append("   " + ln.strip())
        n = sum(1 for e in events if e.get("event") == "gate_failed" and e.get("gate") == g)
        out.append(f"  Attempts: this gate has failed {n}× (build_stuck at 5).")
        out.append("  Recover: root-cause each ✗ — fix the CODE, not the test. Do NOT weaken a criterion.")
    elif reason == "gate_rot":
        out.append("  Observe: a completed phase's gate references a file that no longer exists.")
        for pr in [p for p in doctor(hbdir)["problems"] if "no longer reproducible" in p]:
            out.append("   " + pr)
            rel = pr.split("missing ", 1)[1].split(" ", 1)[0] if "missing " in pr else None
            if rel:
                deleted = subprocess.run(["git", "-C", pd, "log", "--diff-filter=D", "--oneline", "-1", "--", rel],
                                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.decode().strip()
                if deleted:
                    out.append(f"     traced: deleted in {deleted}")
        out.append("  Recover: restore the file (git checkout <commit>^ -- <file>) or re-point the gate.")
    elif reason == "deadlock":
        r = rv.resolve(state, dag, hbdir) or {}
        out.append(f"  Cause: {r.get('cause', 'unknown')}")
        out.append("  Recover: " + ("free the orphan IDs (hb fail <id>)" if r.get("cause") == "active_orphan"
                                     else "fix the DAG and re-lint (hb lint)"))
    elif reason == "build_stuck":
        out.append(f"  build_stuck_count={state['build_stuck_count']}. Read events.jsonl — are you repeating a fix?")
        out.append("  Recover: produce a blocker report and surface for a human.")
    elif reason == "review_stuck":
        g = (state["pending_reviews"] or [None])[0]
        out.append(f"  Gate awaiting review: {g}")
        out.append(f"  Recover: spawn a refuter, then: hb review {g} pass|fail \"<findings>\".")
    else:
        out.append("  (no structured diagnosis for this reason — see: hb protocol " + reason + ")")
    return "\n".join(out)
