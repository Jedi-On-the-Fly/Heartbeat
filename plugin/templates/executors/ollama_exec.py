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
    """The reviewer's verdict — True (REFUTED) / False (CLEAR) — else None (fail-closed). The contract
    (py/tests/verdict_cases.json): the reply's last non-empty line is ONLY the verdict — optional
    **/`/_ markup, an optional "Verdict:" / "Final verdict —" label, the upper-case token, optional
    "." or "!" — and the nearest earlier non-empty line neither begins with a verdict token nor ends with one
    after a separator (a stacked or listed template; "… or CLEAR." inside a sentence does not count). Anything else is no verdict. Whitespace is space/tab. A last line that is only
    a token is read at face value, whatever the reply argued before it."""
    import re as _r
    A = ("[ \t]*[*_\x60]*(?:(?:[Ff]inal[ \t]+)?(?:[Vv]erdict|VERDICT)[*_\x60]*[ \t]*[:\u2014\u2013-][ \t*_\x60]*)?"
         "[\"'\u201c\u201d]?(REFUTED|CLEAR)[\"'\u201c\u201d]?[*_\x60]*[.!]?[*_\x60]*[ \t]*")
    P = ("[ \t]*(?:(?:[-*+]|[0-9]+[.)])[ \t]+)?[ \t*_\x60]*(?:(?:[Ff]inal[ \t]+)?(?:[Vv]erdict|VERDICT)[*_\x60]*[ \t]*"
         "[:\u2014\u2013-][ \t*_\x60]*)?[\"'\u201c\u201d]?(?:REFUTED|CLEAR)(?![A-Za-z0-9_])")
    E = ("(?:^|[.!?:;|/\u2014\u2013-])[ \t*_\x60\"'\u201c\u201d]*(?:REFUTED|CLEAR)"
         "[\"'\u201c\u201d*_\x60.!?:;)\\]]*[ \t]*$")
    lines = [ln.rstrip(" \t\r") for ln in (t or "").split("\n")]
    while lines and not lines[-1]:
        lines.pop()
    m = _r.fullmatch(A, lines[-1]) if lines else None
    if not m:
        return None
    k = len(lines) - 2
    while k >= 0 and not lines[k]:
        k -= 1
    if k >= 0 and (_r.match(P, lines[k]) or _r.search(E, lines[k])):
        return None   # the line before also begins or ends with a verdict: a stacked / listed template
    return m.group(1) == "REFUTED"


def _refute_result(text):
    """A verdict only when the reviewer gave one. No final REFUTED/CLEAR token is not a CLEAR:
    it is an error, which the driver escalates (fail-closed)."""
    text = str(text or "")
    if sys.argv[1:2] == ["author"]:          # author mode reuses this path: its reply is a constraint
        return {"refuted": False, "findings": text[:20000]}   # array, parsed by author_reply (fail-closed)
    v = _verdict(text)
    if v is None:
        return {"error": "no verdict line at the end of the reviewer's reply (fail-closed); the reply ends: " + text[-300:]}
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
                  'short reason. End your reply with a final line containing only the verdict, REFUTED if you found a hole or CLEAR if you could not, with nothing else on that line.')
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
