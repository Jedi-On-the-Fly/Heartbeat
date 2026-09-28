"""claude-code backend (in-process wrapper around headless `claude -p`)."""
import os
import subprocess
from shutil import which
from . import verdict_refuted


def _claude(prompt):
    """argv for `claude -p`, on the role's model when one is set (per-role models: the recorded model must
    be the model that ran); unset → the CLI's own default."""
    m = os.environ.get("HB_EXEC_MODEL")
    return ["claude"] + (["--model", m] if m else []) + ["-p", prompt]


def execute(payload):
    ctx = payload.get("context", "")
    cwd = payload.get("cwd") or os.getcwd()
    if not which("claude"):
        return {"ok": False, "summary": "claude CLI not available"}
    prompt = (f"You are a HeartBeat Stage-B worker. Do EXACTLY this one task, then stop. "
              f"Work in {cwd}. Never edit .hb/ or gate.sh.\n\n{ctx}")
    try:
        r = subprocess.run(_claude(prompt), cwd=cwd, capture_output=True, text=True, timeout=1800)
        return {"ok": r.returncode == 0, "summary": "claude completed" if r.returncode == 0 else "claude exited non-zero"}
    except Exception as e:
        return {"ok": False, "summary": f"claude error: {e}"}


def refute(payload):
    if not which("claude"):
        return {"error": "claude CLI not available"}
    prompt = (f'{payload.get("prompt", "Refute.")}\n\nContext:\n{payload.get("context", "")}\n\n'
              "You are a skeptical reviewer. End with REFUTED or CLEAR.")
    try:
        r = subprocess.run(_claude(prompt), capture_output=True, text=True, timeout=600)
        return {"refuted": verdict_refuted(r.stdout), "findings": r.stdout[:20000]}
    except Exception as e:
        return {"error": f"reviewer error: {e}"}


def author(payload):
    """The gate-time constraint author: the author prompt as-is (NOT the refuter's wrapper), reply → JSON
    constraint list (fail-closed)."""
    from ._fileblocks import author_reply
    if not which("claude"):
        return {"ok": False, "error": "claude CLI not available — could not run the constraint author"}
    try:
        r = subprocess.run(_claude(payload.get("prompt", "")), capture_output=True, text=True, timeout=600)
        return author_reply(r.stdout)
    except Exception as e:
        return {"ok": False, "error": f"author error: {e}"}
