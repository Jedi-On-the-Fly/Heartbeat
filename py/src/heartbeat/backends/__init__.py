"""In-process backend registry. Each backend exposes execute(payload)->{ok,summary}
and refute(payload)->{refuted,findings}. payload carries `context`, `cwd`, `task`.

For arbitrary/external backends, the executor uses a subprocess wire protocol instead
(HB_EXEC_CMD / backend `script`) — those never reach this registry.
"""
import importlib

_KNOWN = {"ollama", "agno", "crewai", "claude", "claude-code", "langgraph", "openai-agents",
          "autogen", "smolagents", "pydantic-ai", "codex"}
_MODULE = {"claude-code": "claude", "openai-agents": "openai_agents", "pydantic-ai": "pydanticai"}
_MODULES = {"ollama", "agno", "crewai", "claude", "langgraph", "openai_agents",
            "autogen", "smolagents", "pydanticai", "codex"}


def get(name):
    mod = _MODULE.get(name, name)
    if mod not in _MODULES:
        raise ValueError(f"unknown in-process backend: {name} (set HB_EXEC_CMD for a custom command)")
    return importlib.import_module(f"heartbeat.backends.{mod}")
