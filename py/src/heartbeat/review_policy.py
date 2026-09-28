"""review_policy — the one place the adversarial-review acceptance rules live.

A review pass is security-sensitive: it must be backed by a substantive,
phase-citing artifact written by a **different actor** than the one who did the
work. Historically this logic lived only inside `cli.py`'s `review` subcommand,
so the executor and the MCP server had to *re-enter* `cli.main([...])` and scrape
stdout to reuse it. That indirection meant a caller could drift from the CLI's
policy without any test noticing. This module is the single source of truth;
`cli.py`, `executor.py`, and `mcp_server.py` all delegate here.

`accept_review` returns `(rc, out, err)` — the caller decides where to route the
strings (CLI → stdout/stderr, MCP → JSON). `rc == 0` means the review was
recorded (a pass wrote `reviews/<gate>.md` and took the phase's restore point).
"""
from __future__ import annotations

import os
import re
from pathlib import Path

from . import state as st
from . import lint as lintmod


def accept_review(hb, gate, verdict, artifact=None, note=None, model=None):
    """Record an adversarial-review verdict. Returns (rc, out, err).

    hb       — the project's .hb directory (str or Path)
    gate     — gate id under review
    verdict  — "pass" or "fail"
    artifact — path to the refuter's written attempt (required for a pass)
    note     — optional note (str or list of tokens)
    model    — the model that reviewed, recorded on the event (null when unknown — honest,
               never fabricated). The exec path auto-stamps the resolved profile model
               (config-derived); an interactive/MCP value is the recorder's self-report.
    """
    hb = str(hb)
    note_str = (" ".join(note) if isinstance(note, list) else note) or None
    vw = "review free" if verdict == "free" else "review pass"

    if verdict == "fail":
        ev = {"event": "review_failed", "gate": gate, "model": model}
        if note_str:
            ev["note"] = note_str
        st.mutate(hb, ev)
        return 0, f"review fail {gate}", ""

    # pass (or free) — must be backed by a substantive, phase-citing artifact from a distinct actor
    if not artifact:
        if verdict == "free":
            return 1, "", "review free requires --artifact <findings-file>: the free reviewer's written breadth review."
        return 1, "", ("review pass requires --artifact <findings-file>: the refuter's written "
                       "attempt (a pass must cite evidence, not just assert one).")
    project_dir = Path(hb).parent
    ap = Path(artifact) if os.path.isabs(artifact) else project_dir / artifact
    try:
        body = ap.read_bytes().decode("utf-8", errors="replace")   # no universal-newline translation (== node)
    except OSError as e:
        return 1, "", f"{vw}: cannot read artifact {artifact} ({e})"
    if len(body.strip()) < 40:
        return 1, "", (f"{vw}: artifact {artifact} is too thin ({len(body.strip())} chars) "
                       "to be a real refutation — a rubber-stamp is not a review.")
    dag = st.read_dag(hb)
    phase = next((p for p in (dag.get("phases") or []) if p.get("gate_exit") == gate), None)
    anchors = {gate}
    if phase:
        anchors.add(phase["id"])
        anchors.update(t["id"] for t in (phase.get("tasks") or []))
    for c in ((dag.get("gates") or {}).get(gate, {}).get("criteria") or []):
        for pth in lintmod.extract_paths(c.get("cmd", "")):
            anchors.add(pth)
            anchors.add(pth.split("/")[-1])
    hay = body.lower()
    cited = [a for a in anchors if a and len(str(a)) > 1 and str(a).lower() in hay]
    if not cited:
        usable = ", ".join(a for a in anchors if a and len(str(a)) > 1)
        return 1, "", (f"{vw}: artifact {artifact} does not reference the phase under review "
                       f"(it cites nothing real; expected one of: {usable}).")
    reviewer = os.environ.get("HB_ACTOR", "unknown")
    if reviewer != "unknown" and phase:
        phase_task_ids = {t["id"] for t in (phase.get("tasks") or [])}
        doers = {e.get("actor") for e in st.read_events(hb)
                 if e.get("event") == "task_done" and e.get("task") in phase_task_ids
                 and e.get("actor") and e.get("actor") != "unknown"}
        if any(str(d).strip().lower() == str(reviewer).strip().lower() for d in doers):
            return 1, "", (f"{vw}: reviewer '{reviewer}' also executed this phase's work — "
                           "a self-review is not adversarial (set a different HB_ACTOR).")
    # ── constraint-first review (a CONSTRAINED gate only; an unconstrained gate is unchanged) ──
    from . import constraints as cons
    import hashlib
    norm = lambda a: str(a).strip().lower()  # noqa: E731
    constrained = bool(cons.plan_constraints(dag, gate))
    answers = constraint_ids = None
    if verdict == "free":
        if not constrained:
            return 1, "", (f"review free: {gate} has no plan-time constraints — the free review belongs to the "
                           "constraint-first review of a constrained gate")
        pending, _rec, events, _start = cons.review_cycle_full(hb, dag, gate)
        if not pending:
            return 1, "", f"review free: {gate} is not awaiting review"
        if not reviewer or not norm(reviewer) or norm(reviewer) == "unknown":
            return 1, "", "review free: set HB_ACTOR to the free reviewer's identity"
        if any(norm(d) == norm(reviewer) for d in cons.phase_doers(dag, gate, events)):
            return 1, "", f"review free: '{reviewer}' did this phase's work — the free reviewer must be a different actor"
        rd = Path(hb) / "reviews"
        rd.mkdir(parents=True, exist_ok=True)
        (rd / f"{gate}.free.md").write_text(body)
        st.mutate(hb, {"event": "free_review_recorded", "gate": gate, "actor": reviewer, "model": model,
                       "artifact": f"reviews/{gate}.free.md", "sha256": hashlib.sha256(body.encode()).hexdigest()})
        return 0, f"review free {gate} recorded (reviews/{gate}.free.md, by {reviewer})", ""
    if constrained:
        pending, recorded, events, start = cons.review_cycle_full(hb, dag, gate)
        if not recorded:
            return 1, "", (f"review pass refused on {gate}: no gate-time constraints were recorded in this review cycle — "
                           f"run hb constraints {gate} --prompt, have a non-doer author them, then hb constraints {gate} --record <file.json>")
        try:
            gset = cons.recorded_constraints(hb, dag, gate)
        except ValueError as e:
            return 1, "", f"review pass refused on {gate}: {e}"
        constraint_ids = [c.get("id") for c in cons.plan_constraints(dag, gate)] + [c.get("id") for c in gset]
        errs, counts = check_answers(body, constraint_ids)
        if errs:
            return 1, "", f"review pass refused on {gate}: " + "; ".join(errs)
        answers = counts
        from . import refuter_profiles as rprof
        try:
            prof = rprof.gate_profile(hb, ((dag.get("gates") or {}).get(gate) or {}).get("review") or {})
        except Exception as e:  # noqa: BLE001 — unknown profile: fail closed
            return 1, "", f"review pass refused on {gate}: {e}"
        if prof and prof.get("free_review"):
            ok = any(i > start and e.get("event") == "free_review_recorded" and e.get("gate") == gate
                     and norm(e.get("actor") or "") != norm(reviewer) for i, e in enumerate(events))
            if not ok:
                return 1, "", (f"review pass refused on {gate}: the profile requires a free review — record one in this review "
                               f"cycle from an actor other than '{reviewer}': hb review {gate} free --artifact <file>")
    revdir = Path(hb) / "reviews"
    revdir.mkdir(parents=True, exist_ok=True)
    (revdir / f"{gate}.md").write_text(body)
    from . import gate as _g
    ev = {"event": "review_passed", "gate": gate, "model": model, "artifact": f"reviews/{gate}.md",
          "artifact_chars": len(body.strip()), "cited": cited, "reviewer": reviewer,
          "git": {"autocommit": _g.git_policy(hb)}}
    if answers is not None:
        ev["answers"] = answers
        ev["constraint_ids"] = constraint_ids
        ev["artifact_sha256"] = hashlib.sha256(body.encode("utf-8")).hexdigest()
    if note_str:
        ev["note"] = note_str
    st.mutate(hb, ev)
    # Reviewed acceptance is what creates the phase's restore point (commit+tag) — the
    # deterministic pass deferred it so the tag only ever certifies a reviewed-good state.
    from . import gate as _gate
    _gate._git_snapshot(hb, gate)
    from . import anchors
    anchors.try_anchor(hb, gate)   # acceptance anchor — after the restore point, so its commit is the accepted HEAD
    return 0, (f"review pass {gate} (backed by reviews/{gate}.md, {len(body.strip())} chars, "
               f"cites: {', '.join(cited[:3])})"), ""


