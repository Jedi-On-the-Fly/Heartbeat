# Use HeartBeat with Agno

**Outcome:** run a HeartBeat project with an Agno agent as the worker — keeping Agno's speed and
native tools, gaining behavioral gates, refutation, recovery, and cheap ticks.

## What Agno owns, what HeartBeat owns

Agno is a fast agent framework with native tools (like `FileTools`). It's the **reasoner and
executor** for one unit of work. HeartBeat is the deterministic harness *around* it: the DAG of
phases → tasks → **behavioral gates** decides what must become true, in what order, and whether
it actually happened. One HeartBeat task = one Agno agent run; you don't rewrite the agent, you
make it Stage B and gain verification ([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md)).

## Do it

```bash
HB_EXEC_BACKEND=agno HB_EXEC_PROVIDER=ollama HB_EXEC_MODEL=qwen2.5:7b-instruct \
  hb exec run --dir myproject          # local, no API key
# or: HB_EXEC_PROVIDER=anthropic (with ANTHROPIC_API_KEY)
```

`pip install "./py[agno]"`. The adapter builds an Agno model from the provider —
`agno.models.ollama.Ollama` (whose client honors `OLLAMA_HOST`), or Anthropic with a key — so
provider/model is HeartBeat's standard `HB_EXEC_*` env.

## Bring your own agent

The shipped adapter (`py/src/heartbeat/backends/agno.py`) wraps a generic Agno agent with
`FileTools`. To drive **your** agent, edit its `execute(payload)` to run your `Agent` on the
task — `payload["context"]` is the brief, `payload["cwd"]` the working dir; return
`{"ok": bool, "summary": str}`. It's a small, replaceable file, not zero-code; a custom adapter
is validated like any backend ([build-and-test-a-backend.md](build-and-test-a-backend.md)), and
the gate-is-contract lets you swap agent → another framework without touching the DAG
([swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md)).

## Gotcha

Agno writes files with its **native `FileTools`** (not HeartBeat's FILE-block protocol) — the
agent edits the working directory directly, and the gate verifies the result. Keep the agent
pointed at the project dir; it must not touch `.hb/`.

## Proof (reproducible)

Live behavior needs a real model, so it's proven in a **pinned Docker image** (isolated deps,
re-runnable) — see [tests/frameworks/](../../tests/frameworks/):

```bash
bash tests/frameworks/run.sh agno         # build the pinned image + drive it against local Ollama
```

The recorded version · model · date · verdict is in
[tests/frameworks/RESULTS.md](../../tests/frameworks/RESULTS.md). The deterministic contract —
the adapter conforms and degrades without the framework — is suite-enforced; the Docker run is
the on-demand live tier and never gates the suite.
