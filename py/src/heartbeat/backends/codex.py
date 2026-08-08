"""codex backend (in-process wrapper around headless `codex exec`).

Codex CLI is OpenAI's terminal coding agent — the Claude-Code analog. `codex exec` is the
non-interactive mode. Two provider paths via HB_EXEC_PROVIDER: the default authed one (ChatGPT
login / OpenAI key), or `oss` — a keyless local model through Ollama (`--oss --local-provider
ollama -m <model>`). Degrades to protocol-valid JSON if `codex` isn't on PATH.

IMPORTANT: `codex exec` reads additional input from stdin and BLOCKS forever if stdin is left
open with the prompt passed as an argument. The adapter always closes stdin (stdin=DEVNULL).
"""
import os
import subprocess
import tempfile
from shutil import which


def _cmd(prompt, cwd):
    argv = ["codex", "exec", "-s", "workspace-write", "-C", cwd, "--skip-git-repo-check"]
    if os.environ.get("HB_EXEC_PROVIDER", "").lower() == "oss":
        model = os.environ.get("HB_EXEC_MODEL", "qwen2.5:7b-instruct")
        argv += ["--oss", "--local-provider", "ollama", "-m", model]
    argv.append(prompt)
    return argv


def execute(payload):
    ctx = payload.get("context", "")
    cwd = payload.get("cwd") or os.getcwd()
    if not which("codex"):
        return {"ok": False, "summary": "codex CLI not available"}
    prompt = ("You are a HeartBeat Stage-B worker. Do EXACTLY this one task, then stop. "
              f"Work in {cwd}. Never edit .hb/ or gate.sh.\n\n{ctx}")
    last = os.path.join(tempfile.mkdtemp(), "last.txt")
    try:
        r = subprocess.run(_cmd(prompt, cwd) + ["-o", last],
                           cwd=cwd, stdin=subprocess.DEVNULL,   # codex exec hangs on open stdin
                           capture_output=True, text=True, timeout=1800)
        summary = ""
        try:
            summary = open(last).read().strip()[:200]
        except OSError:
            pass
        return {"ok": r.returncode == 0, "summary": summary or ("codex completed" if r.returncode == 0 else "codex exited non-zero")}
    except Exception as e:
        return {"ok": False, "summary": f"codex error: {e}"}


def refute(payload):
    if not which("codex"):
        return {"refuted": False, "findings": "codex CLI not available"}
    cwd = payload.get("cwd") or os.getcwd()
    prompt = (f'{payload.get("prompt", "Refute.")}\n\nContext:\n{payload.get("context", "")}\n\n'
              "You are a skeptical reviewer. Do not modify files. End with REFUTED or CLEAR.")
    try:
        r = subprocess.run(_cmd(prompt, cwd), cwd=cwd, stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=600)
        return {"refuted": "REFUTED" in r.stdout.upper(), "findings": r.stdout[:500]}
    except Exception as e:
        return {"refuted": False, "findings": f"reviewer error: {e}"}
