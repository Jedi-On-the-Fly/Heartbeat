# Parity notes — node vs. Python (running log)

Purpose: capture anything that must stay identical between the node+bash plugin and the
`py/` port, so a future **parity test** (run the same input through both, compare output)
is easy to build. Update as we add cross-implementation surface.

## Shared surfaces (must agree)

| Surface | node | python | Compare by |
|---|---|---|---|
| Projector | `hb.js project()` | `heartbeat.state.project()` | same events+dag → same `completed_tasks/phases`, `pending_reviews`, `build_stuck_count`, `current_phase` |
| Resolver | `hb-next-task.js resolve/readyTasks` | `heartbeat.resolver` | same state → same next action / ready set |
| Lint | `hb-lint.js lint()` | `heartbeat.lint.lint()` | same dag → same errors (warnings may differ in wording) |
| Protocol | `hb.js PROTOCOL` | `heartbeat.protocol.PROTOCOL` | same reason set + action strings |
| **Auditor** | `hb-audit.js audit()` | `heartbeat.audit.audit()` | same dag → same findings (rule + severity per gate) |

Fixtures for the auditor live in `planning/audit-fixtures/` and are consumed by BOTH
suites (node T42, py test_audit.py).

**The parity test now exists: `tests/parity.sh`** (ratcheted as node-suite T43). It runs
the same inputs through both implementations and asserts they agree on: **audit** findings
(4 fixtures), **lint** errors (`planning/parity-fixtures/broken.json` + fixtures), and the
**state projection** (4 event scenarios: fresh / p0-gated / review-owed / two-fails). One
gotcha it encodes: Python's `json.dumps` escapes non-ASCII (the `—` in a lint message) — so
comparisons normalize with `ensure_ascii=False`. Extend it when a new shared surface lands.

## Auditor ruleset (identical regexes in both)

Classify each gate criterion `cmd`:
- **vacuous** — trivially true. `^\s*(true|:|exit 0|echo\b|test 1 = 1|\[ 1 = 1 \])\s*;?\s*$`
- **existence** — existence-only check. `^\s*(test\s+-[efds]\b|\[\s+-[efds]\b|ls(\s|$))`
- **behavioral** — anything else (the good case).
Orthogonal flag:
- **nondeterministic** — network/time. `\bcurl\b|\bwget\b|\bnc\b|\bping\b|\bsleep\b|\$RANDOM\b|\bdate\b|https?://(?!localhost|127\.0\.0\.1)`

Findings (severity):
- `hollow_gate` (**error**) — a phase's gate has criteria but NONE are behavioral (all vacuous/existence). The phase passes without proving its work.
- `ungated` (**error**) — gate has zero criteria.
- `unguarded_phase` (**warn**) — a phase has tasks but no `gate_exit`.
- `vacuous` / `existence` (**info**) — per-criterion note (does not fail the DAG on its own if a sibling criterion is behavioral).
- `nondeterministic` (**warn**) — per-criterion flake risk.
- `gate_offphase` (**warn**) — the gate references files no task in that phase mentions (may not test this phase's work).

`audit` exits 1 if any **error**, else 0. A phase with one behavioral + one `test -f`
criterion is NOT hollow (one behavioral criterion is enough) — only its `test -f` gets an
info note.

## Expected findings on the fixtures

| fixture | error | notable findings |
|---|---|---|
| `hollow.json` | yes | `hollow_gate` (G0), `vacuous` (G0/c) |
| `existence.json` | yes | `hollow_gate` (G0), `existence` (G0/c) |
| `nondeterministic.json` | no | `nondeterministic` (G0/c) — behavioral but flaky |
| `good.json` | no | none (clean) |

## Parity result (DA3)

Node ≡ Python on all four fixtures — same `errors`, `warns`, and sorted rule set.
(Only cosmetic difference: `json.dumps` spacing; compare via normalized serialization.)
This is the working parity test; a future dedicated one should also diff `project()`,
`resolve()`, and `lint()` on shared fixtures.

## Dogfood findings on our own DAGs (DA3)

Ran `hb-audit` on our real DAGs — the auditor behaved correctly and found nothing
false-confident in the plans we actually run:

| DAG | result |
|---|---|
| `planning/hb-exec.dag.json` | clean ✓ |
| `planning/heartbeat-py.dag.json` | `GATE_PP5[pp5c2]` is `test -f pyproject.toml` (info) — but has a `pytest` sibling, so **not hollow**. Fine. |
| `planning/dag-auditor.dag.json` (this plan) | clean ✓ |
| `plugin/templates/dag.json` (default template) | two `test -f` info notes with behavioral siblings → not hollow. **Could be more exemplary** (it's the thing users copy) — left as-is to avoid churning the node suite; noted as a follow-up. |
| python scaffold default (`hb init`) | `hollow_gate` **error** on the `true` placeholder — **intended**: a fresh project has no real gate yet, and audit correctly says so. |

Takeaway: the auditor caught the one genuinely hollow gate we ship (the scaffold
placeholder, by design) and cleared every plan we actually executed. No changes required.
