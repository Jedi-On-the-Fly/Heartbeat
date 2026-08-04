"""Progress report — ported from hb-report.js (text + json)."""
from pathlib import Path

from . import state as st


def build(hbdir):
    dag = st.read_dag(hbdir)
    s = st.project(st.read_events(hbdir), dag)
    phases = dag.get("phases") or []
    total = sum(len(p.get("tasks") or []) for p in phases)
    done = len(s["completed_tasks"])
    return {
        "project": Path(hbdir).parent.name,
        "tasks_done": done,
        "tasks_total": total,
        "percent": int(done / total * 100) if total else 0,
        "current_phase": s["current_phase"],
        "completed_phases": s["completed_phases"],
        "phases": [
            {"id": p["id"], "title": p.get("title", ""), "gate": p.get("gate_exit"),
             "done": sum(1 for t in (p.get("tasks") or []) if t["id"] in s["completed_tasks"]),
             "total": len(p.get("tasks") or []),
             "complete": p["id"] in s["completed_phases"]}
            for p in phases
        ],
    }


def render(hbdir):
    r = build(hbdir)
    out = [f"═══ HeartBeat Report — {r['project']} ═══",
           f"Progress: {r['tasks_done']}/{r['tasks_total']} tasks ({r['percent']}%)", "", "Phases:"]
    for p in r["phases"]:
        mark = "✅" if p["complete"] else "  "
        out.append(f"  {mark} {p['id']} {p['title']} — {p['done']}/{p['total']}  [gate: {p['gate']}]")
    return "\n".join(out)
