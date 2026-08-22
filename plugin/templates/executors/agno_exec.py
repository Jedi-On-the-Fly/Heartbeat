#!/usr/bin/env python3
"""HeartBeat executor backend: Agno (https://github.com/agno-agi/agno).

Wire protocol (shared by every HeartBeat backend):
    driver -> backend:  argv[1] = "execute" | "refute" ; stdin = payload JSON
    backend -> driver:  ONE JSON object on stdout
        execute -> {"ok": bool,      "summary":  str}
        refute  -> {"refuted": bool, "findings": str}

One HeartBeat task == one Agno agent run. For `execute` the agent is given REAL file
tools (agno.tools.file.FileTools) so it writes into the current directory itself; any
===FILE=== blocks in its final text are also honored as a fallback. It NEVER touches
.hb/ or gate.sh — the driver mediates all state. Degrades to protocol-valid JSON if
`agno` isn't installed.

Provider: HB_EXEC_PROVIDER = anthropic (default) | ollama.
Model:    HB_EXEC_MODEL (default: claude-sonnet-4-6, or qwen2.5:7b-instruct for ollama).
"""
import sys, os, json


def _verdict(t):
    import re as _r
    toks = _r.findall(r"REFUTED|CLEAR", (t or "").upper())
    return bool(toks) and toks[-1] == "REFUTED"
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from _fileblocks import write_blocks
except Exception:
    def write_blocks(text, cwd=None):
        return []

# Guarantee ONLY the protocol JSON lands on stdout: keep the real stdout fd, then point
# fd 1 at stderr so any framework chatter (banners, progress) can't corrupt the JSON line.
_STDOUT_FD = os.dup(1)
os.dup2(2, 1)


def emit(obj):
    os.write(_STDOUT_FD, (json.dumps(obj) + "\n").encode())


def make_model(provider, model_id):
    if provider == "ollama":
        from agno.models.ollama import Ollama
        return Ollama(id=model_id)
    from agno.models.anthropic import Claude
    return Claude(id=model_id)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "execute"
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}
    ctx = payload.get("context", "")
    provider = os.environ.get("HB_EXEC_PROVIDER", "anthropic").lower()
    model_id = os.environ.get("HB_EXEC_MODEL") or ("qwen2.5:7b-instruct" if provider == "ollama" else "claude-sonnet-4-6")

    try:
        from agno.agent import Agent
        model = make_model(provider, model_id)
    except Exception as e:  # agno (or its provider deps) not installed → graceful degrade
        emit({"refuted": False, "findings": f"agno unavailable ({e})"} if mode == "refute"
             else {"ok": False, "summary": f"agno unavailable ({e})"})
        return

    if mode == "refute":
        prompt = (f'{payload.get("prompt", "Refute that the phase is complete.")}\n\n'
                  f'Context:\n{ctx}\n\nEnd with exactly one token: REFUTED or CLEAR.')
        reviewer = Agent(model=model, instructions=(
            "You are a skeptical adversarial reviewer for a phase gate. Hunt for hollow "
            "tests, criteria not truly met, or faked output. End with REFUTED or CLEAR."))
        try:
            r = reviewer.run(prompt)
            text = getattr(r, "content", str(r))
            emit({"refuted": _verdict(text), "findings": text[:500]})
        except Exception as e:
            emit({"refuted": False, "findings": f"reviewer error: {e}"})
        return

    # execute — give the agent real file tools
    from pathlib import Path
    from agno.tools.file import FileTools
    worker = Agent(model=model, tools=[FileTools(base_dir=Path(os.getcwd()))], instructions=(
        "You are a HeartBeat Stage-B worker. Use your file tools (save_file) to CREATE the "
        "file(s) the task needs, using RELATIVE paths in the current directory. Do exactly "
        "one task, then stop. Never touch .hb/ or gate.sh."))
    try:
        r = worker.run(f"{ctx}\n\nCreate the required file(s) now using save_file.")
        text = getattr(r, "content", str(r))
        fb = write_blocks(text)   # fallback: honor any ===FILE=== blocks in the text too
        emit({"ok": True, "summary": f"agno agent ran (file tools + {len(fb)} block-fallback)"})
    except Exception as e:
        emit({"ok": False, "summary": f"agno run failed: {e}"})


if __name__ == "__main__":
    main()
