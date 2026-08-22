# Run HeartBeat fully locally

**Outcome:** run HeartBeat end to end with **no cloud, no API key, and no Claude Code** — the
pure-Python port driving a local model. Everything stays on your machine.

This is the offline story: `pip install`, the Python runtime, and a local Ollama model as the
worker. The DAG, gates, and refutation are identical to any other setup; only the environment
is local.

## Do it

```bash
pip install -e py                 # the pure-Python port; stdlib-only core, no node
ollama pull qwen2.5:7b-instruct          # a local model to be the worker

hb init myproject
hb audit --dir myproject                 # refuse hollow gates before running
HB_EXEC_BACKEND=ollama HB_EXEC_MODEL=qwen2.5:7b-instruct hb exec run --dir myproject
```

No API key is set, nothing leaves the machine. The `ollama` backend is stdlib-only (it just
talks to the local Ollama server), so the core install pulls no extra dependencies.

## What "fully local" means

- **No node / no Claude Code.** The Python port implements Stage A, the resolver, the gates,
  the state projector, and the executor. Pick it over the plugin when you're outside Claude
  Code — see [choose-runtime.md](choose-runtime.md).
- **Gates can be Python too.** A gate `cmd` is any shell one-liner, so
  `python3 -c "import mymod; assert mymod.works()"` is a perfectly good gate — no node anywhere
  in the loop.
- **No key, offline.** A local model means no provider, no network, no per-token cost — the
  worker runs on your hardware. Backend details and expectations are in
  [use-heartbeat-with-ollama.md](use-heartbeat-with-ollama.md).

## Realistic expectations

A small local model (3B–7B) clears simple, well-scoped tasks; hard tasks want a bigger model or
tighter task sizing. That's fine — the gates make a weak worker *safe*: the worst it can do is
fail a gate, never fake a pass. Size tasks accordingly and let the tick spend the model only
when there's real work.

## Prove it worked

The port ships a fully node/bash-free end-to-end run — a local model writes `greeting.py` and a
Python gate imports and runs it:

```bash
python3 py/real-backend.py ollama qwen2.5:7b-instruct
```

This is a live run (a real model), so it's a capability check, not a deterministic suite test.
