#!/usr/bin/env python3
"""HeartBeat executor backend: CrewAI (https://github.com/crewAIInc/crewAI).

Wire protocol (shared by every HeartBeat backend):
    driver -> backend:  argv[1] = "execute" | "refute" | "author" ; stdin = payload JSON
    backend -> driver:  ONE JSON object on stdout
        execute -> {"ok": bool,      "summary":  str}
        refute  -> {"refuted": bool, "findings": str}

NAMING: a HeartBeat *task* is NOT a CrewAI *Task*. Here ONE HeartBeat task maps to a
single CrewAI Agent + Task in a one-member Crew. For `execute` the agent gets a real
file-writer tool when `crewai_tools` is installed; either way, any ===FILE=== blocks in
its output are honored as a fallback. It NEVER touches .hb/ or gate.sh. Degrades to
protocol-valid JSON if `crewai` isn't installed.

Provider: HB_EXEC_PROVIDER = anthropic (default) | ollama.
Model:    HB_EXEC_MODEL (default: claude-sonnet-4-6, or qwen2.5:7b-instruct for ollama).
"""
import re
import sys, os, json


try:
    from _fileblocks import author_reply
except Exception:
    def author_reply(text):
        return {"ok": False, "error": "the author helper (_fileblocks.author_reply) is unavailable"}

def _verdict(t):
    """The reviewer's verdict — True (REFUTED) / False (CLEAR) — else None (fail-closed). The contract
    (py/tests/verdict_cases.json): the reply's last non-empty line is ONLY the verdict — optional
    **/`/_ markup, an optional "Verdict:" / "Final verdict —" label, the upper-case token, optional
    "." or "!" — and the nearest earlier non-empty line neither begins with a verdict token nor ends with one
    after a separator (a stacked or listed template; "… or CLEAR." inside a sentence does not count). Anything else is no verdict. Whitespace is space/tab. A last line that is only
    a token is read at face value, whatever the reply argued before it."""
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


def _refute_result(text):
    """A verdict only when the reviewer gave one. No final REFUTED/CLEAR token is not a CLEAR:
    it is an error, which the driver escalates (fail-closed)."""
    text = str(text or "")
    if sys.argv[1:2] == ["author"]:          # author mode reuses this path: its reply is a constraint
        return {"refuted": False, "findings": text[:20000]}   # array, parsed by author_reply (fail-closed)
    v = _verdict(text)
    if v is None:
        return {"error": "no verdict line at the end of the reviewer's reply (fail-closed); the reply ends: " + text[-300:]}
    return {"refuted": v, "findings": text[:20000]}
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from _fileblocks import write_blocks
except Exception:
    def write_blocks(text, cwd=None):
        return []

# Guarantee ONLY the protocol JSON lands on stdout: keep the real stdout fd, then point
# fd 1 at stderr so CrewAI's banners/telemetry can't corrupt the JSON line.
_STDOUT_FD = os.dup(1)
os.dup2(2, 1)


def emit(obj):
    os.write(_STDOUT_FD, (json.dumps(obj) + "\n").encode())


def make_llm(provider, model_id):
    from crewai import LLM
    if provider == "ollama":
        return LLM(model=f"ollama/{model_id}",
                   base_url=os.environ.get("OLLAMA_HOST", "http://localhost:11434"))
    # anthropic via LiteLLM naming (e.g. anthropic/claude-...); pass through as given
    return LLM(model=model_id if "/" in model_id else f"anthropic/{model_id}")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "execute"
    # Constraint-first review: `author` runs the refute path on the author prompt, then converts the
    # reply to {"ok", "constraints"} (fail-closed). Any other unknown mode is REFUSED — it must never
    # fall through to execute (which writes files).
    global emit
    if mode not in ("execute", "refute", "author"):
        emit({"error": f"unsupported mode {mode!r} (execute | refute | author)"})
        return
    if mode == "author":
        _emit_raw = emit
        emit = lambda obj: _emit_raw(author_reply((obj or {}).get("findings", "") if isinstance(obj, dict) else ""))  # noqa: E731
        mode = "refute"
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}
    ctx = payload.get("context", "")
    provider = os.environ.get("HB_EXEC_PROVIDER", "anthropic").lower()
    model_id = os.environ.get("HB_EXEC_MODEL") or ("qwen2.5:7b-instruct" if provider == "ollama" else "claude-sonnet-4-6")

    try:
        from crewai import Agent, Task, Crew
        llm = make_llm(provider, model_id)
    except Exception as e:  # crewai (or its deps) not installed → graceful degrade
        emit({"error": f"crewai unavailable ({e})"} if mode == "refute"
             else {"ok": False, "summary": f"crewai unavailable ({e})"})
        return

    if mode == "refute":
        reviewer = Agent(role="Skeptical adversarial reviewer",
                         goal="Find a real hole in the claimed phase completion",
                         backstory="You refuse to rubber-stamp: you hunt hollow tests and faked output.",
                         llm=llm, verbose=False)
        task = Task(description=f'{payload.get("prompt", "Refute that the phase is complete.")}\n\n'
                                f"Context:\n{ctx}\n\nEnd your reply with a final line containing only the verdict, REFUTED if you found a hole or CLEAR if you could not, with nothing else on that line.",
                    agent=reviewer, expected_output="Reasons, then a final line that is only the verdict: REFUTED or CLEAR.")
        try:
            out = str(Crew(agents=[reviewer], tasks=[task], verbose=False).kickoff())
            emit(_refute_result(out))
        except Exception as e:
            emit({"error": f"reviewer error: {e}"})
        return

    # execute — real file-writer tool if available, plus the FILE-block fallback
    tools = []
    try:
        from crewai_tools import FileWriterTool
        tools = [FileWriterTool()]
    except Exception:
        tools = []
    worker = Agent(role="HeartBeat Stage-B worker",
                   goal="Complete exactly one task so its phase gate passes",
                   backstory="You work in the current directory and never touch .hb/ or gate.sh.",
                   llm=llm, tools=tools, verbose=False)
    instr = (f"{ctx}\n\nCreate the required file(s) with RELATIVE paths in the current directory. "
             "If you have a file-writer tool, use it. Otherwise emit each file as a block:\n"
             "===FILE: relative/path.ext===\n<the COMPLETE file content>\n===END===")
    task = Task(description=instr, agent=worker,
                expected_output="The one task is complete and the phase gate would pass.")
    try:
        out = str(Crew(agents=[worker], tasks=[task], verbose=False).kickoff())
        fb = write_blocks(out)   # fallback: honor any ===FILE=== blocks in the output
        emit({"ok": True, "summary": f"crewai crew ran ({'tool' if tools else 'no-tool'} + {len(fb)} block-fallback)"})
    except Exception as e:
        emit({"ok": False, "summary": f"crewai run failed: {e}"})


if __name__ == "__main__":
    main()
