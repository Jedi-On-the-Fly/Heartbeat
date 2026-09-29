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
    """The reply's verdict — True (REFUTED) / False (CLEAR) — only when a whole-word, upper-case
    REFUTED/CLEAR is the reply's FINAL word (only punctuation/markup after it) and stands alone: after a
    sentence end or a label on its line ("… done. CLEAR", "**Verdict:** REFUTED"), or at a line start
    after a finished sentence, a heading, a label or a blank line. Anything else — no token, text after
    it ("CLEAR would be premature"), a token inside a sentence ("NOT yet CLEAR", a hard-wrapped
    "not\\nCLEAR"), a copied template ("REFUTED | CLEAR", "* REFUTED\\n* CLEAR") — is None (fail-closed).
    A reply that argues one way and ends with the other token explicitly is still read as that token."""
    import re as _r
    t = (t or "").rstrip()
    m = _r.search(r"\b(REFUTED|CLEAR)\b[\s*_`\"'\u201c\u201d.!)\]]*$", t)
    if not m:
        return None   # no token, or text after it: the verdict must be the reply's final word
    lines = t[:m.start()].split("\n")
    pre = _r.sub(r"^\s*(?:[-*+\u2022]|\d+[.)])\s+", "", lines[-1])            # a list bullet
    pre = _r.sub(r"[\s*_`#>\"'\u201c\u201d]+", " ", pre).strip()
    if pre:   # mid-line: only after a sentence end or a label ("… done. CLEAR", "Verdict: REFUTED")
        if not _r.search(r"(?:[.!?:;\u2014\u2013]|\s-)$", pre):
            return None
    elif len(lines) > 1 and lines[-2].strip():   # line start: the line before must end a sentence,
        q = _r.sub(r"[\s*_`>\"'\u201c\u201d]+$", "", lines[-2])   # or be a heading / a label
        if not (q.lstrip().startswith("#") or _r.search(r"[.!?:;)\]]$", q)):
            return None
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
                           "You are a skeptical adversarial reviewer. End with REFUTED or CLEAR.")
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
