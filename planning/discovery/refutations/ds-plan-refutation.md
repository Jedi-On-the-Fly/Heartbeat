# Plan refutation — Wave 3 "discovery" (DS1 / DS2)

Refuter: plan-level adversarial review, run before any work. All probes executed in
mktemp/scratchpad fixtures (`bash plugin/bootstrap.sh <tmpdir>`, phases completed only through
the CLI: `node .hb/hb.js start/done` + `bash .hb/gate.sh`). The repo tree and the live `.hb/`
were not touched; the plan was audited on a copy (`node plugin/templates/hb-audit.js` +
`python -m heartbeat.cli audit` on `$SCRATCH/dag-copy.json` — both: "gates look behavioural,
0 warnings"; lint clean).

Baseline fixture ("fx1"): minimal dag, phase H1 (task H1T1, GATE_H1 =
`grep -q '^hello$' "$PROJECT_DIR/out.txt"`), completed through the CLI, gate passed
(`gate_passed` event pins the criteria: `{"id":"h1c1","cmd":"grep -q '^hello$' ...","exit":0}`).
Then horizon-2 phases appended by editing dag.json per the skill's continuation rule
(fresh ids, first new phase's `gate_entry` = `GATE_H1`).

Verdict summary: the plan's core append-continuation and unstarted-silence claims are TRUE and
runtime-agreed, but TWO of the characterization claims the plan asserts as existing mechanics
are FALSE today, and both sit inside gate-review constraints (P1, P2) that a faithful
implementation cannot satisfy without either changing the dag text or doing runtime work the
plan's premise says is zero. UNSOUND.

---

## F1 — BLOCKING. The boundary's LOUD side does not exist: hand-editing a COMPLETED gate's criteria is SILENT on BOTH runtimes, on every channel

ds1a asserts: "(boundary) hand-editing COMPLETED H1's gate criteria is LOUD — characterize the
exact channel (doctor drift finding / tick unsanctioned_drift / stale-pass invalidation) and
assert it on both runtimes." P2's claim repeats it; `_meta.design` presents the editability
boundary as a mechanic "that already exist[s]".

Probe: on fx1 (H1 completed through the CLI), hand-edit `dag.json`:
`d.gates.GATE_H1.criteria = [{id:"h1c1", desc:"...", cmd:"true"}]` (weakened from the grep).
Then every candidate channel, both runtimes:

| channel | node | python |
|---|---|---|
| `hb doctor` | `✓ hb doctor: healthy (1 note(s))` rc=0 (note is the unrelated benign "H2 not built yet") | `✓ hb doctor: healthy` rc=0 |
| `tick` | `{"wakeAgent":true,...,"reason":"next_task"}` — proceeds | same (`next_task`) |
| `hb-lint` | clean | clean |
| `hb report` | `GATE_H1: 1 passed, 0 failed` — no marker | no marker |
| `hb changed GATE_H1` | `(no changes)` (file-anchor based, not dag-based) | — |
| `gate.sh --check GATE_H1` | `✅ (check) GATE_H1 would pass` — the weakened criteria re-pass | — |
| `gate.sh --all` (re-verify sweep) | `✅ ALL GATES PASS` | — |
| `hb evidence GATE_H1` | prints the PINNED pass-time criteria (the old grep) but compares nothing, alarms nothing | — |

Why, from the code: every gate-content loudness guard in both runtimes is EVENT-keyed —
`regateBlocks` / `staleRearm` / `unansweredRegate` fire only on `gate_regated` / `gate_rearmed`
events or dag-vs-log marker disagreement (plugin/templates/hb.js ~371–400, 1035–1178;
py/src/heartbeat/doctor.py ~108–150, review_policy.py, constraints.py). A pure hand-edit writes
no event and sets no marker, so nothing fires. No code in either runtime compares
`dag.gates[g].criteria` against the criteria pinned in the last `gate_passed` event — even
though the log carries them (the tripwire's data exists; the comparison does not).
`tick unsanctioned_drift` is `WATCH_PATHS`-based and `WATCH_PATHS=""` by default
(plugin/templates/tick.sh:20); the only way to make it cover dag.json also trips on EVERY dag
edit — including sanctioned appends of unstarted phases — i.e. it would falsify the boundary's
SILENT side. The three candidate channels the dag names cannot satisfy the claim: doctor has no
criteria-drift check, tick drift can't distinguish the two sides, and stale-pass invalidation
requires a `gate_rearmed` event a hand-edit never writes.

Impact: the boundary case of tests/replan.sh is guaranteed RED; "fold it in ds1b" is not a
hole-fix but the design and construction of a NEW shared detection surface (dag-criteria vs
log-pinned-criteria comparison in doctor, on both runtimes, + parity case + teeth), under a
plan whose `_meta.design` premise is "Zero expected runtime change" and whose P2 constraint
asserts the feature already exists. P2 as written is unsatisfiable against today's code; a
reviewer holding the work to it must find it VIOLATED no matter how well DS1 is executed.

Required dag change (one of):
- Rescope ds1a's boundary case + P2 to characterize the TRUE boundary (hand-edit of accepted
  criteria is silent today; loudness exists only on the sanctioned channels and on
  marker/log disagreement — T180.7/T183 territory), and add an EXPLICIT task (or an explicit
  ds1b mandate) for the hand-edit tripwire: doctor compares each ACCEPTED gate's current
  criteria against the last `gate_passed`-pinned criteria, mirrored node≡python, parity case,
  selftest teeth. Name the runtime-code scope honestly in `_meta.design`.
- Or drop the loud-side assertion from this wave entirely and pin only what exists.

## F2 — BLOCKING. "Rebuild idempotent (state.json byte-identical across rebuild)" is false by design on both runtimes

ds1a: "rebuild idempotently (state.json byte-identical across rebuild)"; P1's violation clause:
"...or rebuild changes the projection bytes."

Probe (fx1, no append yet): two consecutive `node .hb/hb.js rebuild` → sha256
`f5f42db0…` then `40a81731…` — differ; diff is exactly `last_updated`
("2026-10-24T00:19:52.406Z" vs the previous stamp). Python: two rebuilds in the same second
were byte-identical (second-granularity timestamps — a flakiness trap), but with `sleep 1.2`
between them: `6419c17e…` vs `c6b46c53…` — differ, same cause.

This is documented intentional behavior, verbatim in BOTH runtimes:
- plugin/templates/hb.js:107 — "Pure: (events, dag) → state. Deterministic (except
  last_updated timestamp)." (`s.last_updated = nowIso()` at :185)
- py/src/heartbeat/state.py:83 — same comment; `s["last_updated"] = now_iso()` at :169.

`last_updated` has NO consumers (grep across both runtimes: it is written, never read), so a
determinism fold would likely be safe — but it IS a runtime change to the projection core of
both runtimes right before pinning it, and the plan nowhere says so. As written:
- the honest proof assertion goes red always on node (ms stamps) and FLAKILY on python
  (same-second races) — the worst failure mode for a characterization suite;
- P1's violation clause is ALWAYS true today, so the constraint is unsatisfiable as written —
  a plan-time constraint that copies a false premise as a requirement.

Required dag change: assert idempotence modulo `last_updated` (e.g. "byte-identical with
last_updated normalized", or "the projection byte-identical and the completed phase's record
byte-identical"), or explicitly scope "make rebuild's projection fully deterministic
(last_updated := last event's ts) on both runtimes + parity case" as sanctioned work. Pick one
in the dag text; don't leave it to a silent ds1b interpretation.

## What the probes CONFIRMED (the plan's load-bearing claims that are true today)

- Append-continuation is fully sanctioned and runtime-agreed (P1's core): after appending H2
  (fresh ids, `gate_entry: GATE_H1`, `GATE_H2` defined): node lint `✓ DAG valid (0 warnings)`,
  py lint identical; node resolver serves `H2T1`; tick wakes `next_task H2T1`; py `next` agrees
  (honoring the tick's lease: `busy, in_flight H2T1`); state.json bytes UNCHANGED by the append;
  after `rebuild`, `current_phase` advances H1→H2 with H1's record intact
  (`completed_tasks:["H1T1"]`, `completed_phases:["H1"]`).
- Unstarted surface is freely editable (P2's silent side): renaming/retitling/dropping tasks of
  never-started H2, and cleanly dropping an appended phase+gate: lint clean both, doctor
  healthy both (note count unchanged), both resolvers follow the edited plan (`H2T1R` served).
- The edges are loud and parity-identical: duplicate appended task id → `✗ duplicate task ID:
  H1T1` on both; `gate_entry` naming an undefined gate (or a gate dropped out from under a
  later appended phase) → 2 identical errors on both ("undefined gate", "no phase's gate_exit —
  phase locked forever") and tick surfaces `deadlock/dag_invalid`. Mid-lease append: tick
  `at_capacity` during the lease, `hb done` lands, resolver then serves the appended work.
- The discovery verbs compose at the replan point: `HB_ACTOR=… hb detach H2 --reason …` sets
  `gate_entry: null` + the four detach fields + loud report marker (`⟂ detached from GATE_H1`);
  lint stays clean on both; tick serves H2's task while detached; `reattach` restores
  `gate_entry: GATE_H1` and strips the fields; resolver sane throughout. Detach-fields-without-
  a-live-log-detach is already a characterized doctor NOTE channel (hb.js:420, doctor.py:159,
  pinned by T183) — the review prompt's "appended phase carries detach fields from a restore"
  probe has a real surface.
- ds2a's l.244 pre-check holds EXACTLY: `prose-check.sh` on today's SKILL.md fails with
  `placeholder in:` only; the code-stripped grep finds one hit — line 244 "fill in". Rewording
  just that phrase on a copy (with the three relative link targets present, as they are in the
  repo) → `PROSE-OK:SKILL.md`, `ALL-PROSE-OK:1`. No second failing class. dev-tests.md and
  howto-list.md pass prose-check today, so ds2w's `ALL-PROSE-OK:4` is reachable iff the two new
  texts are clean.
- ds2y's GROUPS-PASSED pattern is correct for run-tests.sh's real format: groups accumulate as
  `" $g"` and the marker line is `echo "GROUPS-PASSED:$_gp "` (tests/run-tests.sh:1970-1971) —
  trailing space guaranteed, so `grep -q 'GROUPS-PASSED:.* T184 '` keys on the OUTCOME set
  (only zero-fail groups with ≥1 registered check), exactly the repo's own documented coverage
  idiom (T52; SKILL.md "Coverage gates assert the OUTCOME"). T184 is unused in run-tests.sh
  today (groups end at T183) — the id is free.
- Timeouts are grounded: both gate runners honor per-criterion `timeout_s` over the 60s default
  (plugin/templates/gate.sh:30-46; py gate.py:17). Measured on this machine: parity.sh 4.9s
  (green), full pytest 10.4s / 171 passed (green), full detach.sh (the closest sibling proof,
  6 cases both runtimes) 10.9s — ds1x/ds1y/ds1p/ds1q/ds2q's 300s budgets have order-of-magnitude
  headroom. Full node suite: measured this session — see the appendix line below; the 1500s
  budget for ds2y is consistent with the dag's "~12min measured".
- docs-currency.sh is read-only and green today (`DOCS-CURRENT-OK`); audit of the plan copy is
  clean on BOTH runtimes; `review.profile` values (`correctness`, `default`) name shipped
  refuter profiles; the env-hygiene header the plan demands is the exact convention line
  (run-tests.sh:13, detach.sh:27); `tests/replan.sh` and `docs/howto/plan-to-the-horizon.md`
  do not exist yet (correctly new surface); P1's named subjects
  (plugin/templates/hb-lint.js, py/src/heartbeat/lint.py, tests/run-tests.sh) are real paths.
- Scope honesty: the skill's plan verb has a natural seam for the horizon rule (the
  "Continuation vs fresh" block, SKILL.md:40-43, states HOW; the Rules list follows) and no
  existing rule conflicts with plan-only-to-the-horizon or replan-as-outcome (never-weaken at
  SKILL.md:328 is reinforced, not contradicted). docs/heartbeat.md currently has NO
  regate/detach/doctrine enumeration (grep: zero hits), so ds2c's conditional concept line
  correctly self-cancels or motivates a new enumeration — either reading is implementable.

## Minor findings (recommendations — not dag-blocking on their own)

- F3: No criterion falsifies ds2c's actual outputs. dev-tests.md and howto-list.md pass
  prose-check TODAY, unchanged; docs-currency checks v1.29-era tokens only. If ds2c were
  skipped entirely (no T184 row, how-to unlisted), ds2w/ds2x/ds2y/ds2q all still pass; only the
  review prompt covers it. Cheap fix in the dag: an outcome-keyed criterion in GATE_DS2, e.g.
  `grep -q 'T184' docs/dev-tests.md && grep -q 'plan-to-the-horizon' docs/howto/howto-list.md`.
- F4: GATE_DS2's desc says "the changed docs — all prose-check-clean", but ds2c may also touch
  docs/howto/README.md, README.md, and docs/heartbeat.md, which ds2w's cmd does not check
  (the criterion desc honestly names its four; the gate desc overstates).
- F5: Constraint subject hygiene — P1(DS1) claims resolver/projection/rebuild behavior but its
  subjects name only lint (hb-lint.js, lint.py) plus the proof; the resolver
  (hb-next-task.js / resolver.py) and projection (hb.js / state.py) files the claim pins are
  unnamed. P2's only subject is tests/replan.sh itself. Add the real subjects so the gate-time
  reviewer's targets match the claims.
- F6 (implementation caution, for the ds1a author): appending a phase whose gate cmd references
  a not-yet-built file adds a benign doctor NOTE ("not built yet") on both runtimes — the
  unstarted-silence assertion must key on doctor PROBLEMS/exit-code (or note-count delta across
  the edit), not "zero notes".

## Appendix — node suite baseline (ds2y)

Full `bash tests/run-tests.sh`, run 1 (this machine, this session): wall 13m27.8s —
within ds2y's 1500s budget and consistent with the dag's "~12min measured". The
GROUPS-PASSED trailing-space format is verified LIVE (the line ends `… T183 `), so the
`grep -q 'GROUPS-PASSED:.* T184 '` idiom is mechanically correct.

BUT run 1 exited 1: `RESULT: 470 passed, 2 failed` — T162.5 ("--all skips an ARMED parked
gate loudly") and T162.6 ("report shows parked honestly") failed; T162 is absent from
GROUPS-PASSED. Reproducing the suite's exact T162 sequence standalone (including the
T162.2/.3 park/unpark/audit cycle): green, 10/10 iterations, even under concurrent suite
load — so the red is an in-suite interaction or a rare flake, not a plain park regression.
Run 2 verdict: ALL GREEN — 472 passed, 0 failed, T162 in GROUPS-PASSED, wall 13m26.4s.
Conclusion: main's baseline is green, but T162.5/.6 is a REAL in-suite flake (red in 1 of 2
full runs this session, never standalone). F7 below.

Why this matters to THIS dag either way:
- ds2y keys on ` T184 ` alone, so GATE_DS2 passes while the owning suite is RED elsewhere
  (today it demonstrably can be). The gate's desc ("the how-to's anchor is green in the
  owning suite") is honest about that narrow scope, but AGENTS.md rule 4 ("suites stay
  green on every change") is then enforced by nothing in this plan — and the wave cannot
  ship its release commit over a red/flaky T162 anyway. The plan should either state the
  baseline assumption (node suite green on main at wave start) or widen ds2y to also key
  on the suite's exit (e.g. run once, assert exit 0 AND the T184 marker).
- F7 (hazard, recommend recording in the dag's _meta or refutation round): T162.5/.6 flaked
  red in a full-suite run on an otherwise clean main (standalone: 10/10 green; suite run 2:
  green). A wave whose before-commit checklist and ds2y criterion both run this 13-minute
  suite should know the flake exists — a random T162 red mid-wave would misread as a
  regression caused by DS1's work. Not a dag-text defect of THIS plan, but triage belongs
  somewhere sanctioned (likely the T162.5 `&&`-chain: one transient miss of `park P0` or the
  first `--all` grep leaves P0 parked and cascades into .6).

---

Two findings (F1, F2) place false characterization claims inside ds1a's spec and the
plan-time constraints P1/P2 — the dag text must change before this plan can verify its own
work. 

UNSOUND
