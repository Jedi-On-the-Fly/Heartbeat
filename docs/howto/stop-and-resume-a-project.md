# Stop and resume a project

**Outcome:** kill a HeartBeat run mid-project and pick up exactly where it left off — because
state lives in the **event log**, not in a model's memory or a running process.

## Why it just works

`events.jsonl` is the authoritative, append-only record of everything that happened;
`state.json` is a **derived projection** you can throw away and rebuild
([AGENTS.md](../../AGENTS.md) rule 1). So "stop" is free — kill the process, close the laptop —
and "resume" is a reprojection:

```bash
hb rebuild --dir myproject     # state.json := project(events.jsonl)
hb tick    --dir myproject     # continue: hands out the NEXT task
```

A completed phase stays completed; the tick hands you the next unstarted task, not a redo of
finished work. A crashed session recovers the same way — the next tick rebuilds and continues,
and a stale lease from the dead session is reclaimed automatically
([prove-liveness.md](prove-liveness.md)).

## Don't hand-edit state

To change state, use the CLI (`start` / `done` / `fail` / `gate` / `review` / `rebuild`) —
each appends an event and reprojects. Editing `state.json` by hand desyncs it from the log; `doctor` will
flag the drift and `rebuild` overwrites it ([recover-a-dead-or-corrupted-run.md](recover-a-dead-or-corrupted-run.md)).

## Prove it worked

[`gate-examples/stop-resume.sh`](gate-examples/stop-resume.sh) completes phase 1, **deletes
`state.json`** to simulate a dead session, rebuilds from the log, and asserts phase 1 is still
completed (reconstructed from events) and the next tick continues to phase 2's task — not a
redo → `STOP-RESUME-OK`.

## Next

- If the projection or a gate's inputs got corrupted:
  [recover-a-dead-or-corrupted-run.md](recover-a-dead-or-corrupted-run.md).
- If it's stuck rather than stopped: [diagnose-a-stuck-project.md](diagnose-a-stuck-project.md).
