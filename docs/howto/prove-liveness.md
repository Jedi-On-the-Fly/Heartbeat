# Prove liveness

A long autonomous run can fail two ways: it can do the wrong thing, or it can *hang* — loop
forever on a task it can't finish, sit on a lease from a dead session, or wait on a review
that never comes. HeartBeat's answer is that the tick **escalates instead of waiting
forever**. This is how to know those alarms actually fire.

## The alarms

- **Stuck build.** Repeated no-progress — a task that keeps failing — trips `build_stuck`
  once the failure count crosses the threshold, so a human is pulled in instead of the loop
  spinning. (Driven by the attempt/no-progress counters in the tick.)
- **Stale lease reclaim.** A lease whose holder went silent past its staleness deadline is
  reclaimed — a `lease_expired` event is appended and the task becomes claimable again — so a
  crashed session doesn't freeze a branch forever.
- **Unresolved review.** A phase whose deterministic gate passed but whose adversarial review
  never resolved is escalated to `review_stuck` by the tick past `STUCK_TICKS` (both runtimes) and
  reported by `diagnose`, not silently parked.

None of these should fire when the run is healthy — a fresh lease is kept, a progressing
build is quiet, a project with no pending review reports no `review_stuck`.

## Proof

[`gate-examples/liveness-demo.sh`](gate-examples/liveness-demo.sh) drives the real hb CLI and
proves each alarm fires when something is wrong **and stays silent when it isn't**: repeated
failures raise `build_stuck` (quiet before the threshold); a lease past a forced-zero
staleness deadline is reclaimed (a fresh one is kept); a review left pending is surfaced as
`review_stuck` (absent on a fresh project). Run it:

```bash
bash docs/howto/gate-examples/liveness-demo.sh   # -> LIVENESS-OK
```

The recovery counterparts — drift and rot detection, and rebuilding a dead session — are in
[recover-a-dead-or-corrupted-run.md](recover-a-dead-or-corrupted-run.md).
