# Choose a Stage B backend

The backend is the worker that does the tasks. Because **the gate is the contract**, the choice
is reversible — the same DAG runs under any backend, so start with the simplest that fits and
swap later ([swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md)).

## Map requirements to a backend

- **`claude-code`** — headless `claude -p`. The strongest default; needs the `claude` CLI
  installed and authenticated ([use-heartbeat-with-claude-code.md](use-heartbeat-with-claude-code.md)).
- **`codex`** — headless `codex exec` (OpenAI's terminal agent); authed via `codex login`, or
  `HB_EXEC_PROVIDER=oss` for a keyless local model ([use-heartbeat-with-codex.md](use-heartbeat-with-codex.md)).
- **`opencode`** — headless `opencode run` (SST's provider-agnostic agent); model via
  `HB_EXEC_MODEL` (`provider/model`) ([use-heartbeat-with-opencode.md](use-heartbeat-with-opencode.md)).
- **`ollama`** — a local model, offline, no API key; stdlib-only. Choose it for privacy, cost,
  or air-gapped runs; set expectations to the model's size
  ([use-heartbeat-with-ollama.md](use-heartbeat-with-ollama.md)).
- **A framework** — `agno`, `crewai`, `langgraph`, `openai-agents`, `autogen`, `smolagents`, or
  `pydantic-ai`. Choose one if you already build on it; HeartBeat drives it as the worker and
  complements it rather than replacing it.
- **`script`** — any command in any language (`HB_EXEC_CMD`). Choose it for a deterministic
  worker, a wrapper around your own tool, or testing.

Select with `HB_EXEC_BACKEND` (or the `backend` field in `.hb/executor.json`); `hb exec config`
prints the resolved choice (in both runtimes).

## Don't over-decide

The backend is an implementation detail, not the project. Pick the simplest one that can do the
work, run it, and let the gates verify. If it's the wrong fit you change one setting, not the
DAG — and you can prove your DAG isn't secretly coupled to one worker with the
[portability check](swap-workers-without-changing-the-dag.md). Writing your own is a small
adapter ([build-and-test-a-backend.md](build-and-test-a-backend.md)).

## Related

- The two-method backend contract: [build-and-test-a-backend.md](build-and-test-a-backend.md).
- Use different models for execute vs the refuter — an advanced assurance choice built on the
  same contract.
