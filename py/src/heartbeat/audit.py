"""Adversarial DAG reviewer — deterministic gate-quality audit.

Where lint checks structure, audit checks whether gates actually PROVE their phase's
work. Ruleset is shared verbatim with the node hb-audit.js (see planning/parity-notes.md);
keep the two in lockstep so the parity test stays meaningful.
"""
import re

from . import lint as lintmod

VACUOUS = re.compile(r"^\s*(true|:|exit\s+0|echo\b|test\s+1\s*=\s*1|\[\s+1\s+=\s+1\s+\])\s*;?\s*$")
EXISTENCE = re.compile(r"^\s*(test\s+-[efds]\b|\[\s+-[efds]\b|ls(\s|$))")
# Sources that can change a VERDICT between runs (network, time, randomness). `mktemp` is deliberately
# not listed (== node): it randomises a NAME, and isolating a check in a fresh temp dir keeps a gate
# deterministic — a verdict that compares against the random name is left to the refuter's review.
NONDET = re.compile(r"\bcurl\b|\bwget\b|\bnc\b|\bping\b|\bsleep\b|\bRANDOM\b|\bshuf\b|/dev/urandom|\bSECONDS\b|\$\$|\bdate\b|https?://(?!localhost|127\.0\.0\.1)")
# A criterion that CREATES evidence can fabricate its own pass — a gate must observe,
# not produce. Read-only redirections (/dev/null, /tmp scratch, 2>&1) are exempt, and so is
# `=>` (a JS arrow in an inline `node -e`).
SIDE_EFFECT = re.compile(r"(^|[^0-9>=])>{1,2}\s*(?!/dev/null|/tmp|&\s*[12])|\btee\b|\bcp\b|\bmv\b|\bmkdir\b|\btouch\b|\bdd\b|\bsed\s+-i\b|\binstall\s+-D\b")


def classify(cmd):
    c = (cmd or "").strip()
    if VACUOUS.match(c):
        return "vacuous"
    if EXISTENCE.match(c):
        return "existence"
    return "behavioral"


def is_nondet(cmd):
    return bool(NONDET.search(cmd or ""))


def is_side_effecting(cmd):
    return bool(SIDE_EFFECT.search(cmd or ""))


# A `grep` that keys on a test-suite marker (a coverage gate) vs a grep of a source string.
COVERAGE = re.compile(r"\bgrep\b[^|]*(GROUPS-PASSED|\bT[0-9]+\b|[A-Z][A-Z0-9-]*-OK)")


def criterion_question(c):
    """From a criterion's CLASS, a 'how could this FALSELY pass?' question (byte-identical to node)."""
    cmd = (c.get("cmd") or "").strip()
    cid = c.get("id") or "?"
    cls = classify(cmd)
    if cls == "vacuous":
        return f"{cid}: looks trivially true — does it assert anything about the phase's real work, or would it pass on ANY code?"
    if cls == "existence":
        return f"{cid}: checks a path's PRESENCE — does existence prove the behaviour, or could an empty / placeholder / wrong file pass it?"
    if is_side_effecting(cmd):
        return f"{cid}: WRITES/creates files — could it fabricate its own evidence? A gate must OBSERVE reality, not produce it."
    if COVERAGE.search(cmd):
        return f"{cid}: keys on a suite marker — does it assert the group actually PASSED (zero failures), or could it match a header printed before a RED RUN failed?"
    if re.search(r"\bgrep\b", cmd):
        return f"{cid}: greps for a string in source — could it pass on a hollow STUB that merely contains the string? Verify the code is EXECUTED, not just matched."
    if is_nondet(cmd):
        return f"{cid}: touches time/network/randomness — could it pass or fail by luck rather than by the behaviour?"
    return f"{cid}: runs code — does the assertion pin the REAL required behaviour, or a weak PROXY that a TRIVIAL stub could satisfy?"


def review_questions(dag, gate):
    """The falsification checklist for a gate — the deterministic seed for the adversarial review."""
    g = ((dag or {}).get("gates") or {}).get(gate)
    if not g:
        return f"no gate '{gate}' in this DAG\n"
    lines = [f"Falsification checklist for {gate} — for each criterion, how could it FALSELY pass?"]
    for c in (g.get("criteria") or []):
        lines.append(f"  - {criterion_question(c)}")
    lines.append(f'  - PHASE CLAIM: "{g.get("desc") or gate}". Could every criterion above pass while this is still broken? Is any criterion testing the WRONG behaviour? Is the REAL runtime exercised (not mocked/stubbed)?')
    return "\n".join(lines) + "\n"


