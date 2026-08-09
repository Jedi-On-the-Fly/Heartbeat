# Benchmark agents on the same DAG

Because a DAG's behavioral gates are the same whatever does the work, you can run the *same* DAG
under different backends and grade each one the same way. The gates are the rubric; completed
phases, retries, and escalations are the score. This is an apples-to-apples behavioral eval that
falls out of backends being interchangeable ([swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md)).

## Run it

```bash
hb bench --dir <project> --backend ollama --backend codex --backend opencode
hb bench --dir <project> --backend ollama --backend codex --json     # machine-readable
```

Each `--backend` is either a registered backend **name** (`ollama`, `codex`, `opencode`,
`claude-code`, a framework) or **`label=command`** for a raw script backend
(`--backend 'my-agent=bash ./my-agent.sh'`). Every backend runs the DAG on a **fresh isolated copy**
— your source project is never touched.

## The scorecard

Each backend gets a row (text table, or `--json`):

| Field | Meaning |
|---|---|
| `phases_done` / `phases_total` | phases whose gate (and review, if any) passed |
| `tasks_done` / `tasks_total` | tasks marked done |
| `gate_passed` | gate passes recorded in the log |
| `task_failures` | failed attempts (the retry/attempt-cap metric) |
| `escalated` | the run stopped for a human (attempt cap, blocked gate, …) |
| `completed` | all phases done |
| `outcome` | the run's final line — *why* it stopped |

The scorecard is derived from the **event log**, not the backend's self-report: a backend that
claims success advances nothing unless the gate actually passed.

## Honest scope

The **scorer is deterministic** given a run — that is what the suite proves
([`gate-examples/agent-bench.sh`](gate-examples/agent-bench.sh) scores good / bad / flaky stub
backends and checks each row). But a **real model's run is non-deterministic**: the same backend
can score differently across runs. So treat `hb bench` as a **capability probe**, not a leaderboard
— run it several times and read the distribution, not one number.

One caveat: a **review-gated** DAG only benchmarks cleanly under backends that implement `refute`
(the real agent backends do). A bare script backend that can't refute is reported as `escalated`
with a `review_error` outcome — honestly not-complete, not silently done.

This is the tool that *measures* what [cross-model-verification.md](cross-model-verification.md)
enables: run the doer under each candidate and see which actually clears the gates. Pick from
[choose-a-backend.md](choose-a-backend.md).
