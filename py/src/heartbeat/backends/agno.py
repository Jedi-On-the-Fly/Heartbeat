"""Agno backend (in-process). Real FileTools; provider anthropic|ollama."""
import os
from pathlib import Path
from ._fileblocks import write_blocks
from . import refute_result


def _model():
    provider = os.environ.get("HB_EXEC_PROVIDER", "anthropic").lower()
    model_id = os.environ.get("HB_EXEC_MODEL") or ("qwen2.5:7b-instruct" if provider == "ollama" else "claude-sonnet-4-6")
    if provider == "ollama":
        from agno.models.ollama import Ollama
        return Ollama(id=model_id)
    from agno.models.anthropic import Claude
    return Claude(id=model_id)


def execute(payload):
    ctx = payload.get("context", "")
    cwd = payload.get("cwd") or os.getcwd()
    try:
        from agno.agent import Agent
        from agno.tools.file import FileTools
        agent = Agent(model=_model(), tools=[FileTools(base_dir=Path(cwd))], instructions=(
            "You are a HeartBeat Stage-B worker. Use save_file to create the file(s) the task needs "
            "with RELATIVE paths in the working directory. Do exactly one task, then stop. Never touch .hb/ or gate.sh."))
    except Exception as e:
        return {"ok": False, "summary": f"agno unavailable ({e})"}
    try:
        r = agent.run(f"{ctx}\n\nCreate the required file(s) now using save_file.")
        fb = write_blocks(getattr(r, "content", str(r)), cwd)
        return {"ok": True, "summary": f"agno ran (tools + {len(fb)} block-fallback)"}
    except Exception as e:
        return {"ok": False, "summary": f"agno run failed: {e}"}


def refute(payload):
    ctx = payload.get("context", "")
    try:
        from agno.agent import Agent
        agent = Agent(model=_model(), instructions="Skeptical adversarial reviewer. End with a final line that is only the verdict: REFUTED or CLEAR.")
    except Exception as e:
        return {"error": f"agno unavailable ({e})"}
    try:
        r = agent.run(f'{payload.get("prompt", "Refute.")}\n\nContext:\n{ctx}\n\nEnd with a final line that is only the verdict: REFUTED or CLEAR.')
        text = getattr(r, "content", str(r))
        return refute_result(text)
    except Exception as e:
        return {"error": f"reviewer error: {e}"}
