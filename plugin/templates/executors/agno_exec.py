#!/usr/bin/env python3
"""HeartBeat executor backend: Agno (https://github.com/agno-agi/agno).

Wire protocol (shared by every HeartBeat backend):
    driver -> backend:  argv[1] = "execute" | "refute" | "author" ; stdin = payload JSON
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
import re
import sys, os, json


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
        return {"error": "no REFUTED/CLEAR verdict in the reviewer's reply (fail-closed): " + text[:300]}
    return {"refuted": v, "findings": text[:20000]}
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
    provider = os.environ.get("HB_EXEC_PROVIDER", "anthropic").lower()
    model_id = os.environ.get("HB_EXEC_MODEL") or ("qwen2.5:7b-instruct" if provider == "ollama" else "claude-sonnet-4-6")

    try:
        from agno.agent import Agent
        model = make_model(provider, model_id)
    except Exception as e:  # agno (or its provider deps) not installed → graceful degrade
        emit({"error": f"agno unavailable ({e})"} if mode == "refute"
             else {"ok": False, "summary": f"agno unavailable ({e})"})
        return

    if mode == "refute":
        prompt = (f'{payload.get("prompt", "Refute that the phase is complete.")}\n\n'
                  f'Context:\n{ctx}\n\nEnd with a final line that is only the verdict: REFUTED or CLEAR.')
        reviewer = Agent(model=model, instructions=(
            "You are a skeptical adversarial reviewer for a phase gate. Hunt for hollow "
            "tests, criteria not truly met, or faked output. End with a final line that is only the verdict: REFUTED or CLEAR."))
        try:
            r = reviewer.run(prompt)
            text = getattr(r, "content", str(r))
            emit(_refute_result(text))
        except Exception as e:
            emit({"error": f"reviewer error: {e}"})
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
