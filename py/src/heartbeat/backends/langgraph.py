"""LangGraph backend (in-process).

One HeartBeat task == one LangGraph ReAct agent run with a save_file tool; refute is a
single skeptical model call. Provider ollama|openai|anthropic via LangChain chat models
(ollama is keyless). Any ===FILE=== blocks in the final message are honored as a fallback.
Degrades to protocol-valid JSON if langgraph/langchain isn't installed.
"""
import os

from ._fileblocks import write_blocks, norm_rel
from . import verdict_refuted


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
    content = getattr(msgs[-1], "content", msgs[-1])
    return content if isinstance(content, str) else str(content)


def execute(payload):
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
        """Write content to a file at a RELATIVE path in the current working directory."""
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


def refute(payload):
    ctx = payload.get("context", "")
    try:
        model = _model()
    except Exception as e:
        return {"error": f"langgraph unavailable ({e})"}
    try:
        prompt = (f'{payload.get("prompt", "Refute that the phase is complete.")}\n\nContext:\n{ctx}\n\n'
                  "You are a skeptical adversarial reviewer. End with exactly one token: REFUTED or CLEAR.")
        out = model.invoke(prompt)
        text = getattr(out, "content", str(out))
        return {"refuted": verdict_refuted(str(text)), "findings": str(text)[:20000]}
    except Exception as e:
        return {"error": f"reviewer error: {e}"}
