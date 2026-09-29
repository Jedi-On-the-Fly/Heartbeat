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
