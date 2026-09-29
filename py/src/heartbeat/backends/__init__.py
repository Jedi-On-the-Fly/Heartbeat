"""In-process backend registry. Each backend exposes execute(payload)->{ok,summary}
and refute(payload)->{refuted,findings}. payload carries `context`, `cwd`, `task`.

For arbitrary/external backends, the executor uses a subprocess wire protocol instead
(HB_EXEC_CMD / backend `script`) — those never reach this registry.
"""
import importlib
import re as _re


def verdict_of(text):
    """A model reviewer's verdict — True (REFUTED) / False (CLEAR) — only when a whole-word, upper-case
    REFUTED/CLEAR is the reply's FINAL word (only punctuation/markup after it) and stands alone: after a
    sentence end or a label on its line ("… done. CLEAR", "**Verdict:** REFUTED"), or at a line start
    after a finished sentence, a heading, a label or a blank line. Anything else — no token, text after
    it ("CLEAR would be premature"), a token inside a sentence ("NOT yet CLEAR", a hard-wrapped
    "not\\nCLEAR"), a copied template ("REFUTED | CLEAR", "* REFUTED\\n* CLEAR") — is None (fail-closed).
    A reply that argues one way and ends with the other token explicitly is still read as that token."""
    _r = _re
    t = text
    t = (t or "").rstrip()
    m = _r.search(r"\b(REFUTED|CLEAR)\b[\s*_`\"'\u201c\u201d.!)\]]*$", t)
    if not m:
        return None   # no token, or text after it: the verdict must be the reply's final word
    lines = t[:m.start()].split("\n")
    pre = _r.sub(r"^\s*(?:[-*+\u2022]|\d+[.)])\s+", "", lines[-1])            # a list bullet
    pre = _r.sub(r"[\s*_`#>\"'\u201c\u201d]+", " ", pre).strip()
    if pre:   # mid-line: only after a sentence end or a label ("… done. CLEAR", "Verdict: REFUTED")
        if not _r.search(r"(?:[.!?:;\u2014\u2013]|\s-)$", pre):
            return None
    elif len(lines) > 1 and lines[-2].strip():   # line start: the line before must end a sentence,
        q = _r.sub(r"[\s*_`>\"'\u201c\u201d]+$", "", lines[-2])   # or be a heading / a label
        if not (q.lstrip().startswith("#") or _r.search(r"[.!?:;)\]]$", q)):
            return None
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
