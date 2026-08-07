# Never hand-edit HeartBeat state

**Rule:** mutate state only through the CLI. Never edit `state.json` by hand.

## Why

`events.jsonl` is the authoritative, append-only log; `state.json` is a **derived projection**
of it ([AGENTS.md](../../AGENTS.md) rule 1). Every CLI command (`start` / `done` / `fail` /
`gate` / `review` / `rebuild`) appends an event and reprojects — so the projection is always a
faithful function of the log. Hand-edit the projection and you create a lie the log doesn't
back: `doctor` flags it as drift, and the next `rebuild` (or any CLI mutation) overwrites your
edit from the log. The log always wins, so a hand-edit is at best discarded and at worst masks
the real state until it is.

If the projection looks wrong, don't patch it — **rebuild it**:

```bash
hb doctor    # flags "state.json differs from the event-log projection"
hb rebuild   # state.json := project(events.jsonl)
```

To actually change what's true, append an event (via a CLI command), never edit the file.

## Proof

[`gate-examples/never-hand-edit-state.sh`](gate-examples/never-hand-edit-state.sh) completes a
phase, hand-edits `state.json` to a wrong-but-valid value, and shows `doctor` flags the drift
and `rebuild` overwrites the edit back to the true projection (with a control that an in-sync
projection is not flagged) → `STATE-DISCIPLINE-OK`.

## Related

- Recover a corrupted projection or a rotted gate: [recover-a-dead-or-corrupted-run.md](recover-a-dead-or-corrupted-run.md).
- Stop and resume — the same reprojection: [stop-and-resume-a-project.md](stop-and-resume-a-project.md).
