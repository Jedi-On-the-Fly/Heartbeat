# Spend the model only on work

The expensive resource in an agent system is the model. HeartBeat's core economic move is to
keep a cheap, deterministic **tick** in the idle loop and wake the model only when there is
real work to do. Between tasks, reality is settled and observable with no model in the loop —
the tick reads that settled state and decides.

## What the tick decides

`hb tick` returns `{ "wakeAgent": bool, "data": { "reason": … } }`:

- **Work available** → `wakeAgent: true` with an actionable `reason` (`next_task`,
  `gate_pending`, `review_pending`, …). Only then is the model spent.
- **Nothing to do** → `wakeAgent: false` (`at_capacity` while a task is in flight, or a
  waiting state). The tick handled it; no model is invoked.

So the model is paid for exactly when there is a task to advance — not on a schedule, not to
decide *whether* to work. A task already leased by a running worker yields `at_capacity`: the
tick will not wake a second agent to duplicate in-flight work.

## Why it matters

This is what makes long, mostly-idle projects cheap: a tick every N minutes costs ~nothing,
and the model is spent only on the units of work that actually exist. It also means "should I
wake?" is a code decision, not a model decision — see
[the deterministic-gap concept](../heartbeat.md).

## Proof

[`gate-examples/tick-economics.sh`](gate-examples/tick-economics.sh) drives the real tick and
asserts it wakes only on work: a ready task yields `wakeAgent=true` (`next_task`), while the
same task in flight yields `wakeAgent=false` (`at_capacity`) — no second agent spent. Run it:

```bash
bash docs/howto/gate-examples/tick-economics.sh   # -> TICK-ECONOMICS-OK
```
