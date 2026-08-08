# Use HeartBeat with pydantic-ai

**Outcome:** run a HeartBeat project with a pydantic-ai agent as the worker — keeping typed,
validated outputs, gaining behavioral gates, refutation, recovery, and cheap ticks.

## Two validation layers that complement, not compete

pydantic-ai's strength is **structural validation**: the agent's output is typed and validated
against a schema. HeartBeat's strength is **behavioral validation**: the gate proves the work
*does the thing* (the endpoint returns 200, `greet('Ada')` is right) — not just that the output
has the right shape. They stack: pydantic-ai guarantees the *form* of one task's output;
HeartBeat guarantees the *behavior* across the project and never trusts the agent's own verdict
([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md)). One HeartBeat task = one pydantic-ai
agent run.

## Do it

```bash
HB_EXEC_BACKEND=pydantic-ai HB_EXEC_PROVIDER=ollama HB_EXEC_MODEL=qwen2.5:7b-instruct \
  hb exec run --dir myproject          # local, keyless — Ollama's OpenAI-compatible /v1
# or: HB_EXEC_PROVIDER=openai (with OPENAI_API_KEY; default model gpt-4o-mini)
```

`pip install "./py[pydantic-ai]"`. The adapter builds a pydantic-ai model from the provider and
runs an `Agent` with a `save_file` tool.

## Bring your own agent

The shipped adapter (`py/src/heartbeat/backends/pydanticai.py`) wraps a generic `Agent`. To
drive **your** typed agent, edit its `execute(payload)` to run your `Agent` on the task —
`payload["context"]` is the brief, `payload["cwd"]` the working dir; return
`{"ok": bool, "summary": str}`. Small, replaceable file — not zero-code; validated like any
backend ([build-and-test-a-backend.md](build-and-test-a-backend.md)) and swappable without
touching the DAG ([swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md)).

## Gotcha

pydantic-ai renamed its OpenAI model class (`OpenAIModel` → `OpenAIChatModel`) across versions —
the adapter targets the current one, which is why the live proof is **pinned** (see the version
in RESULTS.md). The `ollama` provider uses an OpenAI-compatible model against Ollama's `/v1`.

## Proof (reproducible)

Live behavior needs a real model, so it's proven in a **pinned Docker image** (isolated deps,
re-runnable) — see [tests/frameworks/](../../tests/frameworks/):

```bash
bash tests/frameworks/run.sh pydantic-ai   # build the pinned image + drive it against local Ollama
```

The recorded version · model · date · verdict is in
[tests/frameworks/RESULTS.md](../../tests/frameworks/RESULTS.md). The deterministic contract is
suite-enforced; the Docker run is the on-demand live tier and never gates the suite.
