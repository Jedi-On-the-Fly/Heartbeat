"""`hb init` — scaffold a .hb/ project (pure-Python; no bootstrap.sh)."""
import json
import os
import subprocess
from pathlib import Path

from . import state as st
from . import protocol

DEFAULT_DAG = {
    "_meta": {"project": "my-project"},
    "phases": [
        {"id": "P0", "title": "Foundation", "gate_entry": None, "gate_exit": "GATE_P0",
         "tasks": [
             {"id": "P0T1", "title": "Author the gate spec", "requires": [],
              "description": "Author the behavioral test/spec for this phase's gate from its checklist."},
             {"id": "P0T2", "title": "Implement the phase", "requires": ["P0T1"],
              "description": "Implement the work so the gate's behavioral criteria pass."},
         ]},
    ],
    "gates": {
        "GATE_P0": {"desc": "Foundation works",
                    "criteria": [{"id": "g1", "desc": "replace with a behavioral check", "cmd": "true"}]},
    },
}

DEFAULT_EXECUTOR = {"backend": "claude-code", "strict": False, "attempt_cap": 3}

# Pre-push gate guard: before a push, re-verify every gate and BLOCK if any regressed. Runtime-specific
# body (python calls `hb gate --all`, node calls `gate.sh --all`) — behavioral parity with bootstrap.sh.
# Bypassable at push time (`git push --no-verify` or HB_NO_HOOK=1). HeartBeat never auto-pushes.
_PRE_PUSH_HOOK = """#!/usr/bin/env bash
[ -n "${HB_NO_HOOK:-}" ] && exit 0
DIR="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -f "$DIR/.hb/dag.json" ] || exit 0
# A python HeartBeat project runs through `hb`. If it isn't on PATH, SKIP with a visible message —
# never block the push on a missing tool / an import error (the guard is a bypassable convenience).
if ! command -v hb >/dev/null 2>&1; then
  echo "HeartBeat gate guard: hb not on PATH — skipping the pre-push gate check (install heartbeat-hb, or bypass with git push --no-verify)" >&2
  exit 0
fi
# Announce BEFORE the sweep — a silent multi-minute hook is indistinguishable from a hung push.
echo "HeartBeat gate guard: re-verifying gates before push… (git push --no-verify skips)" >&2
OUT="$(hb gate --all --dir "$DIR" 2>&1)" && { printf '%s\\n' "$OUT" | grep '^✅' >&2 || true; exit 0; }
echo "✗ HeartBeat gate guard: push blocked — a gate no longer verifies." >&2
# Name the failing gate(s) — a blocked push must say WHICH claim regressed, not just that one did.
printf '%s\\n' "$OUT" | grep '^✗ ' | sed 's/^/  /' >&2
echo "  Re-verify: hb gate --all    ·    bypass: git push --no-verify" >&2
exit 1
"""


def init(project_dir, force=False):
    project = Path(project_dir)
    hb = project / ".hb"
    hb.mkdir(parents=True, exist_ok=True)

    dag = hb / "dag.json"
    if force or not dag.exists():
        dag.write_text(json.dumps(DEFAULT_DAG, indent=2))
    ex = hb / "executor.json"
    if force or not ex.exists():
        ex.write_text(json.dumps(DEFAULT_EXECUTOR, indent=2))
    # events.jsonl is the append-only source of truth — NEVER overwrite it on re-init without --force
    # (that would wipe real history; the node bootstrap refuses re-init without --force for the same reason).
    log = hb / "events.jsonl"
    if force or not log.exists():
        log.write_text(json.dumps({"event": "initialized", "project": project.name}) + "\n")
    st.reproject(hb)
    (hb / "PROTOCOL.md").write_text(protocol.render_md())

    if not os.environ.get("HB_NO_GIT"):
        _git_init(project)
    return hb


def _git_init(project):
    pd = str(project)
    try:
        already = subprocess.run(["git", "-C", pd, "rev-parse", "--is-inside-work-tree"],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        if not already:
            if subprocess.run(["git", "-C", pd, "init", "-q"],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
                return
            gi = project / ".gitignore"
            if "HeartBeat runtime" not in (gi.read_text() if gi.exists() else ""):
                with open(gi, "a") as f:
                    f.write("\n# HeartBeat runtime (ephemeral — never source)\n"
                            ".hb/.lock\n.hb/.wlock\n.hb/leases/\n.hb/.*-alerted\n.hb/.gate-blocked-ticks\n.hb/*.tmp\n.hb/wt/\n")
            subprocess.run(["git", "-C", pd, "add", "-A"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(["git", "-c", "user.name=HeartBeat", "-c", "user.email=heartbeat@local",
                            "-C", pd, "commit", "--no-verify", "-q", "-m", "chore(heartbeat): initialize project"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # Install the pre-push gate guard on a fresh OR existing repo, never clobbering an existing hook.
        hook = project / ".git" / "hooks" / "pre-push"
        if not hook.exists():
            hook.parent.mkdir(parents=True, exist_ok=True)
            hook.write_text(_PRE_PUSH_HOOK)
            os.chmod(hook, 0o755)
    except Exception:
        pass
