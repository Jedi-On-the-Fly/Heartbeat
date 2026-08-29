"""Progress report — ported from hb-report.js (text + json)."""
from pathlib import Path

from . import state as st


def refuter_impact(events, dag):
    """What the refuter ACTUALLY did this run, from the event log (truth) — node twin: refuterImpact.
    A `review_failed` is a CATCH (found a hole → gate_blocked); a `review_passed` is a clear (ran, could
    not refute). The lens is the gate's `review.profile`. Records what was caught, never what was missed
    (misses are unknowable by construction). The summary is structurally identical node ≡ python
    (semantically equal; the wider `hb report --json` is ASCII-escaped in python, report-wide)."""
    gates = (dag or {}).get("gates") or {}
    per = {}
    for e in events:
        ev = e.get("event")
        if ev not in ("review_failed", "review_passed"):
            continue
        g = e.get("gate")
        if not g:
            continue
        d = per.setdefault(g, {"caught": 0, "cleared": 0, "findings": []})
        if ev == "review_failed":
            d["caught"] += 1
            d["findings"].append(e.get("note") or "")
        else:
            d["cleared"] += 1
    out_gates = [{"gate": g, "profile": ((gates.get(g) or {}).get("review") or {}).get("profile"),
                  "caught": per[g]["caught"], "cleared": per[g]["cleared"], "findings": per[g]["findings"]}
                 for g in sorted(per)]
    return {"caught": sum(x["caught"] for x in out_gates),
            "cleared": sum(x["cleared"] for x in out_gates),
            "gates": out_gates}


def build(hbdir):
    dag = st.read_dag(hbdir)
    evs = st.read_events(hbdir)
    s = st.project(evs, dag)
    phases = dag.get("phases") or []
    total = sum(len(p.get("tasks") or []) for p in phases)
    done = len(s["completed_tasks"])
    return {
        "project": Path(hbdir).parent.name,
        "tasks_done": done,
        "tasks_total": total,
        "percent": int(100 * done / total + 0.5) if total else 0,  # 100*done/total then round-half-up == node Math.round (parity; op order matters for float)
        "current_phase": s["current_phase"],
        "completed_phases": s["completed_phases"],
        "phases": [
            {"id": p["id"], "title": p.get("title", ""), "gate": p.get("gate_exit"),
             "done": sum(1 for t in (p.get("tasks") or []) if t["id"] in s["completed_tasks"]),
             "total": len(p.get("tasks") or []),
             "complete": p["id"] in s["completed_phases"]}
            for p in phases
        ],
        "refuters": refuter_impact(evs, dag),
    }


def render(hbdir):
    r = build(hbdir)
    out = [f"═══ HeartBeat Report — {r['project']} ═══",
           f"Progress: {r['tasks_done']}/{r['tasks_total']} tasks ({r['percent']}%)", "", "Phases:"]
    for p in r["phases"]:
        mark = "✅" if p["complete"] else "  "
        out.append(f"  {mark} {p['id']} {p['title']} — {p['done']}/{p['total']}  [gate: {p['gate']}]")
    imp = r["refuters"]
    if imp["caught"] or imp["cleared"]:
        out += ["", f"Refuter impact: caught {imp['caught']} hole(s) across {imp['caught'] + imp['cleared']} review(s)"]
        for g in imp["gates"]:
            lens = g["profile"] or "(default prompt)"
            out.append(f"  {g['gate']} [{lens}]: caught {g['caught']}, cleared {g['cleared']}")
            for f in g["findings"]:
                out.append(f"     ✗ {(f.splitlines()[0] if f else '')[:100]}")
    return "\n".join(out)
