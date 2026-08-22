"""pydantic-ai backend (in-process). Module named pydanticai to avoid shadowing the lib.

execute over an Agent with a save_file tool; refute is a model call. Provider ollama via
an OpenAI-compatible model (keyless) or openai. FILE-block fallback. Degrades to
protocol-valid JSON if pydantic-ai isn't installed.
"""
import os

from ._fileblocks import write_blocks, norm_rel


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


def execute(payload):
    ctx = payload.get("context", "")
    cwd = payload.get("cwd") or os.getcwd()
    try:
        from pydantic_ai import Agent
        agent = Agent(_model(), system_prompt=(
            "You are a HeartBeat Stage-B worker. Do exactly one task, then stop. Use save_file with "
            "RELATIVE paths. Never touch .hb/ or gate.sh."))
    except Exception as e:
        return {"ok": False, "summary": f"pydantic-ai unavailable ({e})"}
    written = []

    @agent.tool_plain
    def save_file(path: str, content: str) -> str:
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
        res = agent.run_sync(f"{ctx}\n\nCreate the required file(s) now.")
        fb = write_blocks(_text(res), cwd)
        n = len(written) + len(fb)
        return {"ok": n > 0, "summary": f"pydantic-ai ran ({len(written)} tool writes + {len(fb)} block-fallback)"}
    except Exception as e:
        return {"ok": False, "summary": f"pydantic-ai run failed: {e}"}


def refute(payload):
    ctx = payload.get("context", "")
    try:
        from pydantic_ai import Agent
        agent = Agent(_model(), system_prompt="You are a skeptical adversarial reviewer. End with exactly one token: REFUTED or CLEAR.")
    except Exception as e:
        return {"error": f"pydantic-ai unavailable ({e})"}
    try:
        text = _text(agent.run_sync(f'{payload.get("prompt", "Refute.")}\n\nContext:\n{ctx}'))
        return {"refuted": "REFUTED" in text.upper(), "findings": text[:500]}
    except Exception as e:
        return {"error": f"reviewer error: {e}"}
