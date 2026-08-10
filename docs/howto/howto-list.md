# HeartBeat How-To Library — roadmap

The full how-to map, organized by job (families **A–J**, after the original ideas list).
Each entry is either **created** (linked file, with the suite group that enforces it) or
**Not available yet**. Created guides are CI-enforced across `tests/run-tests.sh` groups
**T53–T81**: the mechanism guides by a runnable proof, the launch-prose guides (T62) by an
integrity check (links resolve, no placeholders, only real commands) plus adversarial clarity
review, and the framework guides (T64) by a Docker-free harness check + backend conformance
(their live proof is the reproducible pinned Docker in `tests/frameworks/`). See the
[index](README.md) for the shipped set.

Legend: ✅ created · ⬜ Not available yet · *(→ file)* = the outcome lives in a nearby guide.

---

## A. Quick Start — "make it work in 5 minutes"

| How-to | Status |
|---|---|
| HeartBeat in 5 Minutes | ✅ [heartbeat-in-5-minutes.md](heartbeat-in-5-minutes.md) — T59 |
| Your First HeartBeat Project | ✅ [heartbeat-in-5-minutes.md](heartbeat-in-5-minutes.md) — T59 |
| Your First HeartBeat Failure | ⬜ Not available yet *(→ diagnose-a-stuck-project.md)* |
| Stop and Resume a Project | ✅ [stop-and-resume-a-project.md](stop-and-resume-a-project.md) — T59 |
| Run the Same DAG with Another Worker | ✅ [swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md) — T57 |
| Run HeartBeat Without Claude Code | ✅ [run-heartbeat-fully-locally.md](run-heartbeat-fully-locally.md) — T62 |

## B. Onboarding — "apply it to my project"

| How-to | Status |
|---|---|
| Turn an Existing Plan into a HeartBeat DAG | ✅ [turn-a-plan-into-a-dag.md](turn-a-plan-into-a-dag.md) — T59 |
| Break a Large Task into HeartBeat-Sized Units | ✅ [size-a-task.md](size-a-task.md) — T62 |
| Decide What Belongs in a Phase | ✅ [size-a-phase.md](size-a-phase.md) — T62 |
| Write Dependencies That Don't Over-Constrain | ✅ [write-sparse-dependencies.md](write-sparse-dependencies.md) — T77 |
| Add HeartBeat to an Existing Repository | ✅ [add-heartbeat-to-an-existing-repo.md](add-heartbeat-to-an-existing-repo.md) — T77 |
| Migrate an Existing Agent Loop to HeartBeat | ⬜ Not available yet |
| Choose Claude Code vs Python Runtime | ✅ [choose-runtime.md](choose-runtime.md) — T62 |
| Choose a Stage B Backend | ✅ [choose-a-backend.md](choose-a-backend.md) — T62 |

## C. Core Concepts — "why it works this way"

| How-to | Status |
|---|---|
| Find the Deterministic Gap | ⬜ Not available yet *(→ [heartbeat.md](../heartbeat.md))* |
| Separate Control from Cognition | ✅ [spend-the-model-only-on-work.md](spend-the-model-only-on-work.md) — T58 |
| Make the Worker Replaceable | ✅ [swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md) — T57 |
| Make State Computed, Not Remembered | ✅ [recover-a-dead-or-corrupted-run.md](recover-a-dead-or-corrupted-run.md) — T55 |
| Define Authority in an Agent System | ✅ [keep-stage-b-untrusted.md](keep-stage-b-untrusted.md) — T56 |
| Design for Explicit Failure | ✅ [prove-liveness.md](prove-liveness.md) — T56 |

## D. Gates & Assurance — "define and verify done" (deepest family)

