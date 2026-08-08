# Use HeartBeat with smolagents

**Outcome:** run a HeartBeat project with a smolagents agent as the worker — keeping its
code/tool-calling style, gaining behavioral gates, refutation, recovery, and cheap ticks.

## A code-writing agent pairs naturally with a behavioral gate

smolagents agents *write and call code* to get things done — the execution of one unit of work.
That's a perfect match for HeartBeat's core move: the agent produces the work, and HeartBeat's
**behavioral gate** verifies the *outcome* — does the code actually do the thing, not just "the
agent said done" ([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md)). One HeartBeat task =
one smolagents run; HeartBeat sequences tasks across phases and proves each result.

## Do it

```bash
HB_EXEC_BACKEND=smolagents HB_EXEC_PROVIDER=ollama HB_EXEC_MODEL=qwen2.5:7b-instruct \
  hb exec run --dir myproject          # local, keyless — Ollama's OpenAI-compatible /v1
# or: HB_EXEC_PROVIDER=openai (with OPENAI_API_KEY; default model gpt-4o-mini)
```

`pip install "./py[smolagents]"`. The adapter builds a smolagents `OpenAIServerModel` from the
provider and runs a `ToolCallingAgent` with a `save_file` tool.

## Bring your own agent

The shipped adapter (`py/src/heartbeat/backends/smolagents.py`) wraps a generic
`ToolCallingAgent`. To drive **your** agent (e.g. a `CodeAgent` with your tools), edit its
`execute(payload)` to run your agent on the task — `payload["context"]` is the brief,
`payload["cwd"]` the working dir; return `{"ok": bool, "summary": str}`. Small, replaceable file
— not zero-code; validated like any backend
([build-and-test-a-backend.md](build-and-test-a-backend.md)) and swappable without touching the
DAG ([swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md)).

## Gotcha

The model is a smolagents **`OpenAIServerModel`** pointed at the provider's endpoint — the
`ollama` provider uses Ollama's OpenAI-compatible `/v1` (keyless). Let the gate check the code's
behavior, not that a file exists ([writing-behavioral-gates.md](writing-behavioral-gates.md)).

## Proof (reproducible)

Live behavior needs a real model, so it's proven in a **pinned Docker image** (isolated deps,
re-runnable) — see [tests/frameworks/](../../tests/frameworks/):

```bash
bash tests/frameworks/run.sh smolagents   # build the pinned image + drive it against local Ollama
```

The recorded version · model · date · verdict is in
[tests/frameworks/RESULTS.md](../../tests/frameworks/RESULTS.md). The deterministic contract is
suite-enforced; the Docker run is the on-demand live tier and never gates the suite.
