# 10 rules for a good gate

A checklist. Each rule points at a runnable proof under [`gate-examples/`](gate-examples/)
or a sibling how-to — this is a distillation, not a second copy of the enforced rules (the
auditor and the [`/heartbeat plan` rules](../../plugin/skills/heartbeat/SKILL.md) are the
source of truth). The deeper treatment is [writing-behavioral-gates.md](writing-behavioral-gates.md).

1. **It fails on a hollow artifact.** Hand the gate the output of a worker that *didn't*
   do the work; it must fail. This one test catches most weak gates.
   → [hollow](gate-examples/hollow/)
2. **It asserts behavior, not existence.** Not "the file is there" but "the value is
   right." → [existence](gate-examples/existence/)
3. **Running the code is not enough — assert the behavior.** Imports ≠ works; compiles ≠
   correct; 200 on `/health` ≠ the feature works.
   → [imports-not-behavior](gate-examples/imports-not-behavior/)
4. **It is deterministic.** Same artifact, same verdict — no `$RANDOM`, clock, or network.
   → [nondeterministic](gate-examples/nondeterministic/) ·
   [write-fast-deterministic-gates.md](write-fast-deterministic-gates.md)
5. **It is read-only.** The gate reads the artifact; it never writes its own evidence.
   → [side-effecting](gate-examples/side-effecting/)
6. **It checks this phase's artifact.** Not a prior phase's leftover.
   → [off-phase](gate-examples/off-phase/)
7. **A coverage gate asserts the run PASSED**, not that a name appears in the log.
   → [coverage-header-grep](gate-examples/coverage-header-grep/)
8. **It is fast.** Well under `GATE_TIMEOUT_S`, with a generous margin — never a tight
   timing bound (that is itself flaky).
   → [write-fast-deterministic-gates.md](write-fast-deterministic-gates.md)
9. **It works for non-code deliverables too.** A document or dataset is gated on its
   content and shape, not on `test -f`.
   → [write-gates-for-non-code-work.md](write-gates-for-non-code-work.md)
10. **A sensitive gate is refuted, not just passed.** A second actor must fail to prove the
    phase isn't done, citing evidence.
    → [add-refutation-to-a-sensitive-gate.md](add-refutation-to-a-sensitive-gate.md)

Run `hb-audit` and confirm 0 findings; run the proofs with
`bash gate-examples/run.sh`. If a rule here ever drifts from the auditor or the plan rules,
those win — fix this list.
