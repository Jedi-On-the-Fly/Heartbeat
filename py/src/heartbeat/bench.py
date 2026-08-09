"""Agent benchmark harness.

Run the SAME DAG under N backends and score each behaviorally: the gates are the rubric,
and completed phases / attempts / escalations are the metric. This falls out of the DAG +
gates being backend-agnostic and deterministic.

`score(hbdir)` is a PURE function over the event log + dag — it trusts the gate outcomes
recorded in the log, never the backend's self-report. `run(source, specs)` runs each backend
on a FRESH isolated copy of the project (the source is never mutated) and scores it.
"""
import contextlib
import io
import json
import os
import shutil
import tempfile
from pathlib import Path

from . import state as st
from . import scaffold
from . import executor


def score(hbdir):
    """Pure: (event log + dag) → a behavioral scorecard. No backend self-report is trusted."""
    dag = st.read_dag(hbdir)
    events = st.read_events(hbdir)
    s = st.project(events, dag)
    phases = dag.get("phases") or []
    counts = {}
    for e in events:
        ev = e.get("event")
        if ev:
            counts[ev] = counts.get(ev, 0) + 1
    phases_done = len(s.get("completed_phases") or [])
    phases_total = len(phases)
    return {
        "phases_done": phases_done,
        "phases_total": phases_total,
        "tasks_done": len(s.get("completed_tasks") or []),
        "tasks_total": sum(len(p.get("tasks") or []) for p in phases),
        "gate_passed": counts.get("gate_passed", 0),
        "gate_failed": counts.get("gate_failed", 0),
        "task_failures": counts.get("task_failed", 0),
        "reviews_passed": counts.get("review_passed", 0),
        "completed": phases_total > 0 and phases_done == phases_total,
    }


def _parse_spec(spec):
    """'NAME' → a registered backend; 'LABEL=COMMAND' → a script backend."""
    if "=" in spec:
        label, cmd = spec.split("=", 1)
        return label.strip(), None, cmd.strip()
    return spec.strip(), spec.strip(), None


_ENV_KEYS = ("HB_EXEC_BACKEND", "HB_EXEC_CMD", "HB_NO_GIT",
             "HB_EXEC_ATTEMPT_CAP", "HB_EXEC_MAX_ITERS")


def run(source_hbdir, specs, attempt_cap=3, max_iters=50):
    """Run the source project's DAG under each backend spec on an isolated copy; score each.
    The source project is never mutated. Returns a list of scorecards."""
    dag_src = (Path(source_hbdir) / "dag.json").read_text()
    cards = []
    for spec in specs:
        label, backend, cmd = _parse_spec(spec)
        tmp = tempfile.mkdtemp()
        try:
            proj = os.path.join(tmp, "proj")
            scaffold.init(proj)
            hb = os.path.join(proj, ".hb")
            Path(hb, "dag.json").write_text(dag_src)
            Path(hb, "events.jsonl").write_text("")            # fresh log for this backend's run
            st.reproject(hb)                                   # fresh state against the copied dag
            saved = {k: os.environ.get(k) for k in _ENV_KEYS}
            os.environ["HB_NO_GIT"] = "1"
            os.environ["HB_EXEC_ATTEMPT_CAP"] = str(attempt_cap)
            os.environ["HB_EXEC_MAX_ITERS"] = str(max_iters)
            # Failures are bounded by the attempt cap, not a tick breaker: the serial executor emits
            # task_started every iteration (resetting the no-progress counter), and build_stuck fires
            # only at >=5 — clear of the default cap (3). (STUCK_TICKS is read at import, so it can't
            # be re-pinned here anyway; keep the cap < 5.)
            if cmd is not None:
                os.environ["HB_EXEC_CMD"] = cmd
                os.environ.pop("HB_EXEC_BACKEND", None)
            else:
                os.environ["HB_EXEC_BACKEND"] = backend
                os.environ.pop("HB_EXEC_CMD", None)
            buf = io.StringIO()
            try:
                with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(io.StringIO()):
                    code = executor.run(hb)                     # 0 = done/idle, 1 = escalate
            except Exception:
                code = 1
            finally:
                for k, v in saved.items():
                    if v is None:
                        os.environ.pop(k, None)
                    else:
                        os.environ[k] = v
            outcome = ""                                        # the executor's final HB-EXEC line (why it stopped)
            for ln in buf.getvalue().splitlines():
                ln = ln.strip()
                if ln.startswith("HB-EXEC"):
                    outcome = ln
            card = {"label": label}
            card.update(score(hb))
            card["escalated"] = code != 0
            card["outcome"] = outcome
            cards.append(card)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    return cards


def build(cards):
    """A JSON-serialisable view of the scorecards (identity — cards are plain dicts)."""
    return cards


def render(cards):
    """An aligned text comparison table."""
    rows = [f"{'backend':<18}{'phases':>9}{'tasks':>9}{'gates+':>8}{'fails':>7}{'esc':>5}{'done':>6}"]
    for c in cards:
        ph = f"{c['phases_done']}/{c['phases_total']}"
        tk = f"{c['tasks_done']}/{c['tasks_total']}"
        esc = "yes" if c["escalated"] else "no"
        done = "yes" if c["completed"] else "no"
        rows.append(f"{c['label']:<18}{ph:>9}{tk:>9}{c['gate_passed']:>8}{c['task_failures']:>7}{esc:>5}{done:>6}")
    return "\n".join(rows)
