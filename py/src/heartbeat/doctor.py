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
        elif st.substantive_len(body) < 40:
            problems.append(f"{g} review_passed but backing artifact {rel} is empty/thin — not a real refutation")

    # Restore points: every ACCEPTED gate (review gate: last review verdict is a pass; review-less:
    # a gate_passed) must have no restore failure after its last acceptance and — if its recorded
    # policy was autocommit-on — its git tag (legacy events carry neither: never flagged). The
    # acceptance-ANCHOR check applies only once anchors exist (a log that predates them has no
    # _start). Node twin: doctor() in hb.js; lines are identical.
    from . import anchors
    anchored = anchors.read_anchor(hbdir, "_start") is not None
    # acc: the gate's LAST acceptance event; rpf: a restore_point_failed that follows it.
    acc, rpf = {}, {}
    for e in st.read_events(hbdir):
        g = e.get("gate")
        ev = e.get("event")
        rev = bool((gates.get(g) or {}).get("review"))
        if (ev == "review_passed" and rev) or (ev == "gate_passed" and not rev):
            acc[g] = e
            rpf.pop(g, None)
        elif ev == "review_failed":
            acc.pop(g, None)
            rpf.pop(g, None)
        elif ev == "restore_point_failed" and g in acc:
            rpf[g] = e
    git_ok = bool(shutil.which("git"))   # absent ⇒ tag state unknown ⇒ tag checks skipped
    for g in gates:
        e = acc.get(g)
        if not e:
            continue
        if anchored and anchors.read_anchor(hbdir, g) is None:
            problems.append(f"{g} accepted but has no acceptance anchor (.hb/anchors/{g}.json) — hb changed cannot report its phase")
        if g in rpf:
            problems.append(f"{g} accepted but its restore point failed (git {rpf[g].get('step')}) — no tag certifies the accepted state")
        elif git_ok and (e.get("git") or {}).get("autocommit") is True:
            tagged = subprocess.run(
                ["git", "-C", str(pd), "rev-parse", "-q", "--verify", f"refs/tags/{g}"],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
            if not tagged:
                problems.append(f"{g} accepted with autocommit on but has no git tag {g} — no restore point")

    from . import constraints as cons
    problems.extend(cons.doctor_problems(hbdir))

    # regate: a pending revision is a NOTE (legitimate in-flight state); the rearm evidence must
    # stay the pinned bytes; an ACCEPTED gate whose criteria were rearmed after its last provenanced
    # pass carries STALE evidence; the event log (truth) must agree with the dag marker (the
    # dag_corrupted recovery restores dag.json from backup, which can silently drop a pending
    # regate). Node twin: doctor() in hb.js.
    import hashlib
    evs_r = st.read_events(hbdir)
    for g, gv in gates.items():
        blk = st.regate_blocks(gv)
        if blk is not None:
            notes.append(f"{g} is being revised — regate pending (by {blk.get('actor', '?')}: {blk.get('reason', '')}); evaluation refuses until a DIFFERENT actor rearms")
    last_re = {}
    for e in evs_r:
        if e.get("event") == "gate_rearmed":
            last_re[e.get("gate")] = e
    for g, e in last_re.items():
        rel = e.get("artifact") or f"reviews/{g}.regate.md"
        try:
            raw = (Path(hbdir) / rel).read_bytes()
        except OSError:
            raw = None
        if raw is None: problems.append(f"{g} regate rearm artifact {rel} is missing — the rearm evidence can no longer be inspected")   # regate-guard: rearm-rot
        elif st.substantive_len(raw.decode("utf-8", errors="replace")) < 40: problems.append(f"{g} regate rearm artifact {rel} is empty/thin — not real rearm evidence")   # regate-guard: rearm-rot
        elif e.get("sha256") and hashlib.sha256(raw).hexdigest() != e["sha256"]: problems.append(f"{g} regate rearm artifact {rel} changed since recording (sha256 mismatch) — the rearm evidence was altered")   # regate-guard: rearm-rot
    for g in last_re:
        if acc.get(g) and st.stale_rearm(evs_r, g): problems.append(f"{g} accepted but its criteria were rearmed after its last provenanced pass — STALE evidence: re-run the gate (hb gate {g})")   # regate-guard: stale-accepted
    unanswered = {}
    for e in evs_r:
        if e.get("event") == "gate_regated":
            unanswered[e.get("gate")] = True
        elif e.get("event") == "gate_rearmed":
            unanswered.pop(e.get("gate"), None)
    for g in unanswered:
        if st.regate_blocks(gates.get(g)) is None: problems.append(f"{g}: the event log attests a pending regate (gate_regated unanswered by any gate_rearmed) but dag.json carries " + ("a CLEARED marker (pending edited by hand?)" if "regate" in (gates.get(g) or {}) else "no regate marker (restored from backup?)") + " — re-declare and rearm properly, or investigate (the log is truth)")   # regate-guard: marker-sync
    for g, gv in gates.items():
        rmk = (gv or {}).get("regate")
        if isinstance(rmk, dict) and rmk.get("pending") is False:
            e_pin = last_re.get(g)
            if not e_pin or ((rmk.get("rearm") or {}).get("sha256") and e_pin.get("sha256") and rmk["rearm"]["sha256"] != e_pin["sha256"]): problems.append(f"{g}: the dag records a rearmed regate but the event log " + ("pins different bytes (sha256 mismatch with gate_rearmed)" if e_pin else "has no gate_rearmed event") + " — a fabricated rearm record (the log is truth)")   # regate-guard: marker-sync

    # detach: a retracted dependency claim is a legitimate in-flight state — NOTES, never problems;
    # the log is still truth in both divergence directions. Node twin: doctor() in hb.js.
    from . import anchors as _anch
    live_d = {}
    for e in evs_r:
        if e.get("event") == "phase_detached":
            live_d[e.get("phase")] = True
        elif e.get("event") == "phase_reattached":
            live_d[e.get("phase")] = False
    for p in phases:
        has_f = "detached_from" in p
        if has_f and not p.get("gate_entry"): notes.append(f"{p['id']} is detached from {p['detached_from']} (by {p.get('detached_by', '?')}: {p.get('detached_reason', '')}) — the dependency claim is retracted; re-audit before relying on the order" + ("" if (_anch.read_anchor(hbdir, f"_detach_{p['id']}") or {}).get("detached_at") == p.get("detached_at") else " (no detach anchor — change reports widen to _start)"))   # detach-guard: doctor — the suffix fires on a MISSING or STAMP-MISMATCHED anchor (changed()'s predicate; a silent widening was a refuter catch)
        if has_f and live_d.get(p.get("id")) is not True: notes.append(f"{p['id']} carries detach fields but the log attests no live detach (no phase_detached, or the last one answered by phase_reattached) — a hand edit or a restored dag: the phase runs UNLOCKED on an unattested claim")   # detach-guard: doctor
        if not has_f and live_d.get(p.get("id")) is True: notes.append(f"{p['id']}: the log attests an unanswered phase_detached but the dag carries no detach fields — a restored dag silently RE-LOCKED the phase (re-lock)")   # detach-guard: doctor

    return {"problems": problems, "notes": notes}


def has_rot(hbdir):
    return any("no longer reproducible" in p for p in doctor(hbdir)["problems"])


def diagnose(hbdir, reason=None):
    dag = st.read_dag(hbdir)
    events = st.read_events(hbdir)
    state = st.project(events, dag)
    pd = _project_dir(hbdir)
    out = []

    # A pending regate on a gate outranks the generic branch ABOUT THAT GATE: the generic recovery
    # commands (re-run gate.sh, spawn the refuter) are exactly what the perimeter refuses.
    regated = [g for g, gv in (dag.get("gates") or {}).items() if st.regate_blocks(gv) is not None]

    def regate_recovery(g):
        blk = st.regate_blocks((dag.get("gates") or {}).get(g)) or {}
        out.append(f"  Gate: {g} — being revised (regate pending, by {blk.get('actor', '?')}: {blk.get('reason', '')})")
        out.append("  Recover:")
        out.append("   1. Edit the revised criteria in .hb/dag.json (if not already done).")
        out.append("   2. Re-audit: hb audit")
        out.append(f"   3. A DIFFERENT actor rearms: hb regate {g} --rearm --artifact <findings-file>")
        out.append(f"   4. Re-run the gate: hb gate {g} — a fresh pass is owed before any review verdict.")

    if not reason:
        if state["gate"]["errors"] > 0:
            reason = "gate_blocked"
        elif has_rot(hbdir):
            reason = "gate_rot"
        elif state["pending_reviews"]:
            reason = "review_stuck"
        elif state["build_stuck_count"] >= 5:
            reason = "build_stuck"
        elif regated:
            reason = "regate_pending"
        else:
            r = rv.resolve(state, dag, hbdir)
            if r and r.get("type") == "deadlock":
                reason = "deadlock"

    out.append(f"Diagnosis: {reason or 'no blocker detected'}")
    if not reason:
        out.append("  Not currently blocked. Run: hb state")
        return "\n".join(out)

    if reason == "regate_pending":
        for g in (regated or ["(none found — pass the gate id)"]):
            regate_recovery(g)
    elif reason == "gate_blocked":
        g, rf = None, None
        for ev in reversed(events):
            if ev.get("event") in ("gate_failed", "gate_passed", "review_failed"):
                g = ev.get("gate")
                rf = ev if ev.get("event") == "review_failed" else None
                break
        if not g:
            ph = next((p for p in (dag.get("phases") or []) if p["id"] not in state["completed_phases"]), None)
            g = ph and ph.get("gate_exit")
        if g and st.regate_blocks((dag.get("gates") or {}).get(g)) is not None:
            regate_recovery(g)
            return "\n".join(out)
        out.append(f"  Gate: {g}")
        if rf:   # the criteria passed; the adversarial review did not
            note = " ".join(str(rf.get("note") or "(none recorded)").split())[:600]
            out.append("  Cause: review_failed — the criteria pass; the review refuted the phase (or could not run).")
            out.append(f"  Findings: {note}")
            out.append("  Recover: a refutation → fix the CODE for the hole it names (never weaken the gate or the "
                       f"review); a review that could not run → fix the refuter backend. Then hb gate {g} — a pass "
                       "owes the review again.")
            return "\n".join(out)
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
        if g and st.regate_blocks((dag.get("gates") or {}).get(g)) is not None:
            regate_recovery(g)
            return "\n".join(out)
        if g and st.stale_rearm(events, g):
            out.append(f"  Gate awaiting review: {g} — revised and re-armed, but its last provenanced pass predates the rearm (stale evidence).")
            out.append(f"  Recover: re-run the revised gate first — hb gate {g}; verdicts are refused until a fresh pass.")
            return "\n".join(out)
        out.append(f"  Gate awaiting review: {g}")
        out.append(f"  Recover: spawn a refuter, then: hb review {g} pass|fail \"<findings>\".")
    else:
        out.append("  (no structured diagnosis for this reason — see: hb protocol " + reason + ")")
    return "\n".join(out)
