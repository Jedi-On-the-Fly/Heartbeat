#!/usr/bin/env python3
"""HeartBeat executor backend: OpenAI Agents SDK (`openai-agents`).

Wire protocol: argv[1] = execute|refute|author ; stdin = payload JSON ; stdout = ONE JSON line
    execute -> {"ok": bool, "summary": str}   refute -> {"refuted": bool, "findings": str}

One task == one Agent run with a save_file function tool; refute is a skeptical Agent.
Provider HB_EXEC_PROVIDER = openai (default) | ollama (OpenAI-compatible /v1, keyless).
Any ===FILE=== blocks are honored as a fallback. Degrades if `agents` is absent.
"""
import re
import sys, os, json


try:
    from _fileblocks import author_reply
except Exception:
    def author_reply(text):
        return {"ok": False, "error": "the author helper (_fileblocks.author_reply) is unavailable"}

def _verdict(t):
    """The reply's verdict: its FINAL whole-word, upper-case REFUTED/CLEAR — True / False — but only
    when that token stands alone: at the start of a line, or right after a sentence end or a label
    (". CLEAR", "Verdict: REFUTED", "— CLEAR"). A token inside a sentence ("NOT yet CLEAR", "far
    from CLEAR", a copied template "REFUTED | CLEAR") is no verdict: None (fail-closed)."""
    import re as _r
    t = t or ""
    ms = list(_r.finditer(r"\b(REFUTED|CLEAR)\b", t))
    if not ms:
        return None
    a = ms[-1]
    pre = _r.sub(r"[\s*_`#>\"'\u201c\u201d]+$", "", t[:a.start()].split("\n")[-1])
    if pre and not _r.search(r"(?:[.!?:;\u2014\u2013]|\s-)$", pre):
        return None
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
    def write_blocks(text, cwd=None):
        return []

_STDOUT_FD = os.dup(1)
os.dup2(2, 1)


def emit(obj):
    os.write(_STDOUT_FD, (json.dumps(obj) + "\n").encode())


def _model():
    provider = os.environ.get("HB_EXEC_PROVIDER", "openai").lower()
    model_id = os.environ.get("HB_EXEC_MODEL") or ("qwen2.5:7b-instruct" if provider == "ollama" else "gpt-4o-mini")
    if provider == "ollama":
        from openai import AsyncOpenAI
        from agents import OpenAIChatCompletionsModel
        host = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")
        return OpenAIChatCompletionsModel(model=model_id, openai_client=AsyncOpenAI(base_url=f"{host}/v1", api_key="ollama"))
    return model_id


def _final(res):
    return getattr(res, "final_output", None) or getattr(res, "output_text", None) or str(res)


def do_execute(payload):
    ctx = payload.get("context", "")
    cwd = payload.get("cwd") or os.getcwd()
    try:
        from agents import Agent, Runner, function_tool
        model = _model()
    except Exception as e:
        return {"ok": False, "summary": f"openai-agents unavailable ({e})"}
    written = []

    @function_tool
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
        agent = Agent(name="HeartBeat worker",
                      instructions="Do exactly one task, then stop. Use save_file with RELATIVE paths. Never touch .hb/ or gate.sh.",
                      tools=[save_file], model=model)
        res = Runner.run_sync(agent, f"{ctx}\n\nCreate the required file(s) now.")
        fb = write_blocks(_final(res), cwd)
        n = len(written) + len(fb)
        return {"ok": n > 0, "summary": f"openai-agents ran ({len(written)} tool writes + {len(fb)} block-fallback)"}
    except Exception as e:
        return {"ok": False, "summary": f"openai-agents run failed: {e}"}


def do_refute(payload):
    ctx = payload.get("context", "")
    try:
        from agents import Agent, Runner
        model = _model()
    except Exception as e:
        return {"error": f"openai-agents unavailable ({e})"}
    try:
        agent = Agent(name="Skeptic",
                      instructions="You are a skeptical adversarial reviewer. End with exactly one token: REFUTED or CLEAR.",
                      model=model)
        res = Runner.run_sync(agent, f'{payload.get("prompt", "Refute.")}\n\nContext:\n{ctx}')
        text = _final(res)
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
