"""AutoGen backend (in-process, autogen-agentchat).

execute/refute over an AssistantAgent. Provider ollama (OpenAI-compatible /v1, keyless)
or openai. Files are written via the FILE-block protocol (portable across AutoGen's async
run). Degrades to protocol-valid JSON if autogen isn't installed.
"""
import os
import asyncio

from ._fileblocks import write_blocks
from . import refute_result


def _client():
    provider = os.environ.get("HB_EXEC_PROVIDER", "openai").lower()
    model_id = os.environ.get("HB_EXEC_MODEL") or ("qwen2.5:7b-instruct" if provider == "ollama" else "gpt-4o-mini")
    from autogen_ext.models.openai import OpenAIChatCompletionClient
    if provider == "ollama":
        host = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")
        return OpenAIChatCompletionClient(
            model=model_id, base_url=f"{host}/v1", api_key="ollama",
            model_info={"family": "unknown", "function_calling": True, "vision": False,
                        "json_output": False, "structured_output": False})
    return OpenAIChatCompletionClient(model=model_id)


def _run(instructions, task):
    from autogen_agentchat.agents import AssistantAgent
    agent = AssistantAgent("hb", model_client=_client(), system_message=instructions)

    async def go():
        return await agent.run(task=task)

    res = asyncio.run(go())
    for m in reversed(getattr(res, "messages", []) or []):
        c = getattr(m, "content", None)
        if isinstance(c, str) and c.strip():
            return c
    return str(res)


def execute(payload):
    ctx = payload.get("context", "")
    cwd = payload.get("cwd") or os.getcwd()
    try:
        text = _run("You are a HeartBeat Stage-B worker. Do exactly one task, then stop. Emit each file "
                    "as a block:\n===FILE: relative/path===\n<content>\n===END===\nNever touch .hb/ or gate.sh.",
                    f"{ctx}\n\nCreate the required file(s) now as FILE blocks.")
    except Exception as e:
        return {"ok": False, "summary": f"autogen unavailable ({e})"}
    written = write_blocks(text, cwd)
    return {"ok": len(written) > 0, "summary": f"autogen ran ({len(written)} block writes)"}


def refute(payload):
    ctx = payload.get("context", "")
    try:
        text = _run("You are a skeptical adversarial reviewer. End your reply with a final line containing only the verdict, REFUTED if you found a hole or CLEAR if you could not, with nothing else on that line.",
                    f'{payload.get("prompt", "Refute.")}\n\nContext:\n{ctx}')
    except Exception as e:
        return {"error": f"autogen unavailable ({e})"}
    return refute_result(str(text))
