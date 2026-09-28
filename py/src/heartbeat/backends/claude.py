"""claude-code backend (in-process wrapper around headless `claude -p`)."""
import os
import subprocess
from shutil import which
from . import verdict_refuted


def execute(payload):
    ctx = payload.get("context", "")
    cwd = payload.get("cwd") or os.getcwd()
    if not which("claude"):
        return {"ok": False, "summary": "claude CLI not available"}
    prompt = (f"You are a HeartBeat Stage-B worker. Do EXACTLY this one task, then stop. "
              f"Work in {cwd}. Never edit .hb/ or gate.sh.\n\n{ctx}")
    try:
        r = subprocess.run(["claude", "-p", prompt], cwd=cwd, capture_output=True, text=True, timeout=1800)
        return {"ok": r.returncode == 0, "summary": "claude completed" if r.returncode == 0 else "claude exited non-zero"}
    except Exception as e:
        return {"ok": False, "summary": f"claude error: {e}"}


def refute(payload):
    if not which("claude"):
        return {"error": "claude CLI not available"}
    prompt = (f'{payload.get("prompt", "Refute.")}\n\nContext:\n{payload.get("context", "")}\n\n'
              "You are a skeptical reviewer. End with REFUTED or CLEAR.")
    try:
        r = subprocess.run(["claude", "-p", prompt], capture_output=True, text=True, timeout=600)
        return {"refuted": verdict_refuted(r.stdout), "findings": r.stdout[:20000]}
    except Exception as e:
        return {"error": f"reviewer error: {e}"}
