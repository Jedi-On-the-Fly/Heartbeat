# Refute high-risk claims, not every task

**Rule:** adversarial refutation is powerful but not free — it spends a second agent. Add it to
the phases where a false "done" is *costly*, not to every task.

## The lever

A `review` block on a gate is a selective lever. Add one and the phase advances only after
**both** the deterministic gate passes **and** a second, distinct actor fails to refute it — so
a phase whose gate passed is *held* at `review_pending` until that refutation is recorded. Leave
it off and the phase advances on the deterministic pass alone. You choose where to spend the
review.

```json
"GATE_P3": { "review": { "prompt": "Refute that P3 is done: hollow tests? faked output?" },
             "criteria": [ /* the deterministic checks */ ] }
```

Where it earns its cost: irreversible or high-consequence outcomes, phases where the worker
graded its own homework, anything a plausible-but-wrong result would quietly corrupt. Where it
usually doesn't: cheap, easily-reversible, or already-strongly-gated work. How to add one, and
what makes a pass count as evidence: [add-refutation-to-a-sensitive-gate.md](add-refutation-to-a-sensitive-gate.md).

## Proof

[`gate-examples/selective-refutation.sh`](gate-examples/selective-refutation.sh) shows the lever
is real: with identical deterministic criteria, a review-gated phase is **held** after its gate
passes (awaiting refutation) while a non-review phase **completes** — so the review block is a
cost you apply selectively → `SELECTIVE-REFUTATION-OK`.

## Related

- Add and validate a refutation: [add-refutation-to-a-sensitive-gate.md](add-refutation-to-a-sensitive-gate.md).
- Never let the worker define its own acceptance alone: [keep-stage-b-untrusted.md](keep-stage-b-untrusted.md).
