#!/usr/bin/env python3
"""HeartBeat executor backend: CrewAI (https://github.com/crewAIInc/crewAI).

Wire protocol (shared by every HeartBeat backend):
    driver -> backend:  argv[1] = "execute" | "refute" ; stdin = payload JSON
    backend -> driver:  ONE JSON object on stdout
        execute -> {"ok": bool,      "summary":  str}
        refute  -> {"refuted": bool, "findings": str}

NAMING: a HeartBeat *task* is NOT a CrewAI *Task*. Here ONE HeartBeat task maps to a
single CrewAI Agent + Task run inside a one-member Crew. The backend works in the
current directory and NEVER touches .hb/ or gate.sh — the driver mediates all state.
Degrades to protocol-valid JSON if the `crewai` package isn't installed.
"""
import sys, os, json


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "execute"
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}

    try:
        from crewai import Agent, Task, Crew
    except Exception as e:  # crewai not installed → graceful, protocol-valid degrade
        if mode == "refute":
            emit({"refuted": False, "findings": f"crewai not installed ({e})"})
        else:
            emit({"ok": False, "summary": f"crewai not installed ({e})"})
        return

    ctx = payload.get("context", "")

    if mode == "refute":
        prompt = payload.get("prompt", "Refute that the phase is complete.")
        reviewer = Agent(
            role="Skeptical adversarial reviewer",
            goal="Find a real hole in the claimed phase completion",
            backstory="You refuse to rubber-stamp: you hunt hollow tests and faked output.",
            verbose=False,
        )
        task = Task(
            description=f"{prompt}\n\nContext:\n{ctx}\n\nEnd with the token REFUTED or CLEAR.",
            agent=reviewer,
            expected_output="REFUTED or CLEAR, with reasons.",
        )
        try:
            out = str(Crew(agents=[reviewer], tasks=[task], verbose=False).kickoff())
            emit({"refuted": "REFUTED" in out.upper(), "findings": out[:500]})
        except Exception as e:
            emit({"refuted": False, "findings": f"reviewer error: {e}"})
    else:
        worker = Agent(
            role="HeartBeat Stage-B worker",
            goal="Complete exactly one task so its phase gate passes",
            backstory="You work in the current directory and never touch .hb/ or gate.sh.",
            verbose=False,
        )
        task = Task(
            description=ctx,
            agent=worker,
            expected_output="The one task is complete and the phase gate would pass.",
        )
        try:
            Crew(agents=[worker], tasks=[task], verbose=False).kickoff()
            emit({"ok": True, "summary": "crewai crew completed the task"})
        except Exception as e:
            emit({"ok": False, "summary": f"crewai run failed: {e}"})


if __name__ == "__main__":
    main()
