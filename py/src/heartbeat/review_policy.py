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
        (rd / f"{gate}.free.md").write_text(body, encoding="utf-8")
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
    (revdir / f"{gate}.md").write_text(body, encoding="utf-8")
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


# EXPLICIT rules, identical to hb.js checkAnswers (see there): 1. THE WORD — the whole artifact
# normalised (NFKC, entities, <br>, tags and comment markers, escape/control/invisible characters,
# confusables) and any line whose squashed letters contain "violated" refuses the pass, evidence
# included; 2. THE ANSWERS parsed strictly from the visible text.
_ANSWER_BREAKS = re.compile(r"\r\n|[\n\r\v\f\x1c\x1d\x1e\x85\u2028\u2029]")
_ANSWER_INVISIBLE = re.compile(r"[​-‏⁠-⁤﻿­᠎͏؜]")
_ANSWER_ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[@-_]")
_ANSWER_CTRL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")
_ANSWER_TEXT = re.compile(r"[^ \t   -   　⠀ㅤﾠᅟᅠ]")
_ANSWER_CONFUSABLES = {"\u0410": "a", "\u0412": "b", "\u0415": "e", "\u041a": "k", "\u041c": "m", "\u041d": "h", "\u041e": "o", "\u0420": "p", "\u0421": "c", "\u0422": "t", "\u0425": "x", "\u0430": "a", "\u0435": "e", "\u043e": "o", "\u0440": "p", "\u0441": "c", "\u0443": "y", "\u0445": "x", "\u0456": "i", "\u0458": "j", "\u0455": "s", "\u0501": "d", "\u0406": "i", "\u0408": "j", "\u0405": "s", "\u04cf": "l", "\u0500": "d", "\u04ae": "y", "\u04af": "y", "\u04c0": "l", "\u051b": "q", "\u051d": "w", "\u0391": "a", "\u0392": "b", "\u0395": "e", "\u0396": "z", "\u0397": "h", "\u0399": "i", "\u039a": "k", "\u039c": "m", "\u039d": "n", "\u039f": "o", "\u03a1": "p", "\u03a4": "t", "\u03a5": "y", "\u03a7": "x", "\u03bf": "o", "\u03bd": "v", "\u03b9": "i", "\u03b1": "a", "\u03ba": "k", "\u03c1": "p", "\u03c4": "t", "\u03c5": "u", "\u0131": "i", "\u017f": "s", "\u2113": "l", "\u01c0": "l", "\u0251": "a", "\u0261": "g", "\u1d20": "v", "\u1d05": "d", "\u1d07": "e", "\u1d1b": "t", "\u1d0f": "o", "\u1d00": "a", "\u0299": "b", "\u1d04": "c", "\ua730": "f", "\u0262": "g", "\u029c": "h", "\u026a": "i", "\u1d0a": "j", "\u1d0b": "k", "\u029f": "l", "\u1d0d": "m", "\u0274": "n", "\u1d18": "p", "\u01eb": "q", "\u0280": "r", "\ua731": "s", "\u1d1c": "u", "\u1d21": "w", "\u028f": "y", "\u1d22": "z", "\u0585": "o", "\u057d": "u", "\u0581": "g", "\u0570": "h", "\u0578": "n", "\u0561": "w", "\u0565": "e", "\u056b": "h", "\u056c": "l", "\u057c": "n"}
_ANSWER_ENTITIES = {"amp": "&", "lt": "<", "gt": ">", "quot": '"', "apos": "'", "nbsp": " "}


# NO platform normalisation (== node; unicodedata / ICU versions differ): explicit full-width fold, and
# STYLED letters (fixed ranges) refused outright.
_ANSWER_STYLED = re.compile("[\u2100-\u214f\u2460-\u24ff\U0001cc00-\U0001cebf\U0001d400-\U0001d7ff\U0001f100-\U0001f1ff]")


def _fold_width(t):
    return re.sub("[\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000]", " ", re.sub("[\uff01-\uff5e]", lambda m: chr(ord(m.group(0)) - 0xFEE0), t))


