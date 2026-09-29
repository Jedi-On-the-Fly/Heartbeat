#!/usr/bin/env python3
"""HeartBeat executor backend: AutoGen (autogen-agentchat).
Wire: argv[1]=execute|refute ; stdin=payload JSON ; stdout=ONE JSON line.
Provider HB_EXEC_PROVIDER=openai|ollama. FILE-block writing. Degrades if autogen absent."""
import re
import sys, os, json, asyncio


try:
    from _fileblocks import author_reply
except Exception:
    def author_reply(text):
        return {"ok": False, "error": "the author helper (_fileblocks.author_reply) is unavailable"}

def _verdict(t):
    """The reviewer's verdict — True (REFUTED) / False (CLEAR) — read from the reply's LAST non-empty line
    by an exact grammar, else None (fail-closed). The line is either (A) only the verdict: optional list
    bullet / markup, an optional "Verdict:" label, the upper-case token, optional "." / "!"; or (B) a
    finished sentence (ending ".", "!", "?") or a "verdict:" label, then the token as the final word —
    where that last sentence is not itself a bare verdict ("Verdict: REFUTED. CLEAR"). The nearest earlier
    non-empty line must not be a verdict line (a stacked or listed template), and for (A) an adjacent line
    before must end a sentence or be a heading or a label (a hard-wrapped "not\\nCLEAR"). Whitespace is
    space/tab only. A reply that argues one way and ends with a well-formed verdict line for the other is
    still read as that verdict."""
    import re as _r
    A = ("[ \t]*(?:(?:[-*+]|[0-9]+[.)])[ \t]+)?[ \t*_\x60]*(?:(?:[Ff]inal[ \t]+)?(?:[Vv]erdict|VERDICT)[ \t*_\x60]*"
         "[:\u2014\u2013-])?[ \t*_\x60\"'\u201c\u201d]*(REFUTED|CLEAR)[ \t*_\x60\"'\u201c\u201d.!]*")
    B = ("([^\n]*[A-Za-z][^\n]*(?:[.!?][)\"'\u201d*_\x60]*|(?:[Vv]erdict|VERDICT)[ \t*_\x60]*[:\u2014\u2013-]))"
         "[ \t]+[*_\x60\"'\u201c]*(REFUTED|CLEAR)[*_\x60\"'\u201d.!]*[ \t]*")
    lines = [ln.rstrip(" \t\r") for ln in (t or "").split("\n")]
    while lines and not lines[-1]:
        lines.pop()
    if not lines:
        return None
    m = _r.fullmatch(A, lines[-1])
    bare = bool(m)
    if not m:
        m = _r.fullmatch(B, lines[-1])
        if not m or _r.fullmatch(A, _r.split(r"(?<=[.!?])[ \t]+", m.group(1))[-1]):
            return None
    k = len(lines) - 2
    while k >= 0 and not lines[k]:
        k -= 1
    if k >= 0:
        p = lines[k]
        if _r.fullmatch(A, p) or _r.fullmatch(B, p):
            return None   # another verdict line before it: a stacked / listed template
        if bare and k == len(lines) - 2 and not (p.lstrip(" \t").startswith("#") or
                                                  _r.search(r"[.!?:)\]][\"'\u201d*_\x60]*$", p)):
            return None   # a bare verdict line glued to an unfinished sentence ("…is not\\nCLEAR")
    return m.group(m.lastindex) == "REFUTED"


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
    def write_blocks(text, cwd=None): return []
_STDOUT_FD = os.dup(1); os.dup2(2, 1)
def emit(o): os.write(_STDOUT_FD, (json.dumps(o) + "\n").encode())

def _client():
    provider = os.environ.get("HB_EXEC_PROVIDER", "openai").lower()
    model_id = os.environ.get("HB_EXEC_MODEL") or ("qwen2.5:7b-instruct" if provider == "ollama" else "gpt-4o-mini")
    from autogen_ext.models.openai import OpenAIChatCompletionClient
    if provider == "ollama":
        host = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")
        return OpenAIChatCompletionClient(model=model_id, base_url=f"{host}/v1", api_key="ollama",
            model_info={"family": "unknown", "function_calling": True, "vision": False, "json_output": False, "structured_output": False})
    return OpenAIChatCompletionClient(model=model_id)

def _run(instructions, task):
    from autogen_agentchat.agents import AssistantAgent
    agent = AssistantAgent("hb", model_client=_client(), system_message=instructions)
    async def go(): return await agent.run(task=task)
    res = asyncio.run(go())
    for m in reversed(getattr(res, "messages", []) or []):
        c = getattr(m, "content", None)
        if isinstance(c, str) and c.strip(): return c
    return str(res)

def do_execute(payload):
    ctx = payload.get("context", ""); cwd = payload.get("cwd") or os.getcwd()
    try:
        text = _run("You are a HeartBeat Stage-B worker. Do exactly one task, then stop. Emit each file as a block:\n===FILE: relative/path===\n<content>\n===END===\nNever touch .hb/ or gate.sh.",
                    f"{ctx}\n\nCreate the required file(s) now as FILE blocks.")
    except Exception as e:
        return {"ok": False, "summary": f"autogen unavailable ({e})"}
    written = write_blocks(text, cwd)
    return {"ok": len(written) > 0, "summary": f"autogen ran ({len(written)} block writes)"}

def do_refute(payload):
    ctx = payload.get("context", "")
    try:
        text = _run("You are a skeptical adversarial reviewer. End with REFUTED or CLEAR.", f'{payload.get("prompt","Refute.")}\n\nContext:\n{ctx}')
    except Exception as e:
        return {"error": f"autogen unavailable ({e})"}
    return _refute_result(str(text))

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
    try: payload = json.load(sys.stdin)
    except Exception: payload = {}
    emit(do_refute(payload) if mode == "refute" else do_execute(payload))
if __name__ == "__main__": main()
