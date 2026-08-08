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

## agno

- version: agno==2.8.7 openai==2.53.0 ollama==0.6.2
- model: qwen2.5:7b-instruct (Ollama, keyless)
- date: 2026-08-08
- verdict: phase-complete — strict gate passed (`produced=true structural=true behavioral=true`)

Note: agno's Ollama model class needs the `ollama` client — added to the `[agno]` extra and the
pin. The real Agno agent (native `FileTools`) wrote a working `greet`.

## openai-agents

- version: openai-agents==0.19.4
- model: qwen2.5:7b-instruct (Ollama's OpenAI-compatible /v1, keyless)
- date: 2026-08-08
- verdict: phase-complete — strict gate passed (`produced=true structural=true behavioral=true`)

## autogen

- version: autogen-agentchat==0.7.5 autogen-ext[openai]==0.7.5
- model: qwen2.5:7b-instruct (Ollama's OpenAI-compatible /v1, keyless)
- date: 2026-08-08
- verdict: wiring-ok — the real AutoGen `AssistantAgent` ran and wrote a FILE-block
  (`execute` → `{ok:true, "1 block writes"}`), but this run's 7B output missed the strict
  `greet('Ada')` gate (model-luck, not a wiring failure). The path is proven end to end.

## smolagents

- version: smolagents==1.26.0 openai==2.53.0
- model: qwen2.5:7b-instruct (Ollama's OpenAI-compatible /v1, keyless)
- date: 2026-08-08
- verdict: phase-complete — strict gate passed (`produced=true structural=true behavioral=true`)

## pydantic-ai

- version: pydantic-ai==2.27.0
- model: qwen2.5:7b-instruct (Ollama's OpenAI-compatible /v1, keyless)
- date: 2026-08-08
- verdict: phase-complete — strict gate passed (`produced=true structural=true behavioral=true`)
