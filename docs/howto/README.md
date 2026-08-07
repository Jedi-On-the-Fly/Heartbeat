# HowTo

Task-oriented guides for using HeartBeat well. Each guide is backed by runnable proofs, not
just prose. The full roadmap (created + planned, across families A–J) is in
[howto-list.md](howto-list.md).

- [Writing behavioral gates](writing-behavioral-gates.md) — how to make a gate assert the
  *right* behavior, a catalogue of gate weaknesses (each a runnable proof under
  [`gate-examples/`](gate-examples/)), and the adversarial-fleet method for finding latent
  holes.
- [10 rules for a good gate](writing-gates-10-rules.md) — the checklist, each rule linked to
  a runnable proof.
- [Add refutation to a sensitive gate](add-refutation-to-a-sensitive-gate.md) — add a review
  block; make a pass cite evidence from a different actor.
- [Write fast, deterministic gates](write-fast-deterministic-gates.md) — same artifact, same
  verdict; well under the timeout, never a flaky timing bound.
- [Write gates for non-code work](write-gates-for-non-code-work.md) — gate documents,
  datasets, and migrations on content and shape, not `test -f`.
- [Keep the two runtimes in parity](keep-the-runtimes-in-parity.md) — the node≡python
  contract, and proving the parity alarm actually fires.
- [Recover a dead or corrupted run](recover-a-dead-or-corrupted-run.md) — the event log is
  truth; rebuild heals, doctor flags drift and rot.
- [Keep Stage B untrusted](keep-stage-b-untrusted.md) — the driver escalates on a failing
  gate, rejects malformed output, and kills a hung gate; it never trusts the worker.
- [Prove liveness](prove-liveness.md) — stuck builds, stale leases, and unresolved reviews
  escalate instead of hanging.
- [The auditor catches each weakness](the-auditor-catches-each-weakness.md) — every rule
  fires on a must-trip DAG, and a clean DAG trips none.
- [Swap workers without changing the DAG](swap-workers-without-changing-the-dag.md) — the
  same DAG completes under any backend; hidden worker-coupling is detectable.
- [Build and test a backend](build-and-test-a-backend.md) — the two-method wire contract and
  a reusable conformance harness.
- [Diagnose a stuck project](diagnose-a-stuck-project.md) — `hb diagnose` names the specific
  cause (failing criterion, missing file, awaiting gate).
- [Re-verify completed gates](re-verify-completed-gates.md) — a passed gate is a claim about
  current reality; `--check` / `--all` re-run it and catch decay.
- [Restore a verified phase](restore-a-verified-phase.md) — every gate pass is a git tag you
  can roll back to.
- [Spend the model only on work](spend-the-model-only-on-work.md) — the tick wakes the worker
  only when there's actionable work.
- [HeartBeat in 5 minutes](heartbeat-in-5-minutes.md) — the whole first-run cycle, end to end.
- [Turn a plan into a DAG](turn-a-plan-into-a-dag.md) — prose → phases/tasks/behavioral gates.
- [Stop and resume a project](stop-and-resume-a-project.md) — kill it and continue from the log.
- [Use HeartBeat with Ollama](use-heartbeat-with-ollama.md) — a local model as the worker.
- [Use HeartBeat with Claude Code](use-heartbeat-with-claude-code.md) — headless Claude as the worker.
- [Never hand-edit state](never-hand-edit-state.md) — the log is truth; the CLI mutates, rebuild overwrites edits.
- [Escalate instead of retry forever](escalate-instead-of-retry.md) — bounded retries, then surface to a human.
- [Refute high-risk claims, not every task](refute-high-risk-claims.md) — a review block is a selective lever.
- [Keep worker context from settled reality](context-from-settled-reality.md) — context is computed from state, not stale chat.

Reference and concept docs live one level up in [`docs/`](../); contributor rules are in
[`AGENTS.md`](../../AGENTS.md).