def _answer_text(body, comment_mode):
    t = _fold_width(str(body))

    def ent(m):
        d, h, n = m.group(1), m.group(2), m.group(3)
        if d or h:
            cp = int(d, 10) if d else int(h, 16)
            return chr(cp) if cp <= 0x10FFFF and not (0xD800 <= cp <= 0xDFFF) else ""
        return _ANSWER_ENTITIES.get(n.lower(), m.group(0))
    t = re.sub(r"&#([0-9]{1,7});|&#[xX]([0-9a-fA-F]{1,6});|&([a-zA-Z]+);", ent, t)
    t = re.sub(r"<br[ \t]*/?>", "\n", t, flags=re.I)
    # inside an inline code span a comment marker is literal text, not a comment (== node)
    t = re.sub(r"`[^`\n]*`", lambda m: m.group(0).replace("<!--", "<!- -").replace("-->", "- ->"), t)
    t = re.sub(r"<!--|-->", " ", t) if comment_mode == "keep" else re.sub(r"<!--.*?(?:-->|\Z)", "", t, flags=re.S)
    t = re.sub(r"</?[a-zA-Z][^<>]*>", "", t)
    return _fold_width(_ANSWER_INVISIBLE.sub("", _ANSWER_ANSI.sub("", t)))


def _squash_letters(s):
    out = []
    for c in s:
        f = _ANSWER_CONFUSABLES.get(c, c)
        if len(f) == 1 and ("a" <= f <= "z" or "A" <= f <= "Z"):
            out.append(f.lower())
    return "".join(out)


def check_answers(body, required):
    """The refuter's per-id answers (constraint-first review) — twin of hb.js checkAnswers, messages
    verbatim, EXPLICIT rules (see there). Returns (errors, counts)."""
    from .refuter_profiles import ANSWER_FORMAT
    req, seen, errors = set(required), {}, []
    counts = {"violated": 0, "not_reproduced": 0, "na": 0}
    if _ANSWER_STYLED.search(str(body)):
        errors.append("the artifact uses styled letters (mathematical, enclosed, letterlike or legacy-computing symbols) — write plain text")
    word_lines = sum(1 for mode in ("keep", "drop") for line in _ANSWER_BREAKS.split(_answer_text(body, mode))
                     if "violated" in _squash_letters(_ANSWER_CTRL.sub("", line)))
    loose_id = 0
    for raw in _ANSWER_BREAKS.split(_answer_text(body, "drop")):
        l = re.sub(r"[*`_]", "", _ANSWER_CTRL.sub("", raw)).strip(" \t")
        l = re.sub(r"^(?:[\t >+#-]+|[0-9]+[.)][ \t]+)+", "", l)
        lo = "".join(c.lower() if "A" <= c <= "Z" else c for c in l)   # ASCII-only: no regex case folding
        m = re.match(r"^([pg][0-9]+)[ \t]*[:：][ \t]*(violated|not-reproduced|not reproduced|n/a)(?=$|[ \t—–:,.;])(.*)$", lo)
        head = re.match(r"^([pg][0-9]+)[ \t]*[:：]", lo)
        if head and not m:
            errors.append(f"{head.group(1).upper()} has an answer-shaped line that is not a well-formed answer ({ANSWER_FORMAT})")
            continue
        if not m:
            if re.search(r"(^|[^a-z0-9])[pg][0-9]+([^0-9]|$)", lo) and re.search(r"(not[- ]?reproduced|n/a)", lo):
                loose_id += 1
            continue
        cid, stt = m.group(1).upper(), m.group(2).upper().replace(" ", "-", 1)
        rest = re.sub(r"^[ \t]*[—–:,.;-]+", "", m.group(3))
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
    if word_lines and not counts["violated"]:
        errors.append(f'the artifact uses the word "violated" outside a VIOLATED answer ({word_lines} line(s)) — the word is reserved: '
                      f'if a constraint is violated, record the finding with hb review <gate> fail "<finding>"; otherwise say what held instead')
    if loose_id:
        errors.append(f"a line names a constraint id with a status but is not a well-formed answer ({loose_id} line(s)) — "
                      f"answer each id exactly ({ANSWER_FORMAT})")
    for cid in required:
        if cid not in seen:
            errors.append(f"{cid} has no answer line ({ANSWER_FORMAT})")
    return errors, counts
