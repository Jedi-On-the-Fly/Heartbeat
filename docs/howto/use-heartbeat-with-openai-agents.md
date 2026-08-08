# Use HeartBeat with the OpenAI Agents SDK

**Outcome:** run a HeartBeat project with an OpenAI Agents SDK agent as the worker — keeping its
tools and handoffs, gaining behavioral gates, refutation, recovery, and cheap ticks.

## Handoffs happen inside a task; HeartBeat is across tasks

The OpenAI Agents SDK gives you an `Agent` with tools and **handoffs** between agents. All of
that is the *reasoning* for one unit of work — it happens **inside a single HeartBeat task**.
HeartBeat sits a layer up: its DAG sequences tasks across phases and gates each on a *behavioral*
check, and it never trusts the agent's own "done"
([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md)). One HeartBeat task = one agent run
(handoffs and all); HeartBeat decides what must be true next and whether it happened.

## Do it

```bash
HB_EXEC_BACKEND=openai-agents HB_EXEC_PROVIDER=ollama HB_EXEC_MODEL=qwen2.5:7b-instruct \
  hb exec run --dir myproject          # local, keyless — Ollama's OpenAI-compatible /v1
# or: HB_EXEC_PROVIDER=openai (with OPENAI_API_KEY; default model gpt-4o-mini)
```

`pip install "./py[openai-agents]"`. Provider/model is HeartBeat's standard `HB_EXEC_*` env; the
adapter runs the Agent with a function tool to write files.

## Bring your own agent

The shipped adapter (`py/src/heartbeat/backends/openai_agents.py`) wraps a generic `Agent`. To
drive **your** agent (with your tools/handoffs), edit its `execute(payload)` to run your Agent on
the task — `payload["context"]` is the brief, `payload["cwd"]` the working dir; return
`{"ok": bool, "summary": str}`. Small, replaceable file — not zero-code; validated like any
backend ([build-and-test-a-backend.md](build-and-test-a-backend.md)), and swappable without
touching the DAG ([swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md)).

## Gotcha

The `ollama` provider drives the SDK against **Ollama's OpenAI-compatible `/v1` endpoint**
(keyless) — no OpenAI key needed for local runs. The `openai` provider needs `OPENAI_API_KEY`.

## Proof (reproducible)

Live behavior needs a real model, so it's proven in a **pinned Docker image** (isolated deps,
re-runnable) — see [tests/frameworks/](../../tests/frameworks/):

```bash
bash tests/frameworks/run.sh openai-agents    # build the pinned image + drive it against Ollama
```

The recorded version · model · date · verdict is in
[tests/frameworks/RESULTS.md](../../tests/frameworks/RESULTS.md). The deterministic contract is
suite-enforced; the Docker run is the on-demand live tier and never gates the suite.
