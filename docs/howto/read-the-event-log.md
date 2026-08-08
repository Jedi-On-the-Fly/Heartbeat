# Read the event log

**Outcome:** reconstruct exactly what happened in a run — and understand why `state.json` is
disposable — by reading `events.jsonl`, the authoritative record.

## What's in it

The log is append-only JSON lines, one event per line, in the order they happened:

```
{"event":"initialized"}
{"event":"task_started","task":"P0T1","actor":"…"}
{"event":"task_done","task":"P0T1"}
{"event":"gate_passed","gate":"GATE_P0","pass":1,"fail":0}
```

Common events: `task_started` / `task_done` / `task_failed`, `gate_passed` / `gate_failed`,
`review_passed` / `review_failed`, `lease_expired`. Each carries the `actor` that produced it —
that's what the [distinct-actor review guard](add-refutation-to-a-sensitive-gate.md) checks.

To read it: `tail -f myproject/.hb/events.jsonl`, or filter with `jq`. To answer "what is true
now?", don't parse it by hand — `hb state` projects it for you, and `hb rebuild` recomputes
`state.json` from it.

## Why it's the source of truth

`state.json` is a pure function of this log: replaying the events reproduces the state exactly.
Delete or corrupt the projection and `rebuild` reconstructs it; a hand-edit is overwritten
([never-hand-edit-state.md](never-hand-edit-state.md)). So the log — not a running process or a
model's memory — is what a dead session resumes from
([stop-and-resume-a-project.md](stop-and-resume-a-project.md)).

## Prove it worked

[`gate-examples/event-log.sh`](gate-examples/event-log.sh) completes a phase and asserts the
log is valid JSON in order (`task_started` < `task_done` < `gate_passed`) and that reprojecting
it reproduces the completed phase — and that dropping the `gate_passed` event removes the
completion (state is derived from the log) → `EVENT-LOG-OK`.
