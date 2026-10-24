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
        d = per.setdefault(g, {"caught": 0, "cleared": 0, "findings": [], "models": {}})
        # Per-model breakdown — the capability axis of "did the refuter earn its keep?".
        # Null/absent model buckets under "(none)" (one mirrored convention, node ≡ python).
        mk = e.get("model") or "(none)"
        md = d["models"].setdefault(mk, {"caught": 0, "cleared": 0})
        if ev == "review_failed":
            d["caught"] += 1
            md["caught"] += 1
            d["findings"].append(e.get("note") or "")
        else:
            d["cleared"] += 1
            md["cleared"] += 1
    out_gates = [{"gate": g, "profile": ((gates.get(g) or {}).get("review") or {}).get("profile"),
                  "caught": per[g]["caught"], "cleared": per[g]["cleared"], "findings": per[g]["findings"],
                  "models": per[g]["models"]}
                 for g in sorted(per)]
    return {"caught": sum(x["caught"] for x in out_gates),
            "cleared": sum(x["cleared"] for x in out_gates),
            "gates": out_gates}


def build(hbdir):
    dag = st.read_dag(hbdir)
    evs = st.read_events(hbdir)
    s = st.project(evs, dag)
    phases = dag.get("phases") or []
    # A parked phase is out of the plan's live surface: excluded from the progress denominator
    # (and numerator) but never hidden — it is listed in "parked" and flagged per-phase.
    live = [p for p in phases if not p.get("parked")]
    total = sum(len(p.get("tasks") or []) for p in live)
    done = sum(1 for p in live for t in (p.get("tasks") or []) if t["id"] in s["completed_tasks"])
    return {
        "project": Path(hbdir).parent.name,
        "tasks_done": done,
        "tasks_total": total,
        "percent": int(100 * done / total + 0.5) if total else 0,  # 100*done/total then round-half-up == node Math.round (parity; op order matters for float)
        "current_phase": s["current_phase"],
        "completed_phases": s["completed_phases"],
        "parked": [p["id"] for p in phases if p.get("parked")],
        "phases": [
            {"id": p["id"], "title": p.get("title", ""), "gate": p.get("gate_exit"),
             "done": sum(1 for t in (p.get("tasks") or []) if t["id"] in s["completed_tasks"]),
             "total": len(p.get("tasks") or []),
             "complete": p["id"] in s["completed_phases"],
             "parked": bool(p.get("parked"))}
            for p in phases
        ],
        "refuters": refuter_impact(evs, dag),
    }


def _horizon_line(hbdir, dag):
    """The knowledge horizon (a flagged LAST live phase): planned → REACHED (a replan decision
    is owed) → closed by a recorded verdict. '' on a project without one (== hb-report.js)."""
    live = [p for p in (dag.get("phases") or []) if not p.get("parked")]
    last = live[-1] if live else None
    if last is None or last.get("horizon") is not True:
        return ""
    evs = st.read_events(hbdir)
    s = st.project(evs, dag)
    if last["id"] in (s.get("horizon_closed") or []):
        ev = next((e for e in reversed(evs) if e.get("event") == "horizon_closed" and e.get("phase") == last["id"]), {})
        return f"Horizon: {last['id']} closed by {ev.get('actor') or '?'}: {ev.get('reason') or ''}"
    if all(p["id"] in s["completed_phases"] for p in live):
        return (f"Horizon: {last['id']} REACHED — a replan decision is owed: append the next horizon's phases, "
                f"or end the project with hb horizon close --reason <why>")
    return f"Horizon: {last['id']} (planned) — the plan ends at its knowledge horizon; completing it owes a replan decision"


def render(hbdir):
    r = build(hbdir)
    _dag_raw = st.read_dag(hbdir)
    gates_def = _dag_raw.get("gates") or {}
    phases_raw = {p.get("id"): p for p in (_dag_raw.get("phases") or [])}
    out = [f"═══ HeartBeat Report — {r['project']} ═══",
           f"Progress: {r['tasks_done']}/{r['tasks_total']} tasks ({r['percent']}%)", "", "Phases:"]
    for p in r["phases"]:
        mark = "✅" if p["complete"] else ("⏸ " if p["parked"] else "  ")
        suffix = "  (parked)" if p["parked"] else ""
        _rg = st.regate_blocks((gates_def.get(p.get("gate")) or {})) if p.get("gate") else None   # regate-guard: report — a revision is never silent
        if _rg is not None: suffix += f"  ⛔ revised — rearm pending (by {_rg.get('actor', '?')}: {_rg.get('reason', '')})"   # regate-guard: report
        _dp = phases_raw.get(p["id"]) or {}   # detach-guard: report — a retracted claim is never silent
        if "detached_from" in _dp: suffix += f"  ⟂ detached from {_dp['detached_from']} (by {_dp.get('detached_by', '?')}: {_dp.get('detached_reason', '')})"   # detach-guard: report
        out.append(f"  {mark} {p['id']} {p['title']} — {p['done']}/{p['total']}  [gate: {p['gate']}]{suffix}")
    hl = _horizon_line(hbdir, _dag_raw)
    if hl:
        out += ["", hl]
    imp = r["refuters"]
    if imp["caught"] or imp["cleared"]:
        out += ["", f"Refuter impact: caught {imp['caught']} hole(s) across {imp['caught'] + imp['cleared']} review(s)"]
        for g in imp["gates"]:
            lens = g["profile"] or "(default prompt)"
            out.append(f"  {g['gate']} [{lens}]: caught {g['caught']}, cleared {g['cleared']}")
            for m, mc in sorted((g.get("models") or {}).items()):
                out.append(f"     · {m}: caught {mc['caught']}, cleared {mc['cleared']}")
            for f in g["findings"]:
                out.append(f"     ✗ {(f.splitlines()[0] if f else '')[:100]}")
    return "\n".join(out)
