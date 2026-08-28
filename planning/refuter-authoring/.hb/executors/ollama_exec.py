#!/usr/bin/env python3
"""HeartBeat executor backend: Ollama (local models, https://ollama.com).

Wire protocol (shared by every HeartBeat backend):
    driver -> backend:  argv[1] = "execute" | "refute" ; stdin = payload JSON
    backend -> driver:  ONE JSON object on stdout
        execute -> {"ok": bool,      "summary":  str}
        refute  -> {"refuted": bool, "findings": str}

A local text model can't call tools, so `execute` runs a tiny FILE-block protocol:
the model is told to emit one or more blocks

    ===FILE: relative/path===
    <file content>
    ===END===

and this backend writes them (relative to the current working directory — the driver
sets cwd to the task's worktree/project). The behavioral gate then verifies the work.
The backend NEVER touches .hb/ or gate.sh. Uses only the Python stdlib (urllib), so
there is nothing to pip-install; degrades to protocol-valid JSON if the server is down.

Config: HB_EXEC_MODEL / OLLAMA_MODEL (default qwen2.5:7b-instruct),
        OLLAMA_HOST (default http://localhost:11434).
"""
import sys, os, json, urllib.request, urllib.error
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _fileblocks import write_blocks


def _verdict(t):
    import re as _r
    toks = _r.findall(r"REFUTED|CLEAR", (t or "").upper())
    return bool(toks) and toks[-1] == "REFUTED"

# Guarantee ONLY the protocol JSON lands on stdout: keep the real stdout fd, then point
# fd 1 at stderr so any library chatter (banners, progress) can't corrupt the JSON line.
_STDOUT_FD = os.dup(1)
os.dup2(2, 1)

HOST  = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")
MODEL = os.environ.get("HB_EXEC_MODEL") or os.environ.get("OLLAMA_MODEL") or "qwen2.5:7b-instruct"


def emit(obj):
    os.write(_STDOUT_FD, (json.dumps(obj) + "\n").encode())


def generate(prompt, timeout=180):
    body = json.dumps({"model": MODEL, "prompt": prompt, "stream": False,
                       "options": {"temperature": 0.1}}).encode()
    req = urllib.request.Request(f"{HOST}/api/generate", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode()).get("response", "")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "execute"
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}
    ctx = payload.get("context", "")

    if mode == "refute":
        prompt = (f'{payload.get("prompt", "Refute that the phase is complete.")}\n\n'
                  f'Context:\n{ctx}\n\n'
                  'You are a skeptical adversarial reviewer. Hunt for a real hole: a hollow '
                  'test, a criterion not truly met, a faked or hard-coded output. Reply with a '
                  'short reason, then END with exactly one token: REFUTED (you found a hole) or CLEAR.')
        try:
            out = generate(prompt)
            emit({"refuted": _verdict(out), "findings": out[:500]})
        except (urllib.error.URLError, OSError) as e:
            emit({"refuted": False, "findings": f"ollama unreachable ({e})"})
        return

    # execute
    prompt = (
        "You are a HeartBeat Stage-B worker. Do EXACTLY the one task below, then stop.\n\n"
        f"{ctx}\n\n"
        "Produce every file the task needs by emitting blocks in this EXACT format "
        "(no markdown fences, no commentary outside the blocks):\n"
        "===FILE: relative/path.ext===\n"
        "<the COMPLETE file content — all functions AND their exports together>\n"
        "===END===\n\n"
        "Put the entire contents of each file in ONE block. Do not split a single file "
        "across multiple blocks. Use a RELATIVE path (e.g. greeting.js) — never an "
        "absolute path and never a $PROJECT_DIR prefix.\n"
    )
    try:
        out = generate(prompt)
    except (urllib.error.URLError, OSError) as e:
        emit({"ok": False, "summary": f"ollama unreachable ({e})"})
        return

    written = write_blocks(out)   # parse ===FILE=== blocks → write into cwd (shared helper)

    if written:
        emit({"ok": True, "summary": f"wrote {', '.join(written)}"})
    else:
        emit({"ok": False, "summary": "model produced no FILE blocks"})


if __name__ == "__main__":
    main()
