"""Ollama backend (local models, stdlib-only). FILE-block mini-agent for execute,
skeptic for refute. Degrades to a protocol-valid result if the server is unreachable."""
import os
import json
import urllib.request
import urllib.error

from ._fileblocks import write_blocks
from . import refute_result

HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")


def _model():
    return os.environ.get("HB_EXEC_MODEL") or os.environ.get("OLLAMA_MODEL") or "qwen2.5:7b-instruct"


class Truncated(Exception):
    pass


def _num_ctx():
    # Ollama's default context (4096) TRUNCATES a longer prompt silently — ask for an explicit one
    # (node twin: NUM_CTX in executors/ollama_exec.py).
    return int(os.environ.get("HB_OLLAMA_NUM_CTX") or 16384)


def _generate(prompt, timeout=180):
    num_ctx = _num_ctx()
    body = json.dumps({"model": _model(), "prompt": prompt, "stream": False,
                       "options": {"temperature": 0.1, "num_ctx": num_ctx}}).encode()
    req = urllib.request.Request(f"{HOST}/api/generate", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        reply = json.loads(r.read().decode())
    used = int(reply.get("prompt_eval_count") or 0)
    if used >= num_ctx - 1:   # the prompt filled the context: the model never saw the whole request
        raise Truncated(f"the prompt filled the model's context ({used} of {num_ctx} tokens) — raise HB_OLLAMA_NUM_CTX")
    return reply.get("response", "")


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
    except Truncated as e:
        return {"ok": False, "summary": f"task prompt truncated: {e}"}
    except (urllib.error.URLError, OSError) as e:
        return {"ok": False, "summary": f"ollama unreachable ({e})"}
    written = write_blocks(out, cwd)
    return {"ok": True, "summary": f"wrote {', '.join(written)}"} if written \
        else {"ok": False, "summary": "model produced no FILE blocks"}


def refute(payload):
    ctx = payload.get("context", "")
    prompt = (f'{payload.get("prompt", "Refute that the phase is complete.")}\n\nContext:\n{ctx}\n\n'
              "You are a skeptical adversarial reviewer. Hunt for a real hole (hollow test, "
              "criterion not truly met, faked output). End your reply with a final line containing only the verdict, REFUTED if you found a hole or CLEAR if you could not, with nothing else on that line.")
    try:
        out = _generate(prompt)
    except Truncated as e:
        return {"error": f"refute prompt truncated: {e}"}
    except (urllib.error.URLError, OSError) as e:
        return {"error": f"ollama unreachable ({e})"}
    return refute_result(out)
