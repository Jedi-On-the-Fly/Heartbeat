# Run HeartBeat in CI

**Outcome:** a CI job that fails the build exactly when the work isn't verified. HeartBeat's
exit codes are meaningful, so a pipeline gates on them — no wrapper needed.

## The job

```yaml
# in your CI (any runner): fail fast on a bad plan, then drive to a verified state.
- run: hb audit myproject/.hb/dag.json   # non-zero if any gate is hollow — stop before running
- run: hb exec run --dir myproject       # non-zero unless every phase is verified
```

- `hb audit` exits non-zero on a hollow / prompt-shaped DAG, so a plan that verifies nothing
  never reaches execution ([the-auditor-catches-each-weakness.md](the-auditor-catches-each-weakness.md)).
- `hb exec run` exits `0` only when the project reaches `all_done` — every phase's behavioral
  gate passed. A blocked gate or exhausted retries exits non-zero and the build goes red
  ([escalate-instead-of-retry.md](escalate-instead-of-retry.md)).

Because the runtime is pure-Python with a stdlib core (`pip install heartbeat-hb`), it runs on
any CI runner with no services. Choose a headless backend (a local model, a script, or Claude
Code) and pass a key only if the backend needs one.

## Prove it worked

[`gate-examples/ci-flow.sh`](gate-examples/ci-flow.sh) drives the real auditor and executor and
asserts all three exit codes: a hollow DAG fails `hb audit`, a good project's `exec run` exits
0, and an unpassable one exits non-zero → `CI-FLOW-OK`.

## Next

- Make the run headless with a local model: [use-heartbeat-with-ollama.md](use-heartbeat-with-ollama.md).
- Re-verify old proofs in CI as a regression sweep: `hb gate --all`
  ([re-verify-completed-gates.md](re-verify-completed-gates.md)).
