# Use HeartBeat with AutoGen

**Outcome:** run a HeartBeat project with an AutoGen agent (or group chat) as the worker —
keeping the conversation, gaining behavioral gates, refutation, recovery, and cheap ticks.

## Isn't HeartBeat another conversation orchestrator? No — different altitude

AutoGen orchestrates a **multi-agent conversation** to solve a problem — the reasoning inside one
unit of work. HeartBeat doesn't run a conversation; it runs the DAG *around* it: phases → tasks →
**behavioral gates**, deciding what must become true across the project and verifying it (never
trusting the agents' say-so — [keep-stage-b-untrusted.md](keep-stage-b-untrusted.md)). One
HeartBeat task = one AutoGen agent/group-chat run. Your conversation stays; HeartBeat schedules
across tasks and proves each result.

## Do it

```bash
HB_EXEC_BACKEND=autogen HB_EXEC_PROVIDER=ollama HB_EXEC_MODEL=qwen2.5:7b-instruct \
  hb exec run --dir myproject          # local, keyless — Ollama's OpenAI-compatible /v1
# or: HB_EXEC_PROVIDER=openai (with OPENAI_API_KEY; default model gpt-4o-mini)
```

`pip install "./py[autogen]"` (pulls `autogen-agentchat` + `autogen-ext[openai]`). The adapter
builds an `OpenAIChatCompletionClient` from the provider and runs an `AssistantAgent`.

## Bring your own agents

The shipped adapter (`py/src/heartbeat/backends/autogen.py`) wraps a single `AssistantAgent`. To
drive **your** team (e.g. a group chat), edit its `execute(payload)` to run your AutoGen setup on
the task — `payload["context"]` is the brief, `payload["cwd"]` the working dir; return
`{"ok": bool, "summary": str}`. Small, replaceable file — not zero-code; validated like any
backend ([build-and-test-a-backend.md](build-and-test-a-backend.md)) and swappable without
touching the DAG ([swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md)).

## Gotcha

AutoGen is split into **`autogen-agentchat`** (the agents) and **`autogen-ext[openai]`** (the
model client) — the extra pulls both. The `ollama` provider points the OpenAI client at Ollama's
`/v1` endpoint (keyless); the agent writes files via a FILE-block the adapter honors.

## Proof (reproducible)

Live behavior needs a real model, so it's proven in a **pinned Docker image** (isolated deps,
re-runnable) — see [tests/frameworks/](../../tests/frameworks/):

```bash
bash tests/frameworks/run.sh autogen      # build the pinned image + drive it against local Ollama
```

The recorded version · model · date · verdict is in
[tests/frameworks/RESULTS.md](../../tests/frameworks/RESULTS.md). The deterministic contract is
suite-enforced; the Docker run is the on-demand live tier and never gates the suite.
