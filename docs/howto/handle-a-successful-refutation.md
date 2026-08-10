# Handle a successful refutation

**Outcome:** know what to do when the refuter finds a hole. A successful refutation is not a
failure of the process — it's the process working. The phase is *held*, you fix the real
problem, and re-verify.

## The loop

On a [review-gated phase](add-refutation-to-a-sensitive-gate.md), the deterministic gate
passing is not enough — a second, distinct actor must fail to refute completion first. When the
refuter *does* find a hole, record it and the phase stays put:

```bash
hb review GATE_P3 fail "the test asserts the file exists, not that the endpoint returns 200"
```

Now the phase is **not** completed. Do NOT weaken the gate to make it pass — fix the actual
work (or the gate, if it was testing the wrong thing), then re-run the gate and get a fresh
refutation:

```bash
# fix the code, then:
hb gate GATE_P3                                   # re-run the deterministic gate
hb review GATE_P3 pass --artifact refutation.md   # a NEW, honest refutation attempt
```

A pass isn't a rubber stamp: the artifact must be substantive, cite the phase, and come from a
**different actor than the one who did the work** — a self-review is rejected. Only then does
the phase advance. The stored artifact is re-checked later by `doctor`, so the evidence can't
silently rot ([AGENTS.md](../../AGENTS.md) rule 6).

If the review never resolves at all, the tick escalates it to `review_stuck` past `STUCK_TICKS`
(both runtimes) — surfaced by `diagnose` — rather than the project hanging
([prove-liveness.md](prove-liveness.md)).

## Prove it worked

[`gate-examples/handle-refutation.sh`](gate-examples/handle-refutation.sh) drives the real CLI:
a review **fail** holds the phase; a **self-review** pass (same actor as the doer) is rejected;
and a valid pass from a **distinct actor** advances it → `HANDLE-REFUTATION-OK`.

## Next

- Add refutation to the right phases: [refute-high-risk-claims.md](refute-high-risk-claims.md).
- Write the refuter's attempt as evidence: [add-refutation-to-a-sensitive-gate.md](add-refutation-to-a-sensitive-gate.md).