# EXPLICIT rules, identical to hb.js checkAnswers (see there): every line break, invisible characters
# removed, ASCII-only case folding (re.A), and an answer-SHAPED line not in the format is refused.
_ANSWER_BREAKS = re.compile(r"\r\n|[\n\r\v\f\x1c\x1d\x1e\x85\u2028\u2029]")
_ANSWER_INVISIBLE = re.compile(r"[\u200b-\u200f\u2060\ufeff\u00ad]")
_ANSWER_HEAD = re.compile(r"^([PG][0-9]+)[ \t]*[:：]", re.I | re.A)
_ANSWER_RE = re.compile(r"^[PG][0-9]+[ \t]*[:：][ \t]*(VIOLATED|NOT-REPRODUCED|NOT REPRODUCED|N/A)(?![A-Za-z0-9])(.*)$", re.I | re.A)


def check_answers(body, required):
    """The refuter's per-id answers (constraint-first review) — twin of hb.js checkAnswers, messages
    verbatim, EXPLICIT rules (see there). Returns (errors, counts)."""
    from .refuter_profiles import ANSWER_FORMAT
    req, seen, errors = set(required), {}, []
    counts = {"violated": 0, "not_reproduced": 0, "na": 0}
    text = re.sub(r"<!--.*?-->", "", str(body), flags=re.S)   # an HTML comment hides nothing
    for raw in _ANSWER_BREAKS.split(text):
        l = re.sub(r"^[\t >+#-]+", "", re.sub(r"[*`_]", "", _ANSWER_INVISIBLE.sub("", raw)).strip(" \t"))
        # match on an ASCII-only lowercased copy: no regex case folding (JS and python fold differently)
        lo = "".join(c.lower() if "A" <= c <= "Z" else c for c in l)
        head = re.match(r"^([pg][0-9]+)[ \t]*[:：]", lo)
        if not head:
            if re.match(r"^[^ \t:：]{1,4}[ \t]*[:：][ \t]*(?:violated|not[- ]reproduced|n/a)", lo):
                errors.append(f"an answer-shaped line has an id that is not an ASCII P<n>/G<n> — answer each id exactly ({ANSWER_FORMAT})")
            continue
        cid = head.group(1).upper()
        m = re.match(r"^[pg][0-9]+[ \t]*[:：][ \t]*(violated|not-reproduced|not reproduced|n/a)(?=$|[ \t—–:])(.*)$", lo)
        if not m:
            errors.append(f"{cid} has an answer-shaped line that is not in the format ({ANSWER_FORMAT})")
            continue
        stt = m.group(1).upper().replace(" ", "-", 1)
        rest = re.sub(r"^[ \t]*[—–:-]+", "", m.group(2))
        if cid not in req:
            errors.append(f"{cid} is not a constraint of this gate (an unknown id was answered)")
            continue
        if cid in seen:
            errors.append(f"{cid} is answered twice — one line per id")
            continue
        seen[cid] = stt
        if stt == "VIOLATED":
            counts["violated"] += 1
            errors.append(f'{cid} is answered VIOLATED — a violation is a finding: record it with hb review <gate> fail "<finding>"')
        elif not _ANSWER_TEXT.search(rest):
            errors.append(f"{cid} is answered {stt} without " + ("a reason" if stt == "N/A" else "evidence (the probe you ran)"))
        elif stt == "N/A":
            counts["na"] += 1
        else:
            counts["not_reproduced"] += 1
    for cid in required:
        if cid not in seen:
            errors.append(f"{cid} has no answer line ({ANSWER_FORMAT})")
    return errors, counts


# evidence / a reason must contain a character that is not whitespace (== node ANSWER_TEXT)
_ANSWER_TEXT = re.compile(r"[^ \t   -   　]")
