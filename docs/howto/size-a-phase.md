# How to size a HeartBeat phase

**Rule:** a phase is **one meaningful, verified milestone** — a state of the project you would
want to roll back to. Its gate proves the milestone; every gate pass is a
[restore point](restore-a-verified-phase.md) (git auto-commit on, the default).

## The test

Ask: *if a later change broke things, would I want to `git reset --hard` to right here?* If yes,
it's a real milestone and deserves its own phase. If "here" is an arbitrary mid-point you'd
never target, it isn't a phase boundary.

## Signs the phase is too big

- Its gate has to assert many unrelated things at once — the definition of "done" is fuzzy.
- The whole phase is one restore point, so a regression forces you to redo a lot to get back to
  good.
- It has more than ~8 tasks (the linter flags this) — usually two milestones wearing one name.

## Signs the phase is too small

- A phase per tiny action — you get restore points you'd never use and ceremony that outweighs
  the value ([when-not-to-use-heartbeat.md](when-not-to-use-heartbeat.md)).
- The gate is trivial because the "milestone" isn't really a checkpoint.

## A good phase

Groups the [right-sized tasks](size-a-task.md) that together reach one checkpoint, behind one
behavioral gate that proves the checkpoint holds — and, for a high-stakes milestone, an
[adversarial review](refute-high-risk-claims.md). Spec-first: author that gate's check before the
implementation tasks, so "done" exists before the work.

## Related

- Roll back to a milestone: [restore-a-verified-phase.md](restore-a-verified-phase.md).
- Re-verify a milestone still holds after later changes:
  [re-verify-completed-gates.md](re-verify-completed-gates.md).