| How-to | Status |
|---|---|
| Write Your First Behavioral Gate | ✅ [writing-behavioral-gates.md](writing-behavioral-gates.md) — T53 |
| Convert Structural Checks into Behavioral Checks | ✅ [writing-behavioral-gates.md](writing-behavioral-gates.md) (imports-not-behavior) — T53 |
| Write Fast Deterministic Gates | ✅ [write-fast-deterministic-gates.md](write-fast-deterministic-gates.md) — T54 |
| Write Gates for Non-Code Work | ✅ [write-gates-for-non-code-work.md](write-gates-for-non-code-work.md) — T53 |
| Ten Rules for a Good Gate | ✅ [writing-gates-10-rules.md](writing-gates-10-rules.md) — T53 |
| Decide How Many Gates a Phase Needs | ⬜ Not available yet |
| Debug a Failing Gate | ✅ [diagnose-a-stuck-project.md](diagnose-a-stuck-project.md) — T57 |
| Audit Gates with `hb audit` (each weakness) | ✅ [the-auditor-catches-each-weakness.md](the-auditor-catches-each-weakness.md) — T56 |
| Detect Hollow / Vacuous / Existence Gates | ✅ [writing-behavioral-gates.md](writing-behavioral-gates.md) — T53 |
| Remove Non-Determinism from Gates | ✅ [write-fast-deterministic-gates.md](write-fast-deterministic-gates.md) — T54 |
| Keep Gates Inside Their Phase | ✅ [writing-behavioral-gates.md](writing-behavioral-gates.md) (off-phase) — T53 |
| Make Gates Re-Verifiable | ✅ [re-verify-completed-gates.md](re-verify-completed-gates.md) — T58 |
| Add Refutation to a Sensitive Gate | ✅ [add-refutation-to-a-sensitive-gate.md](add-refutation-to-a-sensitive-gate.md) — T54 |
| Cross-model Verification (a different model refutes) | ✅ [cross-model-verification.md](cross-model-verification.md) — T73 |
| Benchmark Agents on the Same DAG | ✅ [benchmark-agents.md](benchmark-agents.md) — T74 |
| Extract a Verifiable-Reward Stream (`hb reward`) | ✅ [benchmark-agents.md](benchmark-agents.md) — T76 |
| Detect Model Regression (`hb bench --baseline`) | ✅ [benchmark-agents.md](benchmark-agents.md) — T76 |
| Write a Good Refuter Prompt / Profile | ⬜ Not available yet |
| Decide Which Gates Need Refutation | ⬜ Not available yet |
| Handle a Successful Refutation | ✅ [handle-a-successful-refutation.md](handle-a-successful-refutation.md) — T61 |
| Handle a Stuck Refutation Review | ✅ [prove-liveness.md](prove-liveness.md) (review_stuck) — T56 |
| Test Whether Your Refuter Adds Value | ⬜ Not available yet *(needs a live model — not a deterministic proof)* |

## E. Backends & Frameworks — "use my model/framework"

| How-to | Status |
|---|---|
| Use HeartBeat with Claude Code | ✅ [use-heartbeat-with-claude-code.md](use-heartbeat-with-claude-code.md) — T59 |
| Use HeartBeat with Ollama | ✅ [use-heartbeat-with-ollama.md](use-heartbeat-with-ollama.md) — T59 |
| Use HeartBeat with Codex | ✅ [use-heartbeat-with-codex.md](use-heartbeat-with-codex.md) — T66 |
| Use HeartBeat with OpenCode | ✅ [use-heartbeat-with-opencode.md](use-heartbeat-with-opencode.md) — T72 |
| Drive HeartBeat over MCP | ✅ [drive-heartbeat-over-mcp.md](drive-heartbeat-over-mcp.md) — T67, T68, T70 |
| Install the HeartBeat plugin | ✅ [install-the-heartbeat-plugin.md](install-the-heartbeat-plugin.md) — T69 |
| Secure the MCP server | ✅ [secure-the-mcp-server.md](secure-the-mcp-server.md) — T71 |
| Use HeartBeat with Agno | ✅ [use-heartbeat-with-agno.md](use-heartbeat-with-agno.md) — T65 |
| Use HeartBeat with CrewAI | ✅ [use-heartbeat-with-crewai.md](use-heartbeat-with-crewai.md) — T64 |
| Use HeartBeat with LangGraph | ✅ [use-heartbeat-with-langgraph.md](use-heartbeat-with-langgraph.md) — T64 |
| Run a Custom Script Backend | ✅ [build-and-test-a-backend.md](build-and-test-a-backend.md) — T57 |
| Build a New HeartBeat Backend | ✅ [build-and-test-a-backend.md](build-and-test-a-backend.md) — T57 |
| Test a Backend for Conformance | ✅ [build-and-test-a-backend.md](build-and-test-a-backend.md) — T57 |
| Swap Models Without Changing the DAG | ✅ [swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md) — T57 |
| Use HeartBeat with the OpenAI Agents SDK | ✅ [use-heartbeat-with-openai-agents.md](use-heartbeat-with-openai-agents.md) — T65 |
| Use HeartBeat with AutoGen | ✅ [use-heartbeat-with-autogen.md](use-heartbeat-with-autogen.md) — T65 |
| Use HeartBeat with smolagents | ✅ [use-heartbeat-with-smolagents.md](use-heartbeat-with-smolagents.md) — T65 |
| Use HeartBeat with pydantic-ai | ✅ [use-heartbeat-with-pydantic-ai.md](use-heartbeat-with-pydantic-ai.md) — T65 |
| Use Different Models for Execute and Refute | ✅ [cross-model-verification.md](cross-model-verification.md) — T73 |

