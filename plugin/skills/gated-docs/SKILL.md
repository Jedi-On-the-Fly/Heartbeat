---
name: gated-docs
description: Write documentation as verified claims — every guide backed by a runnable proof or an integrity check, wired into the test suite, and adversarially refuted before it ships. Use when writing or revising a how-to/guide/doc that claims how the system behaves, or a batch of them. Applies HeartBeat's "refute, don't confirm" to the docs themselves.
---

# Gated Docs Skill (Claude Code)

**A doc is a claim.** An ungated claim is just confident assertion — the exact thing HeartBeat
exists to distrust. So here, documentation is held to the same bar as code: every guide is
backed by *verification*, wired into the suite so it re-checks on every run, and refuted before
it ships. **The doc bends to the code, never the gate to the doc.**

This is the method used to build HeartBeat's own how-to library. It caught real defects a
well-read but wrong guide would have shipped (e.g. a guide claiming worktree isolation is
unconditional when the code falls back to unisolated in-place execution).

## When to use

- Writing or revising a how-to / guide / reference that claims *how the system behaves*.
- A batch of guides (then orchestrate with the [heartbeat](../heartbeat/SKILL.md) skill).
- Any doc where "but does it actually do that?" is a question worth answering with a run.

## Two kinds of guide, two kinds of gate

1. **Mechanism guide** — claims specific behavior ("`hb ready` excludes a dependent task").
   Gate: a **runnable proof** under `docs/howto/gate-examples/<name>.sh` that demonstrates the
   claim and **fails if it's false**.
2. **Decision / prose guide** — teaches judgment (when to X, choose Y). Gate: **prose
   integrity** via [`prose-check.sh`](../../../docs/howto/gate-examples/prose-check.sh) — links
   resolve, only real commands, substantive, no placeholders.

## The recipe (one guide)

1. **Pick the kind** (mechanism vs decision).
2. **Spec-first: write the PROOF before the prose.** The proof must be able to go **red** — if
   you can't picture it failing, it's hollow (`test -f`, `true`, or `echo MARKER-OK`
   unconditionally). The teeth test: mutate the thing under test; the proof must then fail. A
   good proof is **self-contained** (own temp dir / stub; never depends on the repo's `.hb`),
   **deterministic** (no time / network / randomness), **fast** (under `GATE_TIMEOUT_S`), and
   prints one `MARKER-OK` line only when every claim holds. See
   [writing-behavioral-gates.md](../../../docs/howto/writing-behavioral-gates.md) for the
   catalogue of weaknesses, each itself a runnable proof.
3. **Write the guide.** Every command real, every link resolves, and claim only what the proof
   shows — no more.
4. **Wire it so it can't rot.** Add a suite check that **runs the proof and greps its marker**
   (not "the file exists") — a new `Tnn` group in `tests/run-tests.sh`, or add a prose guide to
   the prose bundle. Assert the marker on the same line as the proof, so a check hidden in a
   dead branch or a bare filename mention can't pass for wiring.
5. **Refute (a different actor).** Ask a skeptic: is the proof hollow? does the guide overclaim
   versus the code? broken links? Fix what it finds by **correcting the doc**, never by
   weakening the gate.

## The batch (dogfood with HeartBeat)

For several guides at once, make each guide a gated phase of a HeartBeat project:

1. `/heartbeat plan` a DAG under `planning/`, one phase per guide: the phase's first task
   authors the proof (spec-first), the second writes the guide and wires it. Gate each phase on
   **proof marker + prose-check + wired-into-suite**.
2. Get it **lint-clean + audit-clean**, then **plan-refute** (a skeptic returns SOUND) before a
   token of building.
3. Build phase by phase; on each gate, run a **distinct-actor refutation** (COULD NOT REFUTE).
4. Keep the node, Python, and parity suites green throughout; commit locally.

Match the ceremony to the scope: one small guide is the recipe above; a library is the DAG.

## Anti-patterns (a doc that only looks gated)

- A marker printed unconditionally, or a "strong" proof that also passes on the stub (never
  goes red).
- Wiring that greps a *filename* instead of *running the proof and asserting its marker* — a
  check in a never-taken branch reads as covered when it isn't.
- A guide claiming behavior the proof doesn't exercise (overclaim).
- Weakening a gate, softening a proof, or deleting an assertion to make a doc pass. The doc is
  what's wrong; fix the doc.

## Reference

- Behavioral-gate weakness catalogue: [writing-behavioral-gates.md](../../../docs/howto/writing-behavioral-gates.md)
- Prose integrity checker: [`prose-check.sh`](../../../docs/howto/gate-examples/prose-check.sh) (has a `--selftest`)
- Example proofs: [`docs/howto/gate-examples/`](../../../docs/howto/gate-examples/)
- Orchestration for a batch: the [heartbeat](../heartbeat/SKILL.md) skill (plan / audit / gate / run).
