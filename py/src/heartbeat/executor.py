"""Executor driver (pure-Python). Ported from hb-exec.js.

HeartBeat stays the deterministic brain (tick decides what/when, gates verify); this
driver dispatches each task to a backend (in-process for ollama/agno/crewai/claude, or a
subprocess via HB_EXEC_CMD) and mediates every state transition. Escalate-only on a
blocked gate; per-task attempt cap; strict-gate refusal; serial or worktree-parallel.
"""
import concurrent.futures as cf
import json
import os
import re
import shutil
import subprocess
import sys
import threading
from pathlib import Path

from . import state as st
from . import resolver as rv
from . import lint as lintmod
from . import gate as gatemod
from . import tick as tickmod
from . import report as reportmod
from . import backends


def _envbool(name, dflt):
    v = os.environ.get(name)
    return dflt if v is None else v in ("1", "true")


def config(hbdir):
    f = {}
    try:
        f = json.loads((Path(hbdir) / "executor.json").read_text())
    except Exception:
        pass
    hb_stale = int(os.environ.get("HEARTBEAT_STALE_S", "180"))
    backend = os.environ.get("HB_EXEC_BACKEND") or f.get("backend") or "claude-code"
    cmd = os.environ.get("HB_EXEC_CMD") or f.get("cmd")
    return {
        "backend": backend,
        "cmd": cmd,
        # Generic, domain-neutral context hook: a command whose stdout is appended to each task's
        # context (see assemble_context). The executor knows nothing about what it produces.
        "context_cmd": os.environ.get("HB_EXEC_CONTEXT_CMD") or f.get("context_cmd"),
        "strict": _envbool("HB_EXEC_STRICT", bool(f.get("strict", False))),
        "attempt_cap": int(os.environ.get("HB_EXEC_ATTEMPT_CAP") or f.get("attempt_cap") or 3),
        "concurrency": max(1, int(os.environ.get("HB_MAX_CONCURRENCY") or f.get("concurrency") or 1)),
        "heartbeat_s": int(os.environ.get("HB_EXEC_HEARTBEAT_S") or max(1, hb_stale // 2)),
        # Cross-model refuter: run `refute` on a distinct backend/cmd/model from the doer.
        # Each falls back to the doer's value, so default behavior is byte-unchanged. The cmd
        # falls back to the doer's cmd ONLY when no distinct refute backend was requested —
        # otherwise a distinct backend + the doer's explicit cmd would wrongly route to the doer.
        "refute_backend": os.environ.get("HB_REFUTE_BACKEND") or f.get("refute_backend") or backend,
        "refute_cmd": (os.environ.get("HB_REFUTE_CMD") or f.get("refute_cmd")
                       or (None if (os.environ.get("HB_REFUTE_BACKEND") or f.get("refute_backend")) else cmd)),
        "refute_model": os.environ.get("HB_REFUTE_MODEL") or f.get("refute_model"),
        "refute_provider": os.environ.get("HB_REFUTE_PROVIDER") or f.get("refute_provider"),
    }


def assemble_context(hbdir, task):
    dag = st.read_dag(hbdir)
    state = st.read_state(hbdir) or {}
    phase = next((p for p in (dag.get("phases") or []) if p["id"] == task.get("phase")), {})
    gate = (dag.get("gates") or {}).get(phase.get("gate_exit")) if phase.get("gate_exit") else None
    pd = str(Path(hbdir).parent)
    L = [f"Project {Path(pd).name} (dir: {pd}).",
         f"Phase {task.get('phase')}. Task {task['id']}: {task.get('title')}"]
    if task.get("description"):
        L.append("\nWhat to do:\n" + task["description"])
    done_here = [t for t in (state.get("completed_tasks") or []) if any(x["id"] == t for x in (phase.get("tasks") or []))]
    if done_here:
        L.append("\nAlready completed in this phase: " + ", ".join(done_here))
    if gate and gate.get("criteria"):
        L.append(f"\nThis phase's gate ({phase.get('gate_exit')}) will verify — build to pass, do NOT edit the gate:")
        for c in gate["criteria"]:
            L.append(f"  - {c.get('desc', c.get('id'))}: {c.get('cmd')}")
    L.append("\nDo exactly this one task, then stop. Work in the project directory. Do not modify .hb/.")
    return "\n".join(L) + _context_hook(hbdir, task)


def _context_hook(hbdir, task):
    """Generic context hook: if a context_cmd is configured, run it and append its stdout to the
    task context, delimited. Domain-neutral — the executor never inspects what the command emits."""
    cmd = config(hbdir).get("context_cmd")
    if not cmd:
        return ""
    env = dict(os.environ, HB_TASK_ID=str(task.get("id", "")),
               HB_TASK_TITLE=str(task.get("title", "")), HB_TASK_DESC=str(task.get("description", "")))
    try:
        r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, env=env, timeout=30)
        text = (r.stdout or "").strip()
    except Exception as e:                       # degrade: a broken provider must not fail the task
        sys.stderr.write(f"context_cmd failed: {e}\n")
        return ""
    return f"\n\n<<HB-CONTEXT>>\n{text}\n<</HB-CONTEXT>>" if text else ""


class _Pump:
    """Refresh the task's lease heartbeat while a backend runs."""
    def __init__(self, hbdir, task, interval):
        self.hbdir, self.task, self.interval = hbdir, task, interval
        self._stop = threading.Event()
        self._t = None

    def __enter__(self):
        if self.task and self.interval > 0:
            def loop():
                while not self._stop.wait(self.interval):
                    lease = st.leases_dir(self.hbdir) / self.task
                    if lease.exists():
                        try:
                            (lease / "beat").write_text(st.now_iso())
                        except OSError:
                            pass
            self._t = threading.Thread(target=loop, daemon=True)
            self._t.start()
        return self

    def __exit__(self, *a):
        self._stop.set()
        if self._t:
            self._t.join(timeout=1)


def dispatch(cfg, mode, payload, hbdir, task_id, cwd=None, model=None, provider=None):
    cwd = cwd or os.path.abspath(str(Path(hbdir).parent))   # absolute: a relative --dir must not break the worker's cwd
    # Cross-model override: run this call under a distinct model/provider (backends and the
    # subprocess wire both read HB_EXEC_MODEL/PROVIDER from the env). Restored in finally.
    saved = {}
    for k, v in (("HB_EXEC_MODEL", model), ("HB_EXEC_PROVIDER", provider)):
        if v is not None:
            saved[k] = os.environ.get(k)
            os.environ[k] = v
    try:
        with _Pump(hbdir, task_id, cfg["heartbeat_s"]):
            if cfg["cmd"]:
                try:
                    r = subprocess.run(["bash", "-c", f"{cfg['cmd']} {mode}"], cwd=cwd,
                                       input=json.dumps(payload), capture_output=True, text=True, timeout=1800)
                    lines = [ln for ln in r.stdout.strip().splitlines() if ln.strip()]
                    return json.loads(lines[-1]) if lines else {}
                except Exception:
                    return {}
            mod = backends.get(cfg["backend"])
            p = dict(payload)
            p["cwd"] = cwd
            return mod.execute(p) if mode == "execute" else mod.refute(p)
    finally:
        for k, old in saved.items():
            if old is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = old


def _strict_block(hbdir, gate_id):
    dag = st.read_dag(hbdir)
    gate = (dag.get("gates") or {}).get(gate_id, {})
    reasons = []
    for c in (gate.get("criteria") or []):
        if re.match(r"\s*(test\s+-[efds]\b|\[\s+-[efds]\b|ls\b)", c.get("cmd", "")):
            reasons.append(f"gate {gate_id} has a non-behavioral criterion")
            break
    w = lintmod.lint(dag)["warnings"]
    if w:
        reasons.append(f"hb-lint: {len(w)} warning(s) — {w[0]}")
    return reasons


def _git_isolation(hbdir):
    if os.environ.get("HB_NO_GIT"):
        return False
    pd = str(Path(hbdir).parent)
    return subprocess.run(["git", "-C", pd, "rev-parse", "--is-inside-work-tree"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def _git(pd, *args):
    return subprocess.run(["git", "-C", pd, *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _worktree_dispatch(hbdir, cfg, attempts, iso, merge_lock, t):
    st.acquire_lease(hbdir, t["id"])
    st.mutate(hbdir, {"event": "task_started", "task": t["id"]})
    pd = os.path.abspath(str(Path(hbdir).parent))       # absolute: git -C pd + a relative wt would double-nest (proj/proj/.hb/wt)
    cwd, wt, branch = pd, None, None
    if iso:
        branch = f"hb-exec/{t['id']}"
        wt = os.path.abspath(str(Path(hbdir) / "wt" / t["id"]))
        Path(wt).parent.mkdir(parents=True, exist_ok=True)
        if _git(pd, "worktree", "add", "--quiet", "-B", branch, wt, "HEAD").returncode == 0:
            cwd = wt
        else:
            wt = None

    r = dispatch(cfg, "execute", {"mode": "execute", "task": t, "context": assemble_context(hbdir, t)},
                 hbdir, t["id"], cwd=cwd)
    ok = r.get("ok") is True
    capped = False

    def bump():
        nonlocal capped
        attempts[t["id"]] = attempts.get(t["id"], 0) + 1
        if attempts[t["id"]] >= cfg["attempt_cap"]:
            capped = True

    if ok and wt:
        try:
            with merge_lock:
                _git(wt, "add", "-A")
                if _git(wt, "diff", "--cached", "--quiet").returncode != 0:
                    subprocess.run(["git", "-c", "user.name=HeartBeat", "-c", "user.email=heartbeat@local",
                                    "-C", wt, "commit", "--no-verify", "-q", "-m", f"hb-exec({t['id']}): {t.get('title')}"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if _git(pd, "merge", "--no-verify", "--no-edit", "-q", branch).returncode != 0:
                    _git(pd, "merge", "--abort")
                    raise RuntimeError("merge conflict")
            st.mutate(hbdir, {"event": "task_done", "task": t["id"]})
        except Exception:
            st.mutate(hbdir, {"event": "task_failed", "task": t["id"], "reason": "merge conflict"})
            bump()
    elif ok:
        st.mutate(hbdir, {"event": "task_done", "task": t["id"]})
    else:
        st.mutate(hbdir, {"event": "task_failed", "task": t["id"], "reason": r.get("summary", "")})
        bump()

    st.release_lease(hbdir, t["id"])
    if wt:
        _git(pd, "worktree", "remove", "--force", wt)
        _git(pd, "branch", "-D", branch)
    return "capped" if capped else "ok"


def _fan_out(hbdir, cfg, attempts):
    s = st.project(st.read_events(hbdir), st.read_dag(hbdir))
    ready = rv.ready_tasks(s, st.read_dag(hbdir), hbdir, cfg["concurrency"])
    if not ready:
        return "continue"
    iso = _git_isolation(hbdir)
    print(f"⇉ fan-out {len(ready)} task(s) [{'worktree-isolated' if iso else 'in-place'}]: "
          + ", ".join(t["id"] for t in ready))
    merge_lock = threading.Lock()
    with cf.ThreadPoolExecutor(max_workers=cfg["concurrency"]) as ex:
        results = list(ex.map(lambda t: _worktree_dispatch(hbdir, cfg, attempts, iso, merge_lock, t), ready))
    return "stop" if "capped" in results else "continue"


def run(hbdir):
    # In-process, so don't leak HB_ACTOR into the caller's environment.
    _saved = os.environ.get("HB_ACTOR")
    try:
        return _run(hbdir)
    finally:
        if _saved is None:
            os.environ.pop("HB_ACTOR", None)
        else:
            os.environ["HB_ACTOR"] = _saved


def _run(hbdir):
    cfg = config(hbdir)
    max_iters = int(os.environ.get("HB_EXEC_MAX_ITERS", "0")) or 10 ** 9
    attempts = {}
    # Distinct identities: the worker stamps task_done, the refuter stamps the review pass —
    # guaranteed different so the self-review guard is enforced in the automated path.
    worker_actor = os.environ.get("HB_ACTOR", "hb-exec:worker")
    os.environ["HB_ACTOR"] = worker_actor
    refuter_actor = f"{worker_actor}:refuter"
    for _ in range(max_iters):
        out = tickmod.tick(hbdir)
        data = out.get("data", {})
        reason = data.get("reason")
        if not out.get("wakeAgent"):
            if reason == "project_complete":
                print("HB-EXEC DONE: project complete")
                return 0
            print(f"HB-EXEC IDLE: {reason}")
            return 0

        if reason == "next_task":
            if cfg["concurrency"] > 1:
                st.release_lease(hbdir, data["next_task"]["id"])   # free the tick's single lease
                if _fan_out(hbdir, cfg, attempts) == "stop":
                    print("HB-EXEC STOP: attempts_exhausted")
                    return 1
                continue
            t = data["next_task"]
            print(f"▸ {t['id']} — {t.get('title')}")
            st.acquire_lease(hbdir, t["id"])
            st.mutate(hbdir, {"event": "task_started", "task": t["id"]})
            r = dispatch(cfg, "execute", {"mode": "execute", "task": t, "context": assemble_context(hbdir, t)},
                         hbdir, t["id"])
            if r.get("ok") is True:
                st.mutate(hbdir, {"event": "task_done", "task": t["id"]})
                st.release_lease(hbdir, t["id"])
            else:
                st.mutate(hbdir, {"event": "task_failed", "task": t["id"], "reason": r.get("summary", "")})
                st.release_lease(hbdir, t["id"])
                attempts[t["id"]] = attempts.get(t["id"], 0) + 1
                if attempts[t["id"]] >= cfg["attempt_cap"]:
                    print(f"HB-EXEC STOP: attempts_exhausted — {t['id']} failed {attempts[t['id']]}× (cap {cfg['attempt_cap']})")
                    return 1
        elif reason == "gate_pending":
            g = data["next_task"].get("gate")
            if cfg["strict"]:
                blocks = _strict_block(hbdir, g)
                if blocks:
                    print(f"HB-EXEC STOP: strict_gate — {g}: {'; '.join(blocks)}")
                    return 1
            gatemod.run_gate(hbdir, g)
        elif reason == "review_pending":
            g = data["next_task"].get("gate")
            from . import refuter_profiles as rp
            dag = st.read_dag(hbdir)
            rv_block = ((dag.get("gates") or {}).get(g, {}).get("review") or {})
            # ONE compose (shared with `hb refute-prompt` + the interactive surface). An unknown
            # profile raises → fail CLOSED (never skip the review). A profile's model/provider route
            # through the existing cross-model refute path.
            try:
                refute_prompt = rp.compose_prompt(hbdir, dag, g)
                prof = rp.gate_profile(hbdir, rv_block)
            except ValueError as e:
                print(f"HB-EXEC STOP: review_error — {g}: {e}")
                return 1
            r_model = (prof.get("model") if prof else None) or cfg["refute_model"]
            r_provider = (prof.get("provider") if prof else None) or cfg["refute_provider"]
            # Cross-model: dispatch the refute on the distinct refuter config (falls back to the doer).
            refute_cfg = {**cfg, "backend": cfg["refute_backend"], "cmd": cfg["refute_cmd"]}
            refuter_id = ("cmd:" + cfg["refute_cmd"]) if cfg["refute_cmd"] else cfg["refute_backend"]
            if r_model:
                refuter_id += f" model={r_model}"
            if (cfg["refute_backend"], cfg["refute_cmd"], r_model) != (cfg["backend"], cfg["cmd"], None):
                print(f"  ↳ refuting {g} with a distinct refuter ({refuter_id})")
            _payload = {"mode": "refute", "gate": g, "prompt": refute_prompt,
                        "context": assemble_context(hbdir, {"id": "?", "phase": data["next_task"].get("phase")})}
            verdict_cfg = (prof.get("verdict") if prof else None) or {}
            panel_n = int(verdict_cfg.get("panel") or 1)
            if panel_n > 1:
                # Perspective-diverse panel: run N refuters, aggregate by refute_if. Fail CLOSED if any
                # panelist yields no boolean verdict — an inconclusive panelist can't certify a pass.
                rule = verdict_cfg.get("refute_if") or "majority"
                verdicts, findings = [], []
                for i in range(panel_n):
                    ri = dispatch(refute_cfg, "refute", _payload, hbdir, None, model=r_model, provider=r_provider)
                    if not isinstance(ri.get("refuted"), bool):
                        print(f"HB-EXEC STOP: review_error — {g}: panelist {i + 1}/{panel_n} returned no verdict (fail-closed)")
                        return 1
                    verdicts.append(ri["refuted"])
                    # Only a panelist that produced ACTUAL text contributes a labelled finding — the
                    # `[panelist …]` prefix must never let boilerplate satisfy the pass substance floor.
                    fi = (ri.get("findings") or "").strip()
                    if fi:
                        findings.append(f"[panelist {i + 1}/{panel_n}] {fi}")
                r = {"refuted": rp.aggregate_verdict(verdicts, rule), "findings": "\n\n".join(findings)}
            else:
                r = dispatch(refute_cfg, "refute", _payload, hbdir, None, model=r_model, provider=r_provider)
            if not isinstance(r.get("refuted"), bool):
                # A degraded/unavailable refuter cannot certify a pass — never fail open.
                print(f"HB-EXEC STOP: review_error — {g}: refuter could not run ({r.get('error') or 'no verdict'})")
                return 1
            if r["refuted"]:
                st.mutate(hbdir, {"event": "review_failed", "gate": g, "note": (r.get("findings", "") or "")[:200]})
            else:
                # Sev-1: a "could not refute" pass must cite the refuter's ACTUAL written
                # attempt. Persist findings + route through the validated review path (as a
                # distinct refuter actor), so the pass is reducible to evidence — no rubber-stamp.
                findings = (r.get("findings") or "").strip()
                if len(findings) < 40:
                    print(f"HB-EXEC STOP: review_error — {g}: refuter returned a pass with no substantive findings")
                    return 1
                fdir = Path(hbdir) / "reviews"
                fdir.mkdir(parents=True, exist_ok=True)
                fpath = fdir / f"{g}.attempt.md"
                fpath.write_text(f"# Refutation attempt for {g}\n\nRefuter: {refuter_id}\n"
                                 f"Verdict: could not refute (refuted=false)\n\n{findings}\n")
                from . import review_policy
                saved = os.environ.get("HB_ACTOR")
                os.environ["HB_ACTOR"] = refuter_actor
                try:
                    rc, _out, _err = review_policy.accept_review(hbdir, g, "pass", artifact=str(fpath))
                finally:
                    if saved is None:
                        os.environ["HB_ACTOR"] = worker_actor
                    else:
                        os.environ["HB_ACTOR"] = saved
                if rc != 0:
                    print(f"HB-EXEC STOP: review_error — {g}: review pass rejected by validation")
                    return 1
        elif reason == "all_done":
            print(reportmod.render(hbdir))
            print("HB-EXEC DONE: all phases complete")
            return 0
        else:
            print(f"HB-EXEC STOP: {reason}")
            return 1
    print("HB-EXEC: max iterations reached")
    return 0
