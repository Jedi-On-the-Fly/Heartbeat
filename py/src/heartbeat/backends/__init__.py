"""In-process backend registry. Each backend exposes execute(payload)->{ok,summary}
and refute(payload)->{refuted,findings}. payload carries `context`, `cwd`, `task`.

For arbitrary/external backends, the executor uses a subprocess wire protocol instead
(HB_EXEC_CMD / backend `script`) — those never reach this registry.
"""
import importlib
import re as _re


def verdict_of(text):
    """A model reviewer's verdict — True (REFUTED) / False (CLEAR) — read from the reply's LAST non-empty line
    by an exact grammar, else None (fail-closed). The line is either (A) only the verdict: optional list
    bullet / markup, an optional "Verdict:" label, the upper-case token, optional "." / "!"; or (B) a
    finished sentence (ending ".", "!", "?") or a "verdict:" label, then the token as the final word —
    where that last sentence is not itself a bare verdict ("Verdict: REFUTED. CLEAR"). The nearest earlier
    non-empty line must not be a verdict line (a stacked or listed template), and for (A) an adjacent line
    before must end a sentence or be a heading or a label (a hard-wrapped "not\\nCLEAR"). Whitespace is
    space/tab only. A reply that argues one way and ends with a well-formed verdict line for the other is
    still read as that verdict."""
    t = text
    import re as _r
    A = ("[ \t]*(?:(?:[-*+]|[0-9]+[.)])[ \t]+)?[ \t*_\x60]*(?:(?:[Ff]inal[ \t]+)?(?:[Vv]erdict|VERDICT)[ \t*_\x60]*"
         "[:\u2014\u2013-])?[ \t*_\x60\"'\u201c\u201d]*(REFUTED|CLEAR)[ \t*_\x60\"'\u201c\u201d.!]*")
    B = ("([^\n]*[A-Za-z][^\n]*(?:[.!?][)\"'\u201d*_\x60]*|(?:[Vv]erdict|VERDICT)[ \t*_\x60]*[:\u2014\u2013-]))"
         "[ \t]+[*_\x60\"'\u201c]*(REFUTED|CLEAR)[*_\x60\"'\u201d.!]*[ \t]*")
    lines = [ln.rstrip(" \t\r") for ln in (t or "").split("\n")]
    while lines and not lines[-1]:
        lines.pop()
    if not lines:
        return None
    m = _r.fullmatch(A, lines[-1])
    bare = bool(m)
    if not m:
        m = _r.fullmatch(B, lines[-1])
        if not m or _r.fullmatch(A, _r.split(r"(?<=[.!?])[ \t]+", m.group(1))[-1]):
            return None
    k = len(lines) - 2
    while k >= 0 and not lines[k]:
        k -= 1
    if k >= 0:
        p = lines[k]
        if _r.fullmatch(A, p) or _r.fullmatch(B, p):
            return None   # another verdict line before it: a stacked / listed template
        if bare and k == len(lines) - 2 and not (p.lstrip(" \t").startswith("#") or
                                                  _r.search(r"[.!?:)\]][\"'\u201d*_\x60]*$", p)):
            return None   # a bare verdict line glued to an unfinished sentence ("…is not\\nCLEAR")
    return m.group(m.lastindex) == "REFUTED"


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
