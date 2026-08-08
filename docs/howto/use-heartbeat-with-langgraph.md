# Use HeartBeat with LangGraph

**Outcome:** run a HeartBeat project with a LangGraph agent as the worker — keeping your graph,
gaining behavioral gates, refutation, recovery, and cheap ticks.

## Isn't HeartBeat a redundant stateful graph? No — different graph, different layer

A LangGraph user's instinct is "I already have a stateful graph." The two graphs live at
different layers and don't overlap:

- **LangGraph is the *reasoning* control-flow inside one task.** Nodes are reasoning/tool steps,
  the graph is often cyclic, it's driven by the model, and its state is the in-memory
  conversation for that run.
- **HeartBeat is the *verification* control-flow across the project.** Its DAG is acyclic phases
  gated on *behavioral* checks; its state is an event-sourced, durable projection that survives a
  dead process and rebuilds ([recover-a-dead-or-corrupted-run.md](recover-a-dead-or-corrupted-run.md)).

One HeartBeat task = one LangGraph agent run. LangGraph decides *how to think through* a task;
HeartBeat decides *what must be true, in what order, and whether it actually happened* — and
never trusts the agent's own say-so ([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md)).

## Do it

```bash
HB_EXEC_BACKEND=langgraph HB_EXEC_PROVIDER=ollama HB_EXEC_MODEL=qwen2.5:7b-instruct \
  hb exec run --dir myproject          # local, no API key
# or: HB_EXEC_PROVIDER=openai | anthropic (with the matching key)
```

`pip install "./py[langgraph]"` (pulls `langgraph` + `langchain-ollama`). The adapter builds a
LangChain chat model from the provider — `ChatOllama` via `OLLAMA_HOST`, or `ChatOpenAI` /
`ChatAnthropic` — so provider/model is HeartBeat's standard `HB_EXEC_*` env.

## Bring your own graph

The shipped adapter (`py/src/heartbeat/backends/langgraph.py`) wraps a prebuilt ReAct agent
(`create_react_agent`) with a `save_file` tool. To drive **your** compiled graph, edit that
adapter's `execute(payload)` to invoke your graph on the task — `payload["context"]` is the
brief, `payload["cwd"]` the working dir; return `{"ok": bool, "summary": str}`. A custom adapter
is validated like any backend ([build-and-test-a-backend.md](build-and-test-a-backend.md)), and
the gate-is-contract means you can swap graph → another framework without touching the DAG
([swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md)).

## Gotcha

The provider needs its LangChain integration package — `langchain-ollama` for `ollama`
(bundled by the extra), `langchain-openai` / `langchain-anthropic` for the others. The adapter
imports lazily and degrades to protocol-valid JSON if a provider package is missing.

## Proof (reproducible)

Live behavior needs a real model, so it's proven in a **pinned Docker image**, re-runnable and
isolated from other frameworks' deps — see [tests/frameworks/](../../tests/frameworks/):

```bash
bash tests/frameworks/run.sh langgraph   # build the pinned image + drive it against local Ollama
```

Captured outcomes (version · model · date · verdict) are in
[tests/frameworks/RESULTS.md](../../tests/frameworks/RESULTS.md). The deterministic contract —
the adapter conforms and degrades without the framework — is suite-enforced; the Docker run is
the on-demand live tier and never gates the suite.
