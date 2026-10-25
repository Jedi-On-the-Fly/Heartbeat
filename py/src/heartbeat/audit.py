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
    # A non-string cmd reads as "" (its shape is a lint error, never a crash here), and an EMPTY
    # cmd is VACUOUS: the runner evals '' → exit 0 → a trivial pass, so it must never count as
    # the behavioral criterion that saves a gate from hollow_gate (a refuter-era latent hole).
    c = (cmd if isinstance(cmd, str) else "").strip()
    if not c:
        return "vacuous"
    if VACUOUS.match(c):
        return "vacuous"
    if EXISTENCE.match(c):
        return "existence"
    return "behavioral"


def is_nondet(cmd):
    return bool(NONDET.search(cmd if isinstance(cmd, str) else ""))


def is_side_effecting(cmd):
    return bool(SIDE_EFFECT.search(cmd if isinstance(cmd, str) else ""))


# A `grep` that keys on a test-suite marker (a coverage gate) vs a grep of a source string.
COVERAGE = re.compile(r"\bgrep\b[^|]*(GROUPS-PASSED|\bT[0-9]+\b|[A-Z][A-Z0-9-]*-OK)")


def criterion_question(c):
    """From a criterion's CLASS, a 'how could this FALSELY pass?' question (byte-identical to node)."""
    cmd = (c.get("cmd") if isinstance(c.get("cmd"), str) else "").strip()
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
    v = lintmod.structure_view(dag) if isinstance(dag, dict) else {"gates": {}}  # malformed gates dropped (== node)
    g = v["gates"].get(gate)
    if gate not in v["gates"]:  # membership, not truthiness ({} is a gate; == node)
        return f"no gate '{gate}' in this DAG\n"
    lines = [f"Falsification checklist for {gate} — for each criterion, how could it FALSELY pass?"]
    for c in (g.get("criteria") or []):
        lines.append(f"  - {criterion_question(c if isinstance(c, dict) else {})}")
    lines.append(f'  - PHASE CLAIM: "{g["desc"] if isinstance(g.get("desc"), str) and g["desc"] else gate}". Could every criterion above pass while this is still broken? Is any criterion testing the WRONG behaviour? Is the REAL runtime exercised (not mocked/stubbed)?')
    return "\n".join(lines) + "\n"


def _gate_obj(gates, g):
    """Hostile shapes (non-dict gates map or gate value, non-list criteria, non-string gate_exit)
    read as EMPTY on both runtimes — never a crash, never a divergence (twin: hb-audit.js gateObj)."""
    gv = gates.get(g) if isinstance(g, str) else None
    return gv if isinstance(gv, dict) else {}


def _gate_id(p):
    """A non-string gate_exit is no gate (twin: hb-audit.js gateId)."""
    g = p.get("gate_exit")
    return g if isinstance(g, str) and g else None


def _phase_verified(p, gates):
    gx = _gate_id(p)
    if not gx:
        return False
    crit = _gate_obj(gates, gx).get("criteria")
    if not isinstance(crit, list) or not crit:
        return False
    return any(isinstance(c, dict) and classify(c.get("cmd")) == "behavioral" for c in crit)


def _speculative_tail(phases, gates, F):
    """speculative_tail: trailing unverified live phases behind a verified head were planned past
    the knowledge horizon. Fires once, warn — the DIAGNOSIS is the cut point (twin: hb-audit.js)."""
    live = [p for p in phases if not p.get("parked")]

    def rid(p):
        return p["id"] if isinstance(p.get("id"), str) and p["id"] else "?"
    k = 0
    while k < len(live) and not _phase_verified(live[len(live) - 1 - k], gates):
        k += 1
    if k < 2 or k == len(live):
        return
    tail = [rid(p) for p in live[len(live) - k:]]
    cut = rid(live[len(live) - k - 1])
    F("warn", "speculative_tail", tail[0],
      f"phases {', '.join(tail)} trail the plan unverified after {cut} — a speculative tail (plans past the knowledge horizon are guesses): end the plan at {cut} with \"horizon\": true and plan the tail when its spec is known (docs/howto/plan-to-the-horizon.md)",
      tail=tail, cut=cut)


