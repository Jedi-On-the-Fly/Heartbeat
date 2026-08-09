# Run independent tasks in parallel

**Outcome:** run a phase's independent tasks concurrently instead of one at a time — and, in a
git repo, safely: each runs in its own worktree, so their writes can't collide.

By default HeartBeat is serial (one task at a time). When a phase has tasks that don't depend
on each other, you can fan them out.

## Do it

Ask HeartBeat for the concurrently-runnable set and drive it with a bounded number of workers:

```bash
hb ready 4                                  # up to 4 eligible, unleased, independent tasks
hb exec run --parallel 4 --dir myproject    # drive the loop, up to 4 in flight
```

`hb ready N` returns only tasks that are eligible right now: pending, unleased, and with every
`requires` dependency already done. A task that depends on another is **excluded** until its
dependency completes — so you can't accidentally start work out of order.

The plugin runtime uses the same idea via `HB_MAX_CONCURRENCY` (default `1` = serial):

```bash
HB_MAX_CONCURRENCY=4 hb exec run --dir myproject
```

## What HeartBeat does

Each fanned-out task runs in its **own git worktree**. It does its work on an isolated branch,
and only when it finishes does HeartBeat merge that worktree back into the main tree — one
merge at a time. A task that fails has its worktree discarded, not merged. After the wave, the
worktrees and their temporary `hb-exec/*` branches are cleaned up. So two tasks writing
different files never race on the working tree, and a half-done task leaves nothing behind.

**Isolation needs git.** The worktree isolation requires the project to be a git repo (and
`HB_NO_GIT` unset). Without git, fan-out falls back to concurrent **in-place** execution — the
tasks still run at once, but there's no worktree, so parallel writes *can* collide. In that
case keep the phase serial or make sure the tasks touch different files.

The atomic per-task lease guarantees no task is ever claimed twice, even when several workers
tick at once — the runnable set is handed out, not duplicated.

**The conflict rule.** `hb ready` only knows about `requires` edges. If two independent tasks
actually touch the *same* file, either let worktree isolation handle it (recommended — the
merge is serialized) or add a real `requires` edge so they run in order. Don't model a data
dependency as "no dependency and hope" — give it a real edge
([write-sparse-dependencies.md](write-sparse-dependencies.md)). The same fan-out works under any
worker; see [swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md).

## When to fan out

Fan out when a phase has several genuinely independent tasks and the worker is slow (a real
model, not a stub) — the wall-clock win is real. Keep it serial when tasks are quick, tightly
coupled, or share state that isn't file-scoped. Gates and refutation are unchanged either way:
parallelism speeds up *doing* the work, never *verifying* it.

## Prove it worked

The runnable-set and worktree-isolation behavior is demonstrated by a runnable proof — it
drives a concurrent fan-out with a stub worker and asserts both tasks' distinct files merged
back and the worktrees were cleaned up:

```bash
bash docs/howto/gate-examples/parallel-fanout.sh   # -> PARALLEL-FANOUT-OK
```
