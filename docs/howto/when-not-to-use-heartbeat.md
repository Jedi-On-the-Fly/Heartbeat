# When not to use HeartBeat

HeartBeat adds a deterministic harness — a DAG, gates, an event log, refutation — around agent
work. That structure earns its keep on long, verifiable projects and is pure overhead on work
that doesn't need it. Knowing where it *doesn't* fit is how you use it well.

## Don't reach for HeartBeat when…

- **It's a one-shot prompt.** A single question or a single generation has nothing to schedule,
  no phases to gate, no state to recover. Just call the model.
- **It's a throwaway script.** If you'll run it once and discard it, authoring a DAG and gates
  costs more than the work saves.
- **"Done" can't be a deterministic check.** HeartBeat's value is the behavioral gate — the
  observable proof that a phase is complete ([writing-behavioral-gates.md](writing-behavioral-gates.md)).
  If the outcome is purely subjective ("make the copy feel warmer") with no criterion you can
  express as code, the gate would be hollow and the apparatus is theatre. (For a *partly*
  subjective phase, a [refutation review](refute-high-risk-claims.md) can help — but if there is
  nothing objective to check at all, HeartBeat isn't the tool.)
- **The task is trivially short.** If a worker finishes in one focused turn and you can eyeball
  the result, the tick/gate ceremony outweighs the benefit. Size honestly
  ([size-a-task.md](size-a-task.md)) — if the whole project is one small task, it's not a
  HeartBeat project.

## Where it *does* earn its keep

Long, multi-phase, **verifiable** work — especially unattended runs where a false "done" is
costly and you need recovery, restore points, and evidence you can re-check later. That's the
opposite of the cases above: many steps, objective checkpoints, and a real cost to being
confidently wrong.

## The honest limit

Even on a good fit, HeartBeat is only as strong as your gates — a weak gate gives *false*
confidence, which is worse than none. The auditor and refutation raise the floor, but choosing
an assertion that truly means "done" is still your judgment (see the honest-limits note in
[writing-behavioral-gates.md](writing-behavioral-gates.md)). Use HeartBeat where that judgment is
worth making; skip it where it isn't.
