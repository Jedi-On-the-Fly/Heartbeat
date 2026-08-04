"""Agent side of the DAG audit — a backend refutes the plan semantically.

The deterministic auditor (audit.py) catches structural weakness (hollow/existence
gates). This asks a model to REFUTE that the DAG will actually verify the work — the
things static rules can't see: a gate that asserts the *wrong* behaviour, a phase whose
gate doesn't exercise the task's real requirement, missing coverage. It reuses the
executor's backend `refute` contract, so any configured backend (ollama/agno/crewai/…)
does the reading.
"""
import json

from . import audit as auditmod
from . import executor


def build_prompt(dag, det):
    L = [
        "You are a skeptical reviewer of a HeartBeat DAG — a plan of phases -> tasks -> "
        "behavioral gates. REFUTE that this DAG will truly VERIFY the work.",
        "Look for: gates that assert the WRONG behaviour, a phase whose gate does not "
        "exercise the task's real requirement, missing dependencies, or criteria that pass "
        "without proving anything.",
        "",
        "A deterministic audit already found:",
    ]
    if det["findings"]:
        for f in det["findings"]:
            L.append(f"  - [{f['rule']}] {f['message']}")
    else:
        L.append("  (no structural issues — but structure is not semantics)")
    L += ["", "The DAG:", json.dumps(dag, indent=2)[:4000], "",
          "List each concrete concern as: <gate/phase> - why it fails to verify the real work."]
    return "\n".join(L)


def run(hbdir, dag):
    det = auditmod.audit(dag)
    cfg = executor.config(hbdir)
    r = executor.dispatch(
        cfg, "refute",
        {"mode": "refute", "gate": "<dag-review>", "prompt": build_prompt(dag, det), "context": ""},
        hbdir, None,
    )
    r = r if isinstance(r, dict) else {}
    return {"det": det, "refuted": bool(r.get("refuted")), "concerns": r.get("findings", "")}