def audit(dag, unreadable=None):
    """unreadable: the checked file read's error — the plan is then one dag_shape finding instead
    of a crash or an empty 'clean' audit (twin: hb-audit.js)."""
    findings = []
    parked = []

    def F(sev, rule, phase, message, **extra):
        findings.append({"severity": sev, "rule": rule, "phase": phase, "message": message, **extra})
    shape = [unreadable] if unreadable else lintmod.shape_errors(dag, True)
    if shape: F("error", "dag_shape", None, f"dag.json structure is invalid: {shape[0]} — run the lint for every error")  # shape-guard: audit
    view = lintmod.structure_view(dag) if (not unreadable and isinstance(dag, dict)) else {"phases": [], "gates": {}}
    phases = [p for p in view["phases"] if isinstance(p.get("id"), str) and p["id"]]  # an invalid-id phase is dag_shape's to report
    gates = view["gates"]

    for p in phases:
        if p.get("parked"):
            # A parked phase is out of the plan's live surface — its gate is not audited (an
            # unsound-but-parked gate must not block audit-clean). The skip is returned in
            # "parked" so callers report it; unpark re-audits (rule: audit-clean before run).
            parked.append(p["id"])
            continue
        tasks = p.get("tasks") or []
        gx = _gate_id(p)
        if tasks and not gx:
            F("warn", "unguarded_phase", p["id"], f"phase {p['id']} has tasks but no gate_exit — its work is never verified")
            continue
        if not gx:
            continue
        crit = _gate_obj(gates, gx).get("criteria")
        crit = crit if isinstance(crit, list) else []
        if not crit:
            F("error", "ungated", p["id"], f"gate {gx} has no criteria — phase {p['id']} is not verified", gate=gx)
            continue
        behavioral = 0
        for c in crit:
            if not isinstance(c, dict):
                c = {}   # a non-object entry is a lint error (criteria-shape rule); here it is simply not behavioral
            cid_s = "?" if c.get("id") is None else c.get("id")  # one rendering on both runtimes
            cls = classify(c.get("cmd"))
            if cls == "behavioral":
                behavioral += 1
            else:
                what = "trivially true" if cls == "vacuous" else "an existence-only check"
                tail = "nothing" if cls == "vacuous" else "mere existence"
                F("info", cls, p["id"], f"{gx}[{cid_s}] is {what} — assert behaviour, not {tail}",
                  gate=gx, criterion=c.get("id"))
            if is_nondet(c.get("cmd")):
                F("warn", "nondeterministic", p["id"],
                  f"{gx}[{cid_s}] touches network/time — may flake; gates must be deterministic",
                  gate=gx, criterion=c.get("id"))
            if is_side_effecting(c.get("cmd")):
                F("warn", "side_effecting", p["id"],
                  f"{gx}[{cid_s}] writes/creates files — a gate must OBSERVE, not PRODUCE its evidence (self-fabricated pass)",
                  gate=gx, criterion=c.get("id"))
            if any("\x1e" in v or "\x1f" in v for v in ((c.get(k) if isinstance(c.get(k), str) else "") for k in ("cmd", "desc"))):
                F("error", "control_char", p["id"],
                  f"{gx}[{cid_s}] cmd/desc contains a \\x1e/\\x1f control byte — it would corrupt the gate runner's record transport; remove it",
                  gate=gx, criterion=c.get("id"))
        if behavioral == 0:
            F("error", "hollow_gate", p["id"],
              f"gate {gx} has NO behavioural criterion — phase {p['id']} passes without proving its work",
              gate=gx)
        # "Has a review" = the review value is a dict (node: a non-array object); any other shape is
        # a lint error, never a crash here.
        rv = _gate_obj(gates, gx).get("review")
        if isinstance(rv, dict) and not (isinstance(rv.get("constraints"), list) and rv["constraints"]):
            F("warn", "unconstrained_review", p["id"],
              f"gate {gx} has an adversarial review but no plan-time constraints — the refuter's target is implicit (add review.constraints)",
              gate=gx)

        task_text = " ".join(f"{t['title'] if isinstance(t.get('title'), str) else ''} {t['description'] if isinstance(t.get('description'), str) else ''}" for t in tasks).lower()  # strings only (== node)
        paths = set()
        for c in crit:
            if not isinstance(c, dict) or not isinstance(c.get("cmd"), str):
                continue   # hostile shapes are lint errors, skipped here
            for pth in lintmod.extract_paths(c["cmd"]):
                paths.add(pth)
        if paths and not any(pth.lower() in task_text or pth.rstrip("/").split("/")[-1].lower() in task_text for pth in paths):
            F("warn", "gate_offphase", p["id"],
              f"gate {gx} references files no task in {p['id']} mentions — it may not be testing this phase's work",
              gate=gx)

    _speculative_tail(phases, gates, F)  # horizon-guard: audit

    return {"findings": findings,
            "errors": sum(1 for f in findings if f["severity"] == "error"),
            "warns": sum(1 for f in findings if f["severity"] == "warn"),
            "parked": parked}
