# Framework live-run results

Captured outcomes from `tests/frameworks/run.sh <framework>` — the real framework driving the
real HeartBeat adapter + gate against local Ollama, in the pinned Docker image. Re-run any row
to reproduce it. These are the on-demand **live** tier; they do not gate the suite (see
[README.md](README.md)). `verdict` records whether the strict behavioral gate also passed —
a small local model can miss it by luck, which does not mean the wiring is broken.

## crewai

- version: crewai==1.15.13
- model: qwen2.5:7b-instruct (Ollama, keyless)
- date: 2026-08-08
- verdict: phase-complete — strict gate passed (`produced=true structural=true behavioral=true`)

The real CrewAI `Agent + Task + Crew` run, dispatched through the `crewai` backend, produced a
`greeting.py` whose `greet('Ada')` returns `"Hello, Ada!"` — the behavioral gate passed
end to end.

## langgraph

- version: langgraph==1.2.10 langchain-ollama==1.1.0
- model: qwen2.5:7b-instruct (Ollama, keyless)
- date: 2026-08-08
- verdict: phase-complete — strict gate passed (`produced=true structural=true behavioral=true`)

The real LangGraph ReAct agent (with the `save_file` tool), dispatched through the `langgraph`
backend, produced a `greeting.py` whose `greet('Ada')` returns `"Hello, Ada!"` — the behavioral
gate passed end to end.
