#!/usr/bin/env python3
"""HeartBeat executor backend: Ollama (local models, https://ollama.com).

Wire protocol (shared by every HeartBeat backend):
    driver -> backend:  argv[1] = "execute" | "refute" | "author" ; stdin = payload JSON
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
import re
import sys, os, json, urllib.request, urllib.error
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _fileblocks import write_blocks


try:
    from _fileblocks import author_reply
except Exception:
    def author_reply(text):
        return {"ok": False, "error": "the author helper (_fileblocks.author_reply) is unavailable"}

def _verdict(t):
    """The reply's FINAL whole-word, upper-case REFUTED/CLEAR: True / False — or None when there is
    none ("unclear" or a lower-case "all clear" is not a verdict)."""
    import re as _r
    ms = list(_r.finditer(r"\b(REFUTED|CLEAR)\b", t or ""))
    if not ms:
        return None
    a = ms[-1]
    if len(ms) > 1 and ms[-2].group(1) != a.group(1) and \
            _r.fullmatch(r"\W*(?:or|and)?\W*", (t or "")[ms[-2].end():a.start()], _r.I):
        return None   # "REFUTED | CLEAR", "REFUTED or CLEAR": a copied answer template, no verdict
    if _r.search(r"(?:\bnot|n't)\W*$", (t or "")[:a.start()], _r.I):
        return None   # "NOT CLEAR", "isn't REFUTED": a negated token is no verdict
    return a.group(1) == "REFUTED"


def _refute_result(text):
    """A verdict only when the reviewer gave one. No final REFUTED/CLEAR token is not a CLEAR:
    it is an error, which the driver escalates (fail-closed)."""
    text = str(text or "")
    if sys.argv[1:2] == ["author"]:          # author mode reuses this path: its reply is a constraint
        return {"refuted": False, "findings": text[:20000]}   # array, parsed by author_reply (fail-closed)
    v = _verdict(text)
    if v is None:
        return {"error": "no REFUTED/CLEAR verdict in the reviewer's reply (fail-closed): " + text[:300]}
    return {"refuted": v, "findings": text[:20000]}

# Guarantee ONLY the protocol JSON lands on stdout: keep the real stdout fd, then point
# fd 1 at stderr so any library chatter (banners, progress) can't corrupt the JSON line.
_STDOUT_FD = os.dup(1)
os.dup2(2, 1)

HOST  = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")
MODEL = os.environ.get("HB_EXEC_MODEL") or os.environ.get("OLLAMA_MODEL") or "qwen2.5:7b-instruct"


def emit(obj):
    os.write(_STDOUT_FD, (json.dumps(obj) + "\n").encode())


# Ollama's default context is small (4096 tokens) and it TRUNCATES a longer prompt silently — a
# constraint-first refute prompt is longer. Ask for an explicit context, and refuse a result whose
# prompt filled it (the model never saw the whole request).
NUM_CTX = int(os.environ.get("HB_OLLAMA_NUM_CTX") or 16384)


class Truncated(Exception):
    pass


def generate(prompt, timeout=180):
    body = json.dumps({"model": MODEL, "prompt": prompt, "stream": False,
                       "options": {"temperature": 0.1, "num_ctx": NUM_CTX}}).encode()
    req = urllib.request.Request(f"{HOST}/api/generate", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        reply = json.loads(r.read().decode())
    used = int(reply.get("prompt_eval_count") or 0)
    if used >= NUM_CTX - 1:
        raise Truncated(f"the prompt filled the model's context ({used} of {NUM_CTX} tokens) — "
                        "raise HB_OLLAMA_NUM_CTX")
    return reply.get("response", "")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "execute"
    # Constraint-first review: `author` runs the refute path on the author prompt, then converts the
    # reply to {"ok", "constraints"} (fail-closed). Any other unknown mode is REFUSED — it must never
    # fall through to execute (which writes files).
    global emit
    if mode not in ("execute", "refute", "author"):
        emit({"error": f"unsupported mode {mode!r} (execute | refute | author)"})
        return
    if mode == "author":
        _emit_raw = emit
        emit = lambda obj: _emit_raw(author_reply((obj or {}).get("findings", "") if isinstance(obj, dict) else ""))  # noqa: E731
        mode = "refute"
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
            emit(_refute_result(out))
        except Truncated as e:
            emit({"error": f"refute prompt truncated: {e}"})
        except (urllib.error.URLError, OSError) as e:
            emit({"error": f"ollama unreachable ({e})"})
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
    except Truncated as e:
        emit({"ok": False, "summary": f"task prompt truncated: {e}"})
        return
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
