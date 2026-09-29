#!/usr/bin/env python3
"""HeartBeat executor backend: LangGraph.

Wire protocol: argv[1] = execute|refute|author ; stdin = payload JSON ; stdout = ONE JSON line
    execute -> {"ok": bool, "summary": str}   refute -> {"refuted": bool, "findings": str}

One task == one LangGraph ReAct agent run with a save_file tool; refute is a skeptical
model call. Provider HB_EXEC_PROVIDER = anthropic (default) | ollama | openai. Any
===FILE=== blocks are honored as a fallback. Degrades if langgraph/langchain is absent.
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
        return {"error": "no verdict line at the end of the reviewer's reply (fail-closed); the reply ends: " + text[-300:]}
    return {"refuted": v, "findings": text[:20000]}
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from _fileblocks import write_blocks, norm_rel
except Exception:
    def write_blocks(text, cwd=None):
        return []

# Only the protocol JSON on stdout; framework chatter -> stderr.
_STDOUT_FD = os.dup(1)
os.dup2(2, 1)


def emit(obj):
    os.write(_STDOUT_FD, (json.dumps(obj) + "\n").encode())


def _model():
    provider = os.environ.get("HB_EXEC_PROVIDER", "anthropic").lower()
    model_id = os.environ.get("HB_EXEC_MODEL") or ("qwen2.5:7b-instruct" if provider == "ollama" else "claude-sonnet-4-6")
    if provider == "ollama":
        from langchain_ollama import ChatOllama
        return ChatOllama(model=model_id, base_url=os.environ.get("OLLAMA_HOST", "http://localhost:11434"), temperature=0.1)
    if provider == "openai":
        from langchain_openai import ChatOpenAI
        return ChatOpenAI(model=model_id, temperature=0.1)
    from langchain_anthropic import ChatAnthropic
    return ChatAnthropic(model=model_id)


def _last_text(res):
    msgs = res.get("messages") if isinstance(res, dict) else None
    if not msgs:
        return ""
    c = getattr(msgs[-1], "content", msgs[-1])
    return c if isinstance(c, str) else str(c)


def do_execute(payload):
    ctx = payload.get("context", "")
    cwd = payload.get("cwd") or os.getcwd()
    try:
        from langgraph.prebuilt import create_react_agent
        from langchain_core.tools import tool
        model = _model()
    except Exception as e:
        return {"ok": False, "summary": f"langgraph unavailable ({e})"}
    written = []

    @tool
    def save_file(path: str, content: str) -> str:
        """Write content to a RELATIVE path in the current working directory."""
        rel = norm_rel(path, cwd)
        base = os.path.realpath(cwd)
        dest = os.path.realpath(os.path.join(base, rel))
        if not dest.startswith(base + os.sep) or rel.startswith(".hb/"):
            return "refused: path outside the working directory"
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        with open(dest, "w") as f:
            f.write(content)
        written.append(rel)
        return f"wrote {rel}"

    try:
        agent = create_react_agent(model, [save_file])
        res = agent.invoke({"messages": [("user",
            f"{ctx}\n\nCreate the required file(s) now using save_file with RELATIVE paths, then stop.")]})
        fb = write_blocks(_last_text(res), cwd)
        n = len(written) + len(fb)
        return {"ok": n > 0, "summary": f"langgraph ran ({len(written)} tool writes + {len(fb)} block-fallback)"}
    except Exception as e:
        return {"ok": False, "summary": f"langgraph run failed: {e}"}


def do_refute(payload):
    ctx = payload.get("context", "")
    try:
        model = _model()
    except Exception as e:
        return {"error": f"langgraph unavailable ({e})"}
    try:
        out = model.invoke(f'{payload.get("prompt", "Refute.")}\n\nContext:\n{ctx}\n\n'
                           "You are a skeptical adversarial reviewer. End your reply with a final line containing only the verdict, REFUTED if you found a hole or CLEAR if you could not, with nothing else on that line.")
        text = getattr(out, "content", str(out))
        return _refute_result(str(text))
    except Exception as e:
        return {"error": f"reviewer error: {e}"}


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
    emit(do_refute(payload) if mode == "refute" else do_execute(payload))


if __name__ == "__main__":
    main()
