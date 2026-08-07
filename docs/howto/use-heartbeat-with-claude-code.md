# Use HeartBeat with Claude Code

**Outcome:** run a HeartBeat project with headless Claude as the worker. This is the default
backend — HeartBeat began as a Claude Code plugin — but the *same* DAG runs under any backend;
Claude is just one Stage B.

## Do it

With the `claude` CLI installed and authenticated:

```bash
HB_EXEC_BACKEND=claude-code hb exec run --dir myproject
```

Each task is dispatched to headless `claude -p` with a Stage-B worker prompt (do exactly this
one task, work in the project dir, never touch `.hb/` or the gate). On a review-gated phase,
the same backend runs the **refuter** — a skeptical `claude -p` that must fail to break the
completion claim ([add-refutation-to-a-sensitive-gate.md](add-refutation-to-a-sensitive-gate.md)).

In the Claude Code plugin runtime the equivalent is the `/heartbeat exec` skill; the wire
protocol is identical (see [dev-python.md](../dev-python.md) and
[build-and-test-a-backend.md](build-and-test-a-backend.md)).

## What HeartBeat does

The adapter only translates: it shells out to `claude` and maps the exit code to the
`{"ok":bool}` wire result. It never touches `state.json` or the gate — the driver runs the
gate and, on a failure, **escalates rather than trusting the worker**. So if `claude` errors,
stalls, or claims success on broken work, the phase does not advance
([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md)).

## Prove it worked

Live Claude output is non-deterministic, so the enforced proof mocks *only the CLI*: a stub
`claude` on PATH stands in while the real adapter, driver, and gate run unchanged — and a
failing `claude` is shown NOT to complete the phase (the driver never fakes completion).
[`gate-examples/claude-backend.sh`](gate-examples/claude-backend.sh) → `CLAUDE-BACKEND-OK`.

## Next

- Go fully local instead: [use-heartbeat-with-ollama.md](use-heartbeat-with-ollama.md).
- Add an adversarial reviewer to a sensitive phase:
  [add-refutation-to-a-sensitive-gate.md](add-refutation-to-a-sensitive-gate.md).
