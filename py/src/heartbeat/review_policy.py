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
from pathlib import Path

from . import state as st
from . import lint as lintmod


def accept_review(hb, gate, verdict, artifact=None, note=None):
    """Record an adversarial-review verdict. Returns (rc, out, err).

    hb       — the project's .hb directory (str or Path)
    gate     — gate id under review
    verdict  — "pass" or "fail"
    artifact — path to the refuter's written attempt (required for a pass)
    note     — optional note (str or list of tokens)
    """
    hb = str(hb)
    note_str = (" ".join(note) if isinstance(note, list) else note) or None

    if verdict == "fail":
        ev = {"event": "review_failed", "gate": gate}
        if note_str:
            ev["note"] = note_str
        st.mutate(hb, ev)
        return 0, f"review fail {gate}", ""

    # pass — must be backed by a substantive, phase-citing artifact from a distinct actor
    if not artifact:
        return 1, "", ("review pass requires --artifact <findings-file>: the refuter's written "
                       "attempt (a pass must cite evidence, not just assert one).")
    project_dir = Path(hb).parent
    ap = Path(artifact) if os.path.isabs(artifact) else project_dir / artifact
    try:
        body = ap.read_text()
    except OSError as e:
        return 1, "", f"review pass: cannot read artifact {artifact} ({e})"
    if len(body.strip()) < 40:
        return 1, "", (f"review pass: artifact {artifact} is too thin ({len(body.strip())} chars) "
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
        return 1, "", (f"review pass: artifact {artifact} does not reference the phase under review "
                       f"(it cites nothing real; expected one of: {usable}).")
    reviewer = os.environ.get("HB_ACTOR", "unknown")
    if reviewer != "unknown" and phase:
        phase_task_ids = {t["id"] for t in (phase.get("tasks") or [])}
        doers = {e.get("actor") for e in st.read_events(hb)
                 if e.get("event") == "task_done" and e.get("task") in phase_task_ids
                 and e.get("actor") and e.get("actor") != "unknown"}
        if reviewer in doers:
            return 1, "", (f"review pass: reviewer '{reviewer}' also executed this phase's work — "
                           "a self-review is not adversarial (set a different HB_ACTOR).")
    revdir = Path(hb) / "reviews"
    revdir.mkdir(parents=True, exist_ok=True)
    (revdir / f"{gate}.md").write_text(body)
    ev = {"event": "review_passed", "gate": gate, "artifact": f"reviews/{gate}.md",
          "artifact_chars": len(body.strip()), "cited": cited, "reviewer": reviewer}
    if note_str:
        ev["note"] = note_str
    st.mutate(hb, ev)
    # Reviewed acceptance is what creates the phase's restore point (commit+tag) — the
    # deterministic pass deferred it so the tag only ever certifies a reviewed-good state.
    from . import gate as _gate
    _gate._git_snapshot(hb, gate)
    return 0, (f"review pass {gate} (backed by reviews/{gate}.md, {len(body.strip())} chars, "
               f"cites: {', '.join(cited[:3])})"), ""
