# Keep worker context derived from settled reality

**Rule:** the context you hand a worker should be *computed from the current settled state*, not
a long carried-over chat history. Reused narrative goes stale; settled reality doesn't lie.

## Why HeartBeat assembles context this way

Before each task, the driver builds the worker's context from scratch out of the DAG and the
current projected state — the phase, the task and its description, what is **already completed in
this phase**, and the gate's criteria (the definition of done: "build to pass, do not edit the
gate"). Because it's recomputed every time, the worker always sees *what is true now*, not what
a previous turn believed. This is the flip side of event-sourced state
([never-hand-edit-state.md](never-hand-edit-state.md)): state is computed, so context is too.

The practical payoff:

- No drift from stale narrative — a task started an hour and three phases later still gets an
  accurate picture.
- The worker is told exactly what its gate will check, so it builds to the evidence rather than
  guessing.
- It reinforces worker neutrality — the context is derived from the DAG and state, not from one
  model's conversation ([swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md)).

## Proof

[`gate-examples/context-from-state.sh`](gate-examples/context-from-state.sh) calls the real
`assemble_context` and shows the context for a task has no "already completed" note before a
sibling task is done and gains one after (recomputed from settled state, so the two differ), and
always carries the phase's gate → `CONTEXT-FROM-STATE-OK`.

## Related

- Why state is computed, not remembered: [stop-and-resume-a-project.md](stop-and-resume-a-project.md).
