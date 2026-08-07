#!/usr/bin/env python3
"""HeartBeat executor backend: LangGraph.

Wire protocol: argv[1] = execute|refute ; stdin = payload JSON ; stdout = ONE JSON line
    execute -> {"ok": bool, "summary": str}   refute -> {"refuted": bool, "findings": str}

One task == one LangGraph ReAct agent run with a save_file tool; refute is a skeptical
model call. Provider HB_EXEC_PROVIDER = anthropic (default) | ollama | openai. Any
===FILE=== blocks are honored as a fallback. Degrades if langgraph/langchain is absent.
"""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from _fileblocks import write_blocks
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
        rel = path.lstrip("/")
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
        return {"refuted": False, "findings": f"langgraph unavailable ({e})"}
    try:
        out = model.invoke(f'{payload.get("prompt", "Refute.")}\n\nContext:\n{ctx}\n\n'
                           "You are a skeptical adversarial reviewer. End with REFUTED or CLEAR.")
        text = getattr(out, "content", str(out))
        return {"refuted": "REFUTED" in str(text).upper(), "findings": str(text)[:500]}
    except Exception as e:
        return {"refuted": False, "findings": f"reviewer error: {e}"}


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "execute"
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}
    emit(do_refute(payload) if mode == "refute" else do_execute(payload))


if __name__ == "__main__":
    main()
