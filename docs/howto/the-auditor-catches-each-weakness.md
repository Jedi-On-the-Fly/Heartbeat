# The auditor catches each weakness — and doesn't cry wolf

`hb-audit` is the front-line gate-quality check, *before* a token is spent: it refuses a DAG
whose structure is invalid (`dag_shape`) or whose gates are hollow, ungated or carry a control byte, and it flags gates that are
vacuous, existence-only, nondeterministic, side-effecting, off-phase, unguarded or
unconstrained — and a speculative tail (phases planned past the knowledge horizon) — as
warnings or notes. A checker is only worth trusting if it actually fires on each weakness it
claims to catch — and stays quiet on a clean DAG. This is how that's proven.

## The rules

The auditor emits twelve findings; some are hard errors (`dag_shape`, `ungated`, `hollow_gate`, `control_char`), the rest
warn or info (the full semantics and exact severities live in the auditor itself,
[`hb-audit.js`](../../plugin/templates/hb-audit.js), and the gate catalogue in
[writing-behavioral-gates.md](writing-behavioral-gates.md)):

| Rule | Weakness |
|---|---|
| `unguarded_phase` | a phase with tasks but no gate — its work is never verified |
| `ungated` | a gate with no criteria |
| `hollow_gate` | a gate with criteria but none behavioral |
| `vacuous` | a criterion that's trivially true (`true`) |
| `existence` | a criterion that checks a file exists, not its content |
| `nondeterministic` | a criterion touching `$RANDOM` / network / time |
| `side_effecting` | a criterion that writes its own evidence |
| `gate_offphase` | a gate referencing files no task in the phase mentions |
| `control_char` | a criterion carrying a `\x1e`/`\x1f` byte that would corrupt the gate runner's transport |
| `unconstrained_review` | a review gate with no plan-time `review.constraints` — the refuter's target is implicit (a warning) |
| `dag_shape` | the plan's STRUCTURE is invalid (a malformed container, id, reference or `parked`, or an unreadable file) — the first structure error, as `hb-lint` reports it ([a-malformed-plan-fails-closed.md](a-malformed-plan-fails-closed.md)) |
| `speculative_tail` | two or more trailing LIVE (non-parked) phases left unverified behind a verified head — planned past the knowledge horizon; names the cut point (a warning) |

## Proof

[`gate-examples/audit-rules-check.sh`](gate-examples/audit-rules-check.sh) proves the checker
has teeth in both directions. It **derives the rule set from the auditor source** — so a new
rule added without a fixture fails this check, not silently escapes — then, for each rule,
generates a minimal must-trip DAG and asserts that rule fires; finally it asserts a clean,
behavioral DAG trips **none** of them (no false alarms). Run it:

```bash
bash docs/howto/gate-examples/audit-rules-check.sh   # -> AUDIT-RULES-PROVEN:12
```

This is the auditor's analogue of the parity self-test
([keep-the-runtimes-in-parity.md](keep-the-runtimes-in-parity.md)): don't just watch the
checker pass — prove it fails when it should.
