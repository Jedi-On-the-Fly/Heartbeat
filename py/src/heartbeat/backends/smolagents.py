"""smolagents backend (in-process).

execute over a ToolCallingAgent with a save_file tool; refute is a model call. Provider
ollama via OpenAIServerModel (keyless) or openai. FILE-block fallback. Degrades to
protocol-valid JSON if smolagents isn't installed.
"""
import os

from ._fileblocks import write_blocks, norm_rel
from . import refute_result


def _model():
    provider = os.environ.get("HB_EXEC_PROVIDER", "openai").lower()
    model_id = os.environ.get("HB_EXEC_MODEL") or ("qwen2.5:7b-instruct" if provider == "ollama" else "gpt-4o-mini")
    from smolagents import OpenAIServerModel
    if provider == "ollama":
        host = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")
        return OpenAIServerModel(model_id=model_id, api_base=f"{host}/v1", api_key="ollama")
    return OpenAIServerModel(model_id=model_id)


def execute(payload):
    ctx = payload.get("context", "")
    cwd = payload.get("cwd") or os.getcwd()
    try:
        from smolagents import ToolCallingAgent, tool
        model = _model()
    except Exception as e:
        return {"ok": False, "summary": f"smolagents unavailable ({e})"}
    written = []

    @tool
    def save_file(path: str, content: str) -> str:
        """Write content to a file in the working directory.

        Args:
            path: relative file path
            content: the file contents
        """
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
        agent = ToolCallingAgent(tools=[save_file], model=model)
        out = agent.run(f"{ctx}\n\nCreate the required file(s) now using save_file with RELATIVE paths.")
        fb = write_blocks(str(out), cwd)
        n = len(written) + len(fb)
        return {"ok": n > 0, "summary": f"smolagents ran ({len(written)} tool writes + {len(fb)} block-fallback)"}
    except Exception as e:
        return {"ok": False, "summary": f"smolagents run failed: {e}"}


def refute(payload):
    ctx = payload.get("context", "")
    try:
        from smolagents import ToolCallingAgent
        model = _model()
    except Exception as e:
        return {"error": f"smolagents unavailable ({e})"}
    try:
        agent = ToolCallingAgent(tools=[], model=model)
        out = str(agent.run(f'{payload.get("prompt", "Refute.")}\n\nContext:\n{ctx}\n\nEnd with REFUTED or CLEAR.'))
        return refute_result(out)
    except Exception as e:
        return {"error": f"reviewer error: {e}"}
