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
from . import refute_result


def _cmd(prompt, cwd, sandbox="workspace-write"):
    argv = ["codex", "exec", "-s", sandbox, "-C", cwd, "--skip-git-repo-check"]
    # Network is an explicit opt-in (== codex-exec.sh): the workspace-write sandbox has none — not even
    # loopback. HB_CODEX_NETWORK=1 (only "1") opens it; the read-only author never gets it. It opens the
    # sandbox's network generally, not just loopback.
    if sandbox == "workspace-write" and os.environ.get("HB_CODEX_NETWORK") == "1":
        argv += ["-c", "sandbox_workspace_write.network_access=true"]
    if os.environ.get("HB_EXEC_PROVIDER", "").lower() == "oss":
        model = os.environ.get("HB_EXEC_MODEL", "qwen2.5:7b-instruct")
        argv += ["--oss", "--local-provider", "ollama", "-m", model]
    elif os.environ.get("HB_EXEC_MODEL"):
        argv += ["-m", os.environ["HB_EXEC_MODEL"]]   # per-role models: the recorded model must be the model that ran
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


def author(payload):
    """The gate-time constraint author (== codex-exec.sh author): the author prompt as-is, run read-only,
    reply → JSON constraint list (fail-closed)."""
    from ._fileblocks import author_reply
    if not which("codex"):
        return {"ok": False, "error": "codex CLI not available — could not run the constraint author"}
    cwd = payload.get("cwd") or os.getcwd()
    try:
        r = subprocess.run(_cmd(payload.get("prompt", ""), cwd, sandbox="read-only"), cwd=cwd,
                           stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=600)
        return author_reply(r.stdout)
    except Exception as e:
        return {"ok": False, "error": f"author error: {e}"}


def refute(payload):
    if not which("codex"):
        return {"error": "codex CLI not available"}
    cwd = payload.get("cwd") or os.getcwd()
    prompt = (f'{payload.get("prompt", "Refute.")}\n\nContext:\n{payload.get("context", "")}\n\n'
              "You are a skeptical reviewer. Do not modify files. End your reply with a final line containing only the verdict, REFUTED if you found a hole or CLEAR if you could not, with nothing else on that line.")
    try:
        r = subprocess.run(_cmd(prompt, cwd), cwd=cwd, stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=600)
        return refute_result(r.stdout)
    except Exception as e:
        return {"error": f"reviewer error: {e}"}
