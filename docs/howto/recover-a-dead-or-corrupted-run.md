# Recover a dead or corrupted run

The event log is truth. `events.jsonl` is the authoritative, append-only record; `state.json`
is a *derived projection* you never hand-edit ([AGENTS.md](../../AGENTS.md) rule 1). Because
of that, almost any breakage recovers by reprojecting from the log — and `doctor` tells you
when something is wrong before you trust a green run.

## Rebuild heals a bad projection

If `state.json` is stale, corrupted, or deleted, reproject it from the log:

```bash
hb rebuild        # state.json := project(events.jsonl)
```

Reprojection is faithful and idempotent — running it twice gives the same state, and a
completed phase stays completed. A dead session recovers the same way: the next tick
rebuilds and continues.

## doctor: the alarms

`hb doctor` is a read-only integrity check. Two alarms matter most:

- **Drift** — `state.json` disagrees with the projection of the log. Doctor flags it
  (`state.json differs from the event-log projection — run: hb rebuild`); `hb rebuild` heals
  it. (Note: a *totally unparseable* `state.json` can't be compared — just rebuild.)
- **Rot** — a *completed* phase's gate references a file that no longer exists, so that gate
  can't be reproduced. Doctor flags it (`… no longer reproducible`). This is why a gate must
  reference artifacts that persist, and why deleting a gate's input after the fact is a
  problem, not a cleanup. (Review artifacts rot the same way — see
  [add-refutation-to-a-sensitive-gate.md](add-refutation-to-a-sensitive-gate.md).)

Never hand-edit `state.json` to "fix" either — mutate state only through the CLI
(`start` / `done` / `fail` / `review` / `rebuild`), which appends an event and reprojects.

## Prove the alarms fire

A recovery check is only worth trusting if the alarm goes off when something is actually
wrong — and stays silent when it isn't.
[`gate-examples/recovery-demo.sh`](gate-examples/recovery-demo.sh) drives the real `hb` CLI to
show exactly that: it flags a stale `state.json` and heals it with rebuild (and confirms the
alarm is silent when in sync), flags a deleted gate artifact as rot (and confirms it's silent
before deletion), and confirms rebuild is faithful and idempotent. Run it:

```bash
bash docs/howto/gate-examples/recovery-demo.sh   # -> RECOVERY-GUARDS-OK
```
