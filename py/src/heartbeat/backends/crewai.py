"""CrewAI backend (in-process). LLM provider anthropic|ollama; FILE-block writing.
A HeartBeat task is NOT a CrewAI Task — one HeartBeat task = one Agent+Task+Crew run."""
import os
from ._fileblocks import write_blocks


def _llm():
    provider = os.environ.get("HB_EXEC_PROVIDER", "anthropic").lower()
    model_id = os.environ.get("HB_EXEC_MODEL") or ("qwen2.5:7b-instruct" if provider == "ollama" else "claude-sonnet-4-6")
    from crewai import LLM
    if provider == "ollama":
        return LLM(model=f"ollama/{model_id}", base_url=os.environ.get("OLLAMA_HOST", "http://localhost:11434"))
    return LLM(model=model_id if "/" in model_id else f"anthropic/{model_id}")


def execute(payload):
    ctx = payload.get("context", "")
    cwd = payload.get("cwd") or os.getcwd()
    try:
        from crewai import Agent, Task, Crew
        llm = _llm()
    except Exception as e:
        return {"ok": False, "summary": f"crewai unavailable ({e})"}
    worker = Agent(role="HeartBeat Stage-B worker", goal="Complete exactly one task so its phase gate passes",
                   backstory="You work in the current directory and never touch .hb/ or gate.sh.", llm=llm, verbose=False)
    task = Task(description=(f"{ctx}\n\nCreate the required file(s) with RELATIVE paths. Emit each file as a block:\n"
                             "===FILE: relative/path.ext===\n<the COMPLETE file content>\n===END==="),
                agent=worker, expected_output="The one task is complete and the phase gate would pass.")
    try:
        out = str(Crew(agents=[worker], tasks=[task], verbose=False).kickoff())
        fb = write_blocks(out, cwd)
        return {"ok": True, "summary": f"crewai ran ({len(fb)} block-fallback)"}
    except Exception as e:
        return {"ok": False, "summary": f"crewai run failed: {e}"}


def refute(payload):
    ctx = payload.get("context", "")
    try:
        from crewai import Agent, Task, Crew
        llm = _llm()
    except Exception as e:
        return {"error": f"crewai unavailable ({e})"}
    rev = Agent(role="Skeptical adversarial reviewer", goal="Find a real hole in the claimed completion",
                backstory="You refuse to rubber-stamp.", llm=llm, verbose=False)
    task = Task(description=f'{payload.get("prompt", "Refute.")}\n\nContext:\n{ctx}\n\nEnd with REFUTED or CLEAR.',
                agent=rev, expected_output="REFUTED or CLEAR.")
    try:
        out = str(Crew(agents=[rev], tasks=[task], verbose=False).kickoff())
        return {"refuted": "REFUTED" in out.upper(), "findings": out[:500]}
    except Exception as e:
        return {"error": f"reviewer error: {e}"}
