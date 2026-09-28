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
    import re as _r
    toks = _r.findall(r"REFUTED|CLEAR", (t or "").upper())
    return bool(toks) and toks[-1] == "REFUTED"
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
        emit({"refuted": False, "findings": f"crewai unavailable ({e})"} if mode == "refute"
             else {"ok": False, "summary": f"crewai unavailable ({e})"})
        return

    if mode == "refute":
        reviewer = Agent(role="Skeptical adversarial reviewer",
                         goal="Find a real hole in the claimed phase completion",
                         backstory="You refuse to rubber-stamp: you hunt hollow tests and faked output.",
                         llm=llm, verbose=False)
        task = Task(description=f'{payload.get("prompt", "Refute that the phase is complete.")}\n\n'
                                f"Context:\n{ctx}\n\nEnd with exactly one token: REFUTED or CLEAR.",
                    agent=reviewer, expected_output="REFUTED or CLEAR, with reasons.")
        try:
            out = str(Crew(agents=[reviewer], tasks=[task], verbose=False).kickoff())
            emit({"refuted": _verdict(out), "findings": out[:20000]})
        except Exception as e:
            emit({"refuted": False, "findings": f"reviewer error: {e}"})
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
