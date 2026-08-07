# The auditor catches each weakness — and doesn't cry wolf

`hb-audit` is the front-line gate-quality check: it refuses a DAG whose gates are hollow,
existence-only, nondeterministic, side-effecting, off-phase, ungated, or unguarded, *before*
a token is spent. A checker is only worth trusting if it actually fires on each weakness it
claims to catch — and stays quiet on a clean DAG. This is how that's proven.

## The rules

The auditor emits eight findings; some are hard errors (`ungated`, `hollow_gate`), the rest
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

## Proof

[`gate-examples/audit-rules-check.sh`](gate-examples/audit-rules-check.sh) proves the checker
has teeth in both directions. It **derives the rule set from the auditor source** — so a new
rule added without a fixture fails this check, not silently escapes — then, for each rule,
generates a minimal must-trip DAG and asserts that rule fires; finally it asserts a clean,
behavioral DAG trips **none** of them (no false alarms). Run it:

```bash
bash docs/howto/gate-examples/audit-rules-check.sh   # -> AUDIT-RULES-PROVEN:8
```

This is the auditor's analogue of the parity self-test
([keep-the-runtimes-in-parity.md](keep-the-runtimes-in-parity.md)): don't just watch the
checker pass — prove it fails when it should.
