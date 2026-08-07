# HowTo

Task-oriented guides for using HeartBeat well. Each guide is backed by runnable proofs, not
just prose.

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

Reference and concept docs live one level up in [`docs/`](../); contributor rules are in
[`AGENTS.md`](../../AGENTS.md).
