#!/usr/bin/env python3
"""HeartBeat executor backend: pydantic-ai.
Wire: argv[1]=execute|refute ; stdin=payload JSON ; stdout=ONE JSON line.
Provider HB_EXEC_PROVIDER=openai|ollama. save_file tool + FILE-block fallback."""
import re
import sys, os, json


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
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from _fileblocks import write_blocks, norm_rel
except Exception:
    def write_blocks(text, cwd=None): return []
    def norm_rel(rel, cwd=None): return (rel or "").lstrip("/")
_STDOUT_FD = os.dup(1); os.dup2(2, 1)
def emit(o): os.write(_STDOUT_FD, (json.dumps(o) + "\n").encode())

def _model():
    provider = os.environ.get("HB_EXEC_PROVIDER", "openai").lower()
    model_id = os.environ.get("HB_EXEC_MODEL") or ("qwen2.5:7b-instruct" if provider == "ollama" else "gpt-4o-mini")
    if provider == "ollama":
        from pydantic_ai.models.openai import OpenAIChatModel
        from pydantic_ai.providers.openai import OpenAIProvider
        host = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")
        return OpenAIChatModel(model_id, provider=OpenAIProvider(base_url=f"{host}/v1", api_key="ollama"))
    return f"openai:{model_id}"

def _text(res):
    return str(getattr(res, "output", None) if getattr(res, "output", None) is not None else getattr(res, "data", ""))

def do_execute(payload):
    ctx = payload.get("context", ""); cwd = payload.get("cwd") or os.getcwd()
    try:
        from pydantic_ai import Agent
        agent = Agent(_model(), system_prompt="You are a HeartBeat Stage-B worker. Do exactly one task; use save_file with RELATIVE paths; never touch .hb/ or gate.sh.")
    except Exception as e:
        return {"ok": False, "summary": f"pydantic-ai unavailable ({e})"}
    written = []
    @agent.tool_plain
    def save_file(path: str, content: str) -> str:
        rel = norm_rel(path, cwd); base = os.path.realpath(cwd); dest = os.path.realpath(os.path.join(base, rel))
        if not dest.startswith(base + os.sep) or rel.startswith(".hb/"): return "refused"
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        with open(dest, "w") as f: f.write(content)
        written.append(rel); return f"wrote {rel}"
    try:
        res = agent.run_sync(f"{ctx}\n\nCreate the required file(s) now.")
        fb = write_blocks(_text(res), cwd); n = len(written) + len(fb)
        return {"ok": n > 0, "summary": f"pydantic-ai ran ({len(written)} tool writes + {len(fb)} block-fallback)"}
    except Exception as e:
        return {"ok": False, "summary": f"pydantic-ai run failed: {e}"}

def do_refute(payload):
    ctx = payload.get("context", "")
    try:
        from pydantic_ai import Agent
        agent = Agent(_model(), system_prompt="You are a skeptical adversarial reviewer. End with REFUTED or CLEAR.")
    except Exception as e:
        return {"error": f"pydantic-ai unavailable ({e})"}
    try:
        text = _text(agent.run_sync(f'{payload.get("prompt","Refute.")}\n\nContext:\n{ctx}'))
        return _refute_result(text)
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
    try: payload = json.load(sys.stdin)
    except Exception: payload = {}
    emit(do_refute(payload) if mode == "refute" else do_execute(payload))
if __name__ == "__main__": main()
