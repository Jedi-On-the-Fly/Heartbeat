"""In-process backend registry. Each backend exposes execute(payload)->{ok,summary}
and refute(payload)->{refuted,findings}. payload carries `context`, `cwd`, `task`.

For arbitrary/external backends, the executor uses a subprocess wire protocol instead
(HB_EXEC_CMD / backend `script`) — those never reach this registry.
"""
import importlib
import re as _re


def verdict_of(text):
    """A model reviewer's verdict: the reply's FINAL whole-word, upper-case REFUTED/CLEAR — True / False —
    but only when that token stands alone: at the start of a line, or right after a sentence end or a
    label (". CLEAR", "Verdict: REFUTED", "— CLEAR"). The prompt itself contains 'REFUTED', so a
    grep-anywhere would misread a CLEAR reply; a token inside a sentence ("NOT yet CLEAR", "far from
    CLEAR", a copied template "REFUTED | CLEAR") is no verdict: None (fail-closed)."""
    t = text or ""
    ms = list(_re.finditer(r"\b(REFUTED|CLEAR)\b", t))
    if not ms:
        return None
    a = ms[-1]
    pre = _re.sub(r"[\s*_`#>\"'\u201c\u201d]+$", "", t[:a.start()].split("\n")[-1])
    if pre and not _re.search(r"(?:[.!?:;\u2014\u2013]|\s-)$", pre):
        return None
    return a.group(1) == "REFUTED"


def refute_result(text):
    """A verdict only when the reviewer gave one (node twin: _refute_result in the executors). No final
    REFUTED/CLEAR token is not a CLEAR: it is an error, which the driver escalates (fail-closed). The
    executor's author fallback reuses a backend's refute() and sets HB_REFUTE_RAW=1 so the raw reply
    (a constraint array, parsed by author_reply) passes through."""
    import os as _os
    text = str(text or "")
    if _os.environ.get("HB_REFUTE_RAW") == "1":
        return {"refuted": False, "findings": text[:20000]}
    v = verdict_of(text)
    if v is None:
        return {"error": "no REFUTED/CLEAR verdict in the reviewer's reply (fail-closed): " + text[:300]}
    return {"refuted": v, "findings": text[:20000]}

_KNOWN = {"ollama", "agno", "crewai", "claude", "claude-code", "langgraph", "openai-agents",
          "autogen", "smolagents", "pydantic-ai", "codex", "opencode"}
_MODULE = {"claude-code": "claude", "openai-agents": "openai_agents", "pydantic-ai": "pydanticai"}
_MODULES = {"ollama", "agno", "crewai", "claude", "langgraph", "openai_agents",
            "autogen", "smolagents", "pydanticai", "codex", "opencode"}


def get(name):
    mod = _MODULE.get(name, name)
    if mod not in _MODULES:
        raise ValueError(f"unknown in-process backend: {name} (set HB_EXEC_CMD for a custom command)")
    return importlib.import_module(f"heartbeat.backends.{mod}")
