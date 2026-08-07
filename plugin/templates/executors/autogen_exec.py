#!/usr/bin/env python3
"""HeartBeat executor backend: AutoGen (autogen-agentchat).
Wire: argv[1]=execute|refute ; stdin=payload JSON ; stdout=ONE JSON line.
Provider HB_EXEC_PROVIDER=openai|ollama. FILE-block writing. Degrades if autogen absent."""
import sys, os, json, asyncio
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
        return {"refuted": False, "findings": f"autogen unavailable ({e})"}
    return {"refuted": "REFUTED" in str(text).upper(), "findings": str(text)[:500]}

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "execute"
    try: payload = json.load(sys.stdin)
    except Exception: payload = {}
    emit(do_refute(payload) if mode == "refute" else do_execute(payload))
if __name__ == "__main__": main()
