"""opencode backend (in-process wrapper around headless `opencode run`).

OpenCode (SST) is a provider-agnostic terminal coding agent. `opencode run` is its
non-interactive mode; `--format json` emits structured events. The model is `-m provider/model`
(HB_EXEC_MODEL, e.g. `ollama/qwen2.5:7b-instruct` for a keyless local run, or
`anthropic/claude-...`); HB_EXEC_PROVIDER prefixes a bare model name. Degrades to protocol-valid
JSON if `opencode` isn't on PATH.

Autonomy + isolation, by feature (not version): when `opencode run --help` advertises them, both modes
pass --auto (else a permission "ask" blocks with no TTY) and --standalone (else v2 attaches to a
background service whose cwd/config may not be the project's). An older CLI without them needs
opencode.json `permission: allow`. stdin is closed (the prompt travels as an argv message).
"""
import json
import os
import subprocess
from shutil import which
from . import refute_result


def _model():
    m = os.environ.get("HB_EXEC_MODEL")
    if not m:
        return None
    prov = os.environ.get("HB_EXEC_PROVIDER")
    return f"{prov}/{m}" if (prov and "/" not in m) else m


def _features(cwd):
    try:
        r = subprocess.run(["opencode", "run", "--help"], cwd=cwd, stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=30)
        h = (r.stdout or "") + (r.stderr or "")
    except Exception:
        h = ""
    return [f for f in ("--standalone", "--auto") if f in h]


def _cmd(prompt, cwd):
    argv = ["opencode", "run", "--format", "json"]
    m = _model()
    if m:
        argv += ["-m", m]
    argv += _features(cwd)
    argv.append(prompt)
    return argv


def _texts(stdout):
    """The model's own words in a --format json event stream: its "text" parts, in order — never a
    tool's output (a file the reviewer read may contain REFUTED/CLEAR). Node twin: texts()."""
    out = []
    for line in (stdout or "").splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        p = (e.get("part") or {}) if isinstance(e, dict) else {}
        if e.get("type") == "text" and p.get("type") == "text" and isinstance(p.get("text"), str):
            out.append(p["text"])
    return "\n".join(out)


def execute(payload):
    ctx = payload.get("context", "")
    cwd = payload.get("cwd") or os.getcwd()
    if not which("opencode"):
        return {"ok": False, "summary": "opencode CLI not available"}
    prompt = ("You are a HeartBeat Stage-B worker. Do EXACTLY this one task, then stop. "
              f"Work in {cwd}. Never edit .hb/ or gate.sh.\n\n{ctx}")
    try:
        r = subprocess.run(_cmd(prompt, cwd), cwd=cwd, stdin=subprocess.DEVNULL,   # prompt is an argv message
                           capture_output=True, text=True, timeout=1800)
        summary = (r.stdout or "").strip()[-200:]
        return {"ok": r.returncode == 0,
                "summary": summary or ("opencode completed" if r.returncode == 0 else "opencode exited non-zero")}
    except Exception as e:
        return {"ok": False, "summary": f"opencode error: {e}"}


def refute(payload):
    if not which("opencode"):
        return {"error": "opencode CLI not available"}
    cwd = payload.get("cwd") or os.getcwd()
    prompt = (f'{payload.get("prompt", "Refute.")}\n\nContext:\n{payload.get("context", "")}\n\n'
              "You are a skeptical reviewer. Do not modify files. End with REFUTED or CLEAR.")
    try:
        r = subprocess.run(_cmd(prompt, cwd), cwd=cwd, stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=600)
        return refute_result(_texts(r.stdout))
    except Exception as e:
        return {"error": f"reviewer error: {e}"}
