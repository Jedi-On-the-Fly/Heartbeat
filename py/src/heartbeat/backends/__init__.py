"""In-process backend registry. Each backend exposes execute(payload)->{ok,summary}
and refute(payload)->{refuted,findings}. payload carries `context`, `cwd`, `task`.

For arbitrary/external backends, the executor uses a subprocess wire protocol instead
(HB_EXEC_CMD / backend `script`) — those never reach this registry.
"""
import importlib
import re as _re


def verdict_of(text):
    """A model reviewer's verdict — True (REFUTED) / False (CLEAR) — else None (fail-closed). The contract
    (py/tests/verdict_cases.json): the reply's last non-empty line is ONLY the verdict — optional
    **/`/_ markup, an optional "Verdict:" / "Final verdict —" label, the upper-case token, optional
    "." or "!" — and the nearest earlier non-empty line neither begins with a verdict token nor ends with one
    after a separator (a stacked or listed template; "… or CLEAR." inside a sentence does not count). Anything else is no verdict. Whitespace is space/tab. A last line that is only
    a token is read at face value, whatever the reply argued before it."""
    t = text
    import re as _r
    A = ("[ \t]*[*_\x60]*(?:(?:[Ff]inal[ \t]+)?(?:[Vv]erdict|VERDICT)[*_\x60]*[ \t]*[:\u2014\u2013-][ \t*_\x60]*)?"
         "[\"'\u201c\u201d]?(REFUTED|CLEAR)[\"'\u201c\u201d]?[*_\x60]*[.!]?[*_\x60]*[ \t]*")
    P = ("[ \t]*(?:(?:[-*+]|[0-9]+[.)])[ \t]+)?[ \t*_\x60]*(?:(?:[Ff]inal[ \t]+)?(?:[Vv]erdict|VERDICT)[*_\x60]*[ \t]*"
         "[:\u2014\u2013-][ \t*_\x60]*)?[\"'\u201c\u201d]?(?:REFUTED|CLEAR)(?![A-Za-z0-9_])")
    E = ("(?:^|[.!?:;|/\u2014\u2013-])[ \t*_\x60\"'\u201c\u201d]*(?:REFUTED|CLEAR)"
         "[\"'\u201c\u201d*_\x60.!?:;)\\]]*[ \t]*$")
    lines = [ln.rstrip(" \t\r") for ln in (t or "").split("\n")]
    while lines and not lines[-1]:
        lines.pop()
    m = _r.fullmatch(A, lines[-1]) if lines else None
    if not m:
        return None
    k = len(lines) - 2
    while k >= 0 and not lines[k]:
        k -= 1
    if k >= 0 and (_r.match(P, lines[k]) or _r.search(E, lines[k])):
        return None   # the line before also begins or ends with a verdict: a stacked / listed template
    return m.group(1) == "REFUTED"


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
