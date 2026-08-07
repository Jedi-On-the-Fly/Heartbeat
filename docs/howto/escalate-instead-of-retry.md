# Escalate instead of retry forever

**Rule:** retry a *transient* failure a bounded number of times; **escalate** ambiguity and
persistent failure to a human. An agent that improvises indefinitely is worse than one that
stops and asks.

## How HeartBeat enforces the bound

The driver retries a failing task, but only up to `HB_EXEC_ATTEMPT_CAP` (default 3). After
that it stops with `attempts_exhausted` and surfaces the blocker — it does not loop forever
burning tokens. And a **blocked gate is never auto-fixed**: the driver escalates rather than
weakening the criterion ([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md)).

- **Transient** (a flaky call, a race) → a retry may clear it; the cap makes that safe.
- **Ambiguous / persistent** (the task is underspecified, or the gate can't pass) → escalate.
  Produce a blocker report; a human decides. Re-running the same failing step is not progress —
  the tick's stuck-loop detection catches that too ([prove-liveness.md](prove-liveness.md)).

Tune the bound with `HB_EXEC_ATTEMPT_CAP`; lower it when retries are unlikely to help.

## Proof

[`gate-examples/escalate-vs-retry.sh`](gate-examples/escalate-vs-retry.sh) drives the real
executor with a worker that always fails and shows the task is retried *exactly* the cap number
of times and then the driver escalates (non-zero, phase not completed) — with a control that a
working worker completes on the first attempt → `ESCALATE-VS-RETRY-OK`.

## Related

- What the driver guarantees for an untrusted worker: [keep-stage-b-untrusted.md](keep-stage-b-untrusted.md).
- When a run is stuck rather than failing: [diagnose-a-stuck-project.md](diagnose-a-stuck-project.md).