## F. State, Recovery & Operations — "what happens when things break"

| How-to | Status |
|---|---|
| Read HeartBeat's Event Log | ✅ [read-the-event-log.md](read-the-event-log.md) — T61 |
| Rebuild State from Events | ✅ [recover-a-dead-or-corrupted-run.md](recover-a-dead-or-corrupted-run.md) — T55 |
| Diagnose a Stuck Project | ✅ [diagnose-a-stuck-project.md](diagnose-a-stuck-project.md) — T57 |
| Recover from a Crashed Worker | ✅ [recover-a-dead-or-corrupted-run.md](recover-a-dead-or-corrupted-run.md) — T55 |
| Recover from an Orphaned Active Task | ✅ [prove-liveness.md](prove-liveness.md) (stale-lease reclaim) — T56 |
| Detect and Repair Gate Rot | ✅ [recover-a-dead-or-corrupted-run.md](recover-a-dead-or-corrupted-run.md) — T55 |
| Restore a Verified Phase | ✅ [restore-a-verified-phase.md](restore-a-verified-phase.md) — T58 |
| Understand HeartBeat Escalation | ✅ [keep-stage-b-untrusted.md](keep-stage-b-untrusted.md) — T56 |
| Keep the Two Runtimes in Parity | ✅ [keep-the-runtimes-in-parity.md](keep-the-runtimes-in-parity.md) — T55, T75 (fuzz oracle) |
| Build an Operational Runbook | ⬜ Not available yet |

## G. CI, Automation & Advanced Workflows — "run it unattended"

| How-to | Status |
|---|---|
| Run HeartBeat in CI | ✅ [run-heartbeat-in-ci.md](run-heartbeat-in-ci.md) — T61 |
| Schedule HeartBeat with Cron | ✅ [schedule-heartbeat-unattended.md](schedule-heartbeat-unattended.md) — T62 |
| Run a Scheduled Self-Audit (corpus drift + overclaims) | ✅ [run-a-scheduled-self-audit.md](run-a-scheduled-self-audit.md) — T81 |
| Run Independent Tasks in Parallel | ✅ [run-tasks-in-parallel.md](run-tasks-in-parallel.md) — T77 |
| Understand Worktree Isolation | ✅ [run-tasks-in-parallel.md](run-tasks-in-parallel.md) — T77 |
| Handle Merge Conflicts from Parallel Work | ⬜ Not available yet *(honest proof is timing-dependent — see notes below)* |
| Embed HeartBeat in a Python Application | ✅ [embed-heartbeat-in-python.md](embed-heartbeat-in-python.md) — T61 |
| Run HeartBeat Fully Locally | ✅ [run-heartbeat-fully-locally.md](run-heartbeat-fully-locally.md) — T62 |
| Spend the Model Only on Work (tick economics) | ✅ [spend-the-model-only-on-work.md](spend-the-model-only-on-work.md) — T58 |

## H. Best Practices — "what to consistently do"

| How-to | Status |
|---|---|
| How to Size a HeartBeat Task | ✅ [size-a-task.md](size-a-task.md) — T62 |
| How to Size a HeartBeat Phase | ✅ [size-a-phase.md](size-a-phase.md) — T62 |
| How to Write a Good DAG | ⬜ Not available yet |
| When Not to Use HeartBeat | ✅ [when-not-to-use-heartbeat.md](when-not-to-use-heartbeat.md) — T62 |
| When to Escalate Instead of Retry | ✅ [escalate-instead-of-retry.md](escalate-instead-of-retry.md) — T60 |
| Ten Rules for a Good Gate | ✅ [writing-gates-10-rules.md](writing-gates-10-rules.md) — T53 |
| Refute High-Risk Claims, Not Every Task | ✅ [refute-high-risk-claims.md](refute-high-risk-claims.md) — T60 |
| Never Let the Worker Define Its Own Acceptance | ✅ [add-refutation-to-a-sensitive-gate.md](add-refutation-to-a-sensitive-gate.md) — T54 |
| Recheck Old Proof After Relevant Change | ✅ [re-verify-completed-gates.md](re-verify-completed-gates.md) — T58 |
| Never Hand-Edit HeartBeat State | ✅ [never-hand-edit-state.md](never-hand-edit-state.md) — T60 |
| Keep Worker Context Derived from Settled Reality | ✅ [context-from-settled-reality.md](context-from-settled-reality.md) — T60 |
| Treat the Event Log as Truth | ✅ [recover-a-dead-or-corrupted-run.md](recover-a-dead-or-corrupted-run.md) — T55 |
| Prefer Explicit Failure to Silent Waiting | ✅ [prove-liveness.md](prove-liveness.md) — T56 |
| Make Every Completed Phase Reproducible | ✅ [re-verify-completed-gates.md](re-verify-completed-gates.md) — T58 |

