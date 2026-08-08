# How to size a HeartBeat task

**Rule:** a task is **one bounded unit of non-deterministic work** — the amount a worker can do
in a single focused turn, producing one observable result.

Gates are *phase*-level, not per-task (a task carries `id` / `title` / `description` / `requires`,
no gate of its own). So sizing a task isn't about giving it a gate — it's about keeping its result
small and observable enough that it slots cleanly into the work its **phase gate** will verify.

## The test

Ask: *does this task produce one clear, observable result?* If you could point at a single
outcome ("`greeting.py` defines `greet` that returns the right string", "the row is in the
table") that would show it's done, it's the right size. If describing the result needs several
unrelated outcomes, it's more than one task.

## Signs a task is too big

- Its result is several unrelated outcomes at once (endpoint returns 200 **and** the migration
  ran **and** the docs updated) — that's three tasks.
- It touches many files for different reasons, so a failure is hard to localize.
- A retry has to redo a lot of already-good work — the [attempt cap](escalate-instead-of-retry.md)
  and recovery get coarse.

Split it by *deliverable*: one artifact or observable change per task.

## Signs a task is too small

- It produces nothing observable for its phase gate to build on — a bookkeeping step ("open the
  file", "think about X"). Fold it into the task that produces a real result.
- You're inventing steps just to have more tasks; that adds ceremony without adding checkpoints.

## Why it matters

Right-sized tasks keep three things sharp: **verification** (each task contributes a clear
outcome the phase gate can assert on — [writing-behavioral-gates.md](writing-behavioral-gates.md)),
**recovery** (a failed task re-runs cleanly), and **context** (the worker gets a focused,
state-derived brief — [context-from-settled-reality.md](context-from-settled-reality.md)). Get the
task boundary right first; the [phase](size-a-phase.md) groups these units into a verified
milestone.

## Related

- Turn a plan into tasks and phases: [turn-a-plan-into-a-dag.md](turn-a-plan-into-a-dag.md).
- Make the phase gate's criteria real: [writing-gates-10-rules.md](writing-gates-10-rules.md).
