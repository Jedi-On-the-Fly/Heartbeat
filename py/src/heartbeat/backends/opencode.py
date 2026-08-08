"""opencode backend (in-process wrapper around headless `opencode run`).

OpenCode (SST) is a provider-agnostic terminal coding agent. `opencode run` is its
non-interactive mode; `--format json` emits structured events. The model is `-m provider/model`
(HB_EXEC_MODEL, e.g. `ollama/qwen2.5:7b-instruct` for a keyless local run, or
`anthropic/claude-...`); HB_EXEC_PROVIDER prefixes a bare model name. Degrades to protocol-valid
JSON if `opencode` isn't on PATH.

Headless autonomy note: opencode's `run` blocks on an "ask" permission when there's no TTY.
Configure opencode.json `permission: allow` for unattended HeartBeat use (opencode 0.15.3 has no
`--auto` flag). The adapter closes stdin defensively (the prompt travels as an argv message).
"""
import os
import subprocess
from shutil import which


def _model():
    m = os.environ.get("HB_EXEC_MODEL")
    if not m:
        return None
    prov = os.environ.get("HB_EXEC_PROVIDER")
    return f"{prov}/{m}" if (prov and "/" not in m) else m


def _cmd(prompt):
    argv = ["opencode", "run", "--format", "json"]
    m = _model()
    if m:
        argv += ["-m", m]
    argv.append(prompt)
    return argv


def execute(payload):
    ctx = payload.get("context", "")
    cwd = payload.get("cwd") or os.getcwd()
    if not which("opencode"):
        return {"ok": False, "summary": "opencode CLI not available"}
    prompt = ("You are a HeartBeat Stage-B worker. Do EXACTLY this one task, then stop. "
              f"Work in {cwd}. Never edit .hb/ or gate.sh.\n\n{ctx}")
    try:
        r = subprocess.run(_cmd(prompt), cwd=cwd, stdin=subprocess.DEVNULL,   # prompt is an argv message
                           capture_output=True, text=True, timeout=1800)
        summary = (r.stdout or "").strip()[-200:]
        return {"ok": r.returncode == 0,
                "summary": summary or ("opencode completed" if r.returncode == 0 else "opencode exited non-zero")}
    except Exception as e:
        return {"ok": False, "summary": f"opencode error: {e}"}


def refute(payload):
    if not which("opencode"):
        return {"refuted": False, "findings": "opencode CLI not available"}
    cwd = payload.get("cwd") or os.getcwd()
    prompt = (f'{payload.get("prompt", "Refute.")}\n\nContext:\n{payload.get("context", "")}\n\n'
              "You are a skeptical reviewer. Do not modify files. End with REFUTED or CLEAR.")
    try:
        r = subprocess.run(_cmd(prompt), cwd=cwd, stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=600)
        return {"refuted": "REFUTED" in (r.stdout or "").upper(), "findings": (r.stdout or "")[:500]}
    except Exception as e:
        return {"refuted": False, "findings": f"reviewer error: {e}"}