def audit(dag):
    findings = []
    phases = dag.get("phases") or []
    gates = dag.get("gates") or {}
    parked = []

    def F(sev, rule, phase, message, **extra):
        findings.append({"severity": sev, "rule": rule, "phase": phase, "message": message, **extra})

    for p in phases:
        if p.get("parked"):
            # A parked phase is out of the plan's live surface — its gate is not audited (an
            # unsound-but-parked gate must not block audit-clean). The skip is returned in
            # "parked" so callers report it; unpark re-audits (rule: audit-clean before run).
            parked.append(p["id"])
            continue
        tasks = p.get("tasks") or []
        if tasks and not p.get("gate_exit"):
            F("warn", "unguarded_phase", p["id"], f"phase {p['id']} has tasks but no gate_exit — its work is never verified")
            continue
        if not p.get("gate_exit"):
            continue
        crit = (gates.get(p["gate_exit"]) or {}).get("criteria") or []
        if not crit:
            F("error", "ungated", p["id"], f"gate {p['gate_exit']} has no criteria — phase {p['id']} is not verified", gate=p["gate_exit"])
            continue
        behavioral = 0
        for c in crit:
            cls = classify(c.get("cmd"))
            if cls == "behavioral":
                behavioral += 1
            else:
                what = "trivially true" if cls == "vacuous" else "an existence-only check"
                tail = "nothing" if cls == "vacuous" else "mere existence"
                F("info", cls, p["id"], f"{p['gate_exit']}[{c.get('id')}] is {what} — assert behaviour, not {tail}",
                  gate=p["gate_exit"], criterion=c.get("id"))
            if is_nondet(c.get("cmd")):
                F("warn", "nondeterministic", p["id"],
                  f"{p['gate_exit']}[{c.get('id')}] touches network/time — may flake; gates must be deterministic",
                  gate=p["gate_exit"], criterion=c.get("id"))
            if is_side_effecting(c.get("cmd")):
                F("warn", "side_effecting", p["id"],
                  f"{p['gate_exit']}[{c.get('id')}] writes/creates files — a gate must OBSERVE, not PRODUCE its evidence (self-fabricated pass)",
                  gate=p["gate_exit"], criterion=c.get("id"))
            if any("\x1e" in (c.get(k) or "") or "\x1f" in (c.get(k) or "") for k in ("cmd", "desc")):
                F("error", "control_char", p["id"],
                  f"{p['gate_exit']}[{c.get('id')}] cmd/desc contains a \\x1e/\\x1f control byte — it would corrupt the gate runner's record transport; remove it",
                  gate=p["gate_exit"], criterion=c.get("id"))
        if behavioral == 0:
            F("error", "hollow_gate", p["id"],
              f"gate {p['gate_exit']} has NO behavioural criterion — phase {p['id']} passes without proving its work",
              gate=p["gate_exit"])
        # "Has a review" = the review value is a dict (node: a non-array object); any other shape is
        # a lint error, never a crash here.
        rv = (gates.get(p["gate_exit"]) or {}).get("review")
        if isinstance(rv, dict) and not (isinstance(rv.get("constraints"), list) and rv["constraints"]):
            F("warn", "unconstrained_review", p["id"],
              f"gate {p['gate_exit']} has an adversarial review but no plan-time constraints — the refuter's target is implicit (add review.constraints)",
              gate=p["gate_exit"])

        task_text = " ".join(f"{t.get('title', '')} {t.get('description', '')}" for t in tasks).lower()
        paths = set()
        for c in crit:
            for pth in lintmod.extract_paths(c.get("cmd", "")):
                paths.add(pth)
        if paths and not any(pth.lower() in task_text or pth.rstrip("/").split("/")[-1].lower() in task_text for pth in paths):
            F("warn", "gate_offphase", p["id"],
              f"gate {p['gate_exit']} references files no task in {p['id']} mentions — it may not be testing this phase's work",
              gate=p["gate_exit"])

    return {"findings": findings,
            "errors": sum(1 for f in findings if f["severity"] == "error"),
            "warns": sum(1 for f in findings if f["severity"] == "warn"),
            "parked": parked}
