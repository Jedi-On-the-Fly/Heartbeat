# Use HeartBeat with CrewAI

**Outcome:** run a HeartBeat project with your CrewAI crew as the worker — keeping the crew,
gaining behavioral gates, refutation, recovery, and cheap ticks.

## Does HeartBeat's DAG compete with my crew? No — different altitude

This is the first question a CrewAI user asks, and the answer is what makes the two compose:

- **CrewAI orchestrates *within* one unit of work.** A crew of role-playing agents collaborates
  to produce a result — the reasoning and execution of a single task.
- **HeartBeat orchestrates *across* units and verifies them.** Its DAG is phases → tasks →
  behavioral gates: what must become true, in what order, and how you *know* each step actually
  worked. It decides when to run your crew and whether the crew's output is acceptable.

So a **HeartBeat task is not a CrewAI Task**: one HeartBeat task = one `Agent + Task + Crew`
run. Your crew is Stage B (the reasoner); HeartBeat is the deterministic harness around it
([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md)). You don't rewrite the crew — you make
it a worker and gain verification.

## Do it

```bash
HB_EXEC_BACKEND=crewai HB_EXEC_PROVIDER=ollama HB_EXEC_MODEL=qwen2.5:7b-instruct \
  hb exec run --dir myproject          # local, no API key
# or: HB_EXEC_PROVIDER=anthropic (with ANTHROPIC_API_KEY)
```

`pip install "./py[crewai]"` (or `heartbeat-hb[crewai]`). The adapter builds a CrewAI `LLM` from
the provider — `ollama/<model>` via `OLLAMA_HOST`, or `anthropic/<model>` with a key — so the
provider/model selection is HeartBeat's standard `HB_EXEC_*` env, not crew-specific wiring.

## Bring your own crew

The shipped adapter (`py/src/heartbeat/backends/crewai.py`) wraps a *generic* one-agent crew.
To drive **your** crew, edit that adapter's `execute(payload)` to `kickoff()` your `Crew` on the
task — `payload["context"]` is the task brief, `payload["cwd"]` the working dir; return
`{"ok": bool, "summary": str}`. It's a small, replaceable file — not zero-code, but localized.
A custom adapter is validated the same way as any backend
([build-and-test-a-backend.md](build-and-test-a-backend.md)); and because the gate is the
contract, you can later swap crew → another framework without touching the DAG
([swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md)).

## Gotcha

CrewAI routes models through litellm, so the model is a **provider-prefixed string**
(`ollama/qwen2.5:7b-instruct`, `anthropic/claude-...`) — the adapter builds this for you from
`HB_EXEC_PROVIDER`/`HB_EXEC_MODEL`; if you hand-edit it, keep the prefix.

## Proof (reproducible)

Live behavior needs a real model, so it's proven in a **pinned Docker image**, re-runnable and
isolated from other frameworks' deps — see [tests/frameworks/](../../tests/frameworks/):

```bash
bash tests/frameworks/run.sh crewai      # build the pinned image + drive it against local Ollama
```

Captured outcomes (version · model · date · verdict) are in
[tests/frameworks/RESULTS.md](../../tests/frameworks/RESULTS.md). The deterministic contract —
the adapter conforms and degrades without the framework — is suite-enforced
([build-and-test-a-backend.md](build-and-test-a-backend.md)); the Docker run is the on-demand
live tier and never gates the suite.
