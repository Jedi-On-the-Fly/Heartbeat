# HowTo

Task-oriented guides for using HeartBeat well. Mechanism guides are backed by a runnable proof;
the decision/best-practice guides are integrity-checked (links resolve, only real commands) and
clarity-reviewed. Every guide is CI-enforced. The full roadmap (created + planned, across
families A–J) is in [howto-list.md](howto-list.md).

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
- [Run HeartBeat in CI](run-heartbeat-in-ci.md) — exit codes gate the pipeline; no wrapper needed.
- [Read the event log](read-the-event-log.md) — reconstruct a run; why state.json is disposable.
- [Embed HeartBeat in a Python app](embed-heartbeat-in-python.md) — drive it via the library, no CLI.
- [Handle a successful refutation](handle-a-successful-refutation.md) — a found hole holds the phase; fix and re-verify.
- [How to size a task](size-a-task.md) — one bounded unit of work with one observable result.
- [How to size a phase](size-a-phase.md) — one verified milestone you'd roll back to.
- [Choose Claude Code vs the Python runtime](choose-runtime.md) — same product; pick by environment.
- [Choose a Stage B backend](choose-a-backend.md) — map requirements to a worker; the choice is reversible.
- [When not to use HeartBeat](when-not-to-use-heartbeat.md) — where the ceremony isn't worth it.
- [Use HeartBeat with CrewAI](use-heartbeat-with-crewai.md) — your crew as the worker; the DAG verifies across tasks.
- [Use HeartBeat with LangGraph](use-heartbeat-with-langgraph.md) — your graph reasons; HeartBeat verifies.
- [Use HeartBeat with Agno](use-heartbeat-with-agno.md) — your Agno agent as the worker.
- [Use HeartBeat with the OpenAI Agents SDK](use-heartbeat-with-openai-agents.md) — handoffs within a task; HeartBeat across tasks.
- [Use HeartBeat with AutoGen](use-heartbeat-with-autogen.md) — your conversation within a task; HeartBeat verifies.
- [Use HeartBeat with smolagents](use-heartbeat-with-smolagents.md) — a code agent gated on its outcome.
- [Use HeartBeat with pydantic-ai](use-heartbeat-with-pydantic-ai.md) — typed outputs + behavioral gates.
- [Use HeartBeat with Codex](use-heartbeat-with-codex.md) — OpenAI's terminal agent as the worker.
- [Drive HeartBeat over MCP](drive-heartbeat-over-mcp.md) — the inverse: an MCP agent calls
  HeartBeat's tick/gate/state tools; `hb mcp-serve` is a stdlib-only stdio server.

Reference and concept docs live one level up in [`docs/`](../); contributor rules are in
[`AGENTS.md`](../../AGENTS.md).