## I. Contribution / Ecosystem — "extend HeartBeat"

| How-to | Status |
|---|---|
| Contribute a Backend Adapter | ✅ [build-and-test-a-backend.md](build-and-test-a-backend.md) — T57 |
| Contribute a Gate Audit Rule | ✅ [the-auditor-catches-each-weakness.md](the-auditor-catches-each-weakness.md) — T56 |
| Contribute a Gate Pack | ⬜ Not available yet |
| Contribute a DAG Template | ⬜ Not available yet |
| Publish a Reproducible Case Study | ⬜ Not available yet |
| Report a False Green | ⬜ Not available yet |
| Report a Backend Portability Failure | ✅ [swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md) — T57 |
| Build an Independent Runtime (conformance) | ✅ [keep-the-runtimes-in-parity.md](keep-the-runtimes-in-parity.md) — T55 |

## J. Troubleshooting — "something broke"

| How-to | Status |
|---|---|
| `hb tick` Says Sleep When I Expected Work | ✅ [spend-the-model-only-on-work.md](spend-the-model-only-on-work.md) — T58 |
| My Gate Passes but the Work Is Wrong | ✅ [writing-behavioral-gates.md](writing-behavioral-gates.md) — T53 |
| My Gate Fails Locally but Passes Elsewhere | ✅ [write-fast-deterministic-gates.md](write-fast-deterministic-gates.md) — T54 |
| My Project Is Stuck | ✅ [diagnose-a-stuck-project.md](diagnose-a-stuck-project.md) — T57 |
| The Worker Keeps Failing the Same Task | ✅ [prove-liveness.md](prove-liveness.md) (build_stuck) — T56 |
| A Completed Phase Became Broken | ✅ [re-verify-completed-gates.md](re-verify-completed-gates.md) — T58 |
| My Backend Works but State Does Not Advance | ✅ [keep-stage-b-untrusted.md](keep-stage-b-untrusted.md) — T56 |
| Switching Models Changes Project Behavior | ✅ [swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md) — T57 |
| My Refuter Always / Never Finds Anything | ⬜ Not available yet |
| HeartBeat Is Using More Tokens Than Expected | ⬜ Not available yet |
| A Gate Command Looks Unsafe | ✅ [review-an-unsafe-gate.md](review-an-unsafe-gate.md) — T77 |

---

## Where we are

The **assurance** spine (families C/D/F — gates, refutation, auditor, parity, recovery,
liveness, portability, diagnosis, re-verification, restore points) is essentially complete
and CI-enforced. This maps to **Hero Journey 2 (self-confirmation → evidence): done.**

The Quick-Start (A), backend (E), and the operational spine of G are largely in place, and the
Tier-1/Tier-2 gaps are now filled: parallel fan-out + worktree isolation, add-to-an-existing-repo,
sparse dependencies, reviewing an unsafe gate (all with runnable proofs under T77), plus running
fully locally and scheduling unattended (prose, T62).

**Deliberately deferred:** *Handle Merge Conflicts / parallel exactly-once* — its honest
proof is timing-dependent (worktree merge interleaving is nondeterministic), which would make
a flaky suite test; kept out to preserve the deterministic-proof invariant.

## Next up (recommended)

The remaining gaps are teaching prose (no new "does-the-alarm-fire" proof) or need a live model:

1. **Migrate an Existing Agent Loop to HeartBeat** (B) — the conversion story for an existing loop.
2. **How to Write a Good DAG** (H) — the synthesis umbrella over sizing + sparse deps + gates.
3. **Build an Operational Runbook** (F) — ops synthesis for a scheduled/unattended project.
4. **Write a Good Refuter Prompt / Profile** (D) — higher-value now that the refuter can be a
   different model; hard to back with a deterministic proof (needs a live model).
