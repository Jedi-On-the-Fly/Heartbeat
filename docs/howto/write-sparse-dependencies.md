# Write dependencies that don't over-constrain

**Outcome:** write `requires` edges that capture *real* dependencies only — so HeartBeat can
run everything that's genuinely independent in parallel, instead of marching through work in a
line it didn't need to.

A `requires` edge says "this task can't start until that one is done." Every edge you add that
*isn't* a real dependency removes a chance to parallelize.

## The rule

Add an edge only when the task truly needs the other's output or ordering:

- **Data dependency** — task B reads a file or result task A produces. Real edge.
- **Ordering dependency** — B must observe a state A established (a migration before a query).
  Real edge.
- **Same-file writes** — two tasks edit the same file. Either add an edge (serialize them) or
  let worktree isolation handle it ([run-tasks-in-parallel.md](run-tasks-in-parallel.md)).
- **Everything else** — no edge. "They feel related" or "I wrote A first" is not a dependency.

## Spot over-constraint

`hb ready` shows the runnable set at any moment. If a phase you expected to fan out only ever
offers one task, your edges are too tight:

```bash
hb ready --dir myproject     # how many tasks are runnable right now?
```

Chaining three independent tasks `A → B → C` offers exactly **one** runnable task; the same
three with only real edges offer **three**. Same work, three times the parallelism — the
difference is entirely in the edges.

## Why it matters

Over-constraint doesn't make results wrong — gates still verify every task — it just wastes
wall-clock by serializing work that could overlap, and it hides which tasks are actually
independent. Sparse, honest edges keep the DAG readable and let
[parallel fan-out](run-tasks-in-parallel.md) do its job.

## Prove it worked

A runnable proof builds two lint-clean DAGs with the same three tasks — one chained, one
sparse — and shows `hb ready` offers 1 vs 3:

```bash
bash docs/howto/gate-examples/sparse-deps.sh   # -> SPARSE-DEPS-OK
```
