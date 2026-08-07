# Write fast, deterministic gates

A gate runs on every tick that reaches it, and its verdict decides whether a phase advances.
Two properties are non-negotiable: it must give the **same answer** on the same artifact,
and it must give it **quickly**.

## Deterministic

Same artifact in, same verdict out — every time. If a gate can flip without the artifact
changing, a phase can advance (or stall) on noise, and a green run means nothing.

- Depend only on the produced artifact. No `$RANDOM`, no wall-clock, no network, no
  ordering that isn't pinned (`sort` before you compare).
- The auditor rejects the obvious sources (`$RANDOM`, `shuf`, `/dev/urandom`, `date`,
  `mktemp` in a verdict). → [nondeterministic](gate-examples/nondeterministic/)
- A subtle trap: **do not gate on timing itself.** `[ "$duration" -lt 2 ]` is a flaky gate —
  it fails under load with no change to the work. Assert the *result*, not how long it took.

## Fast

A gate must clear `GATE_TIMEOUT_S` comfortably. Keep it to bounded, local work: read the
artifact, assert one property, exit. No builds, no network round-trips, no unbounded scans
inside the gate — do the expensive work in a task, and let the gate check its settled
result.

Budget with a **generous margin**, never a tight bound. If a gate needs a timeout, give it
plenty of headroom so normal variance can't trip it — the point is to catch a hang, not to
race the clock.

## Proof

[`gate-examples/fast-determinism-check.sh`](gate-examples/fast-determinism-check.sh) proves
the whole example corpus is deterministic and fast: it runs the example runner twice and
asserts the output is byte-identical (determinism), then runs it under a generous `timeout`
and asserts it finishes within budget (fast) — a generous budget, deliberately, because a
tight one would be the very flakiness this page warns against. Run it:

```bash
bash docs/howto/gate-examples/fast-determinism-check.sh   # -> FAST-DETERMINISTIC-OK
```
