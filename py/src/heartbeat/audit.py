"""Adversarial DAG reviewer — deterministic gate-quality audit.

Where lint checks structure, audit checks whether gates actually PROVE their phase's
work. Ruleset is shared verbatim with the node hb-audit.js (see planning/parity-notes.md);
keep the two in lockstep so the parity test stays meaningful.
"""
import re

from . import lint as lintmod

VACUOUS = re.compile(r"^\s*(true|:|exit\s+0|echo\b|test\s+1\s*=\s*1|\[\s+1\s+=\s+1\s+\])\s*;?\s*$")
EXISTENCE = re.compile(r"^\s*(test\s+-[efds]\b|\[\s+-[efds]\b|ls(\s|$))")
NONDET = re.compile(r"\bcurl\b|\bwget\b|\bnc\b|\bping\b|\bsleep\b|\$RANDOM\b|\bdate\b|https?://(?!localhost|127\.0\.0\.1)")


def classify(cmd):
    c = (cmd or "").strip()
    if VACUOUS.match(c):
        return "vacuous"
    if EXISTENCE.match(c):
        return "existence"
    return "behavioral"


def is_nondet(cmd):
    return bool(NONDET.search(cmd or ""))


def audit(dag):
    findings = []
    phases = dag.get("phases") or []
    gates = dag.get("gates") or {}

    def F(sev, rule, phase, message, **extra):
        findings.append({"severity": sev, "rule": rule, "phase": phase, "message": message, **extra})

    for p in phases:
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
        if behavioral == 0:
            F("error", "hollow_gate", p["id"],
              f"gate {p['gate_exit']} has NO behavioural criterion — phase {p['id']} passes without proving its work",
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
            "warns": sum(1 for f in findings if f["severity"] == "warn")}
