"""Ollama backend (local models, stdlib-only). FILE-block mini-agent for execute,
skeptic for refute. Degrades to a protocol-valid result if the server is unreachable."""
import os
import json
import urllib.request
import urllib.error

from ._fileblocks import write_blocks
from . import verdict_refuted

HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")


def _model():
    return os.environ.get("HB_EXEC_MODEL") or os.environ.get("OLLAMA_MODEL") or "qwen2.5:7b-instruct"


def _generate(prompt, timeout=180):
    body = json.dumps({"model": _model(), "prompt": prompt, "stream": False,
                       "options": {"temperature": 0.1}}).encode()
    req = urllib.request.Request(f"{HOST}/api/generate", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode()).get("response", "")


def execute(payload):
    ctx = payload.get("context", "")
    cwd = payload.get("cwd") or os.getcwd()
    prompt = (
        "You are a HeartBeat Stage-B worker. Do EXACTLY the one task below, then stop.\n\n"
        f"{ctx}\n\n"
        "Produce every file the task needs by emitting blocks in this EXACT format "
        "(no markdown fences, no commentary outside the blocks):\n"
        "===FILE: relative/path.ext===\n<the COMPLETE file content>\n===END===\n\n"
        "Put each file's entire contents in ONE block. Use a RELATIVE path — never an "
        "absolute path and never a $PROJECT_DIR prefix.\n"
    )
    try:
        out = _generate(prompt)
    except (urllib.error.URLError, OSError) as e:
        return {"ok": False, "summary": f"ollama unreachable ({e})"}
    written = write_blocks(out, cwd)
    return {"ok": True, "summary": f"wrote {', '.join(written)}"} if written \
        else {"ok": False, "summary": "model produced no FILE blocks"}


def refute(payload):
    ctx = payload.get("context", "")
    prompt = (f'{payload.get("prompt", "Refute that the phase is complete.")}\n\nContext:\n{ctx}\n\n'
              "You are a skeptical adversarial reviewer. Hunt for a real hole (hollow test, "
              "criterion not truly met, faked output). End with exactly one token: REFUTED or CLEAR.")
    try:
        out = _generate(prompt)
    except (urllib.error.URLError, OSError) as e:
        return {"error": f"ollama unreachable ({e})"}
    return {"refuted": verdict_refuted(out), "findings": out[:500]}
