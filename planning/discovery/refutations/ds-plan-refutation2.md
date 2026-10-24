# Plan refutation — Wave 3 "discovery" (DS1 / DS2), ROUND 2 (post-fold)

Refuter: plan-level adversarial review of the REVISED dag (/home/curtism/Drums/lab/heartbeat/.hb/dag.json,
`_meta.refutation_rounds[0]` = round 1). All probes in mktemp fixtures under the session scratchpad
(`bash plugin/bootstrap.sh`, phases completed only through the CLI on BOTH runtimes:
`node .hb/hb.js start/done` + `bash .hb/gate.sh`, and `python3 -m heartbeat.cli start/done/gate`).
Repo tree and live `.hb/` untouched (live events.jsonl read-only: 1 event, `initialized` — the
archive reset it, so no day-one live false positive). The revised dag was audited and linted on a
COPY: node + python both `✓ gates look behavioural (0 warning(s))`, `✓ DAG valid (0 warnings)`.

Round-2 focus: the new design surface (the drift tripwire spec in ds1a/ds1b/P2), its sanction
semantics against the real regate machinery, severity semantics, and the round-1 fold.

Verdict summary: the fold is faithful — every round-1 mechanical fix checks out live (modulo-
last_updated, problems/exit keying, ds2z non-pre-satisfied, ALL-PROSE-OK:6 reachable, subjects,
selftest/parity conventions). But the NEW surface — the tripwire spec — has three holes that make
constraints unsatisfiable or the doctrine launderable as written, plus two under-pinned semantics
the gate-time author and reviewer cannot hold without dag text. UNSOUND.

---

## The data dependency, established first (both runtimes)

A CLI-completed pass pins criteria on `gate_passed` in EXACTLY this shape, both runtimes
(gate.sh:335-339; py gate.py:193-194; live fixture events):

    node:   {"ts":…,"event":"gate_passed","gate":"GATE_H1","pass":2,"fail":0,
             "criteria":[{"id":"h1c1","cmd":"grep -q '^hello$' \"$PROJECT_DIR/out.txt\"","exit":0},
                         {"id":"h1c2","cmd":"python3 -c \"assert 1+1==2\"","exit":0}],
             "commit":null,"runtime":"node","git":{"autocommit":false}}
    python: same keys + "actor" ("unknown"), different JSON spacing — identical comparable content.

So the pin is a per-criterion `{id, cmd, exit}` SEQUENCE (order preserved — reorder IS
distinguishable), and NOTHING else: **no `desc`, no `timeout_s`**. The fixture's `timeout_s: 30`
on h1c1 was NOT pinned. This drives F10.

## F8 — BLOCKING. The tripwire's memory is one pass deep, and the UNSANCTIONED editor is the only actor who can re-pin it: a plain gate re-run launders drift in one command

Probe (both runtimes): on a fixture whose GATE_H1 passed through the CLI, hand-weaken the
criteria to `[{"id":"h1c1","cmd":"true"}]`, then run the gate NORMALLY (no regate, no rearm):
`bash .hb/gate.sh GATE_H1` → exit 0; `hb gate GATE_H1` (python) → exit 0. Each appends a SECOND,
fully PROVENANCED `gate_passed` pinning `{"id":"h1c1","cmd":"true","exit":0}`. Zero
`gate_regated`/`gate_rearmed` events. Doctor healthy, exit 0, both runtimes. Neither runtime has
an already-passed guard on the single-gate path (`--check`/`--all` are read-only, but the normal
run is not and is refused ONLY under a pending regate — verified: declare regate → `gate.sh`
exits 3 and writes nothing).

Consequence under the plan's spec ("compare the pinned criteria of the last provenanced
gate_passed against current dag criteria; a gate_regated after that pass sanctions"): after the
re-run, pin == current → the mismatch is GONE, permanently, with no regate ever declared. The
one command that exploits the boundary also erases the evidence. The asymmetry is exactly
backwards from the doctrine: the SANCTIONED reviser is fail-closed (regate pending → evaluation
refused, exit 3, rearm bar, different actor) while the unsanctioned editor re-pins freely. And
this is not an exotic adversary move — the suite itself uses hand-edit → re-pass → hand-edit as
its ARMING IDIOM (tests/run-tests.sh T161, ~1786-1790: GDET `false`→`true`→pass→`false`), so an
agent can launder innocently, mid-workflow.

The review prompt probes "rearm + fresh pass" (sanctioned re-pin) but never "fresh pass WITHOUT
rearm after a hand-edit" — the gate-time reviewer following the prompt verbatim will not catch it.

Required dag change (one of):
- Strengthen the spec: drift is ALSO "pinned criteria changed between two consecutive provenanced
  passes with NO gate_regated between them" — the data is already in the log; the sanctioned flow
  stays quiet (declare→edit→rearm→fresh pass has the regate between the two pins), and the
  hand-edit→re-run launder becomes a DURABLE finding. (Check the suite's edit-after-pass fixtures
  — T28.7/T160/T161 — none runs doctor afterward; verified no collision today.)
- Or honestly scope it: dag text + how-to state the tripwire's memory is one pass deep and a
  normal re-run re-pins — and then GATE_DS1's desc ("the editability boundary is real on BOTH
  sides") and the skill/how-to wording must be weakened to match.

## F9 — BLOCKING. The bare/import-pass clause is internally inconsistent across the three spec sites, and ds1b's operational wording picks the LAUNDERABLE reading

- `_meta.design` and P2: keyed on "the criteria pinned on its last PROVENANCED gate_passed" —
  selection ignores bare passes. Safe.
- ds1b (the implementation mandate): "for each gate whose LAST gate_passed is provenanced
  (criteria-stamped — bare import passes skipped)" — a PREDICATE on the last pass: one later bare
  pass makes the whole gate SKIP. `hb import` writes exactly such bare passes for every completed
  phase (hb.js:1649, `{event:'gate_passed', gate}`): hand-edit → `node .hb/hb.js import` →
  tripwire skips the gate. (Node-only verb, but bare events can land in any log — the
  doctor-parity fixture hand-writes one.)
- ds1a's quiet list ("a bare/import pass (no provenance to compare — skipped)") and the review
  prompt ("a bare import pass (skipped)") are ambiguous between the two readings — and ds1a is
  the SPEC-FIRST test, so whichever the author guesses gets cemented RED/GREEN before ds1b.

House precedent is explicit and opposite to ds1b's reading: staleRearm ignores bare passes so a
synthetic pass "cannot launder a revision into an acceptance" (hb.js:852-854). Required dag
change: make all three sites say the same thing — the pin is the latest CRITERIA-PINNED pass
(bare passes ignored in selection, never able to shadow a provenanced pin); skip only gates with
no criteria-pinned pass at all. Note also that the house term "provenanced" is defined as
criteria-OR-runtime (hb.js:853-864, `|| e.runtime`) — the tripwire needs criteria to compare, so
the dag should say "criteria-pinned" rather than import that leniency.

## F10 — BLOCKING. The pinned shape cannot patrol the boundary P2 declares: {id, cmd, exit} only — a timeout_s-only (or desc-only) hand-edit is UNDETECTABLE, and the comparison key / reorder / gate-deleted semantics are unpinned

Established above: neither runtime pins `timeout_s` or `desc`. `timeout_s` is BEHAVIORAL — the
per-criterion budget beats the runner default (gate.sh:28-33; gate.py:112-120), so hand-editing a
completed gate's `timeout_s` 300→1 can flip the gate's future verdict — and it is a hand-edit OF
THE CRITERIA (it lives inside the criteria objects). No doctor built on this pin can report it.

P2's violation clause — "a hand-edit of provenanced-accepted criteria produces no drift finding
on some runtime" — is therefore UNSATISFIABLE as worded: the same formal defect class as
round 1's F1/F2 (a constraint the best possible implementation must violate). And the review
prompt aims the reviewer at exactly this ambiguity ("Try to BREAK the tripwire: criteria
reordered vs edited, a timeout_s-only change, whitespace-only, a criterion added vs removed")
without the dag ever saying what the CORRECT behavior is for any of them — spec-first with no
spec. Concretely unpinned:
- The comparison key. Dag criteria carry `desc`/`timeout_s` the pin lacks and the pin carries
  `exit` the dag lacks — the spec must name the comparable projection (presumably the (id, cmd)
  sequence) or every implementation choice is a coin flip two runtimes must land identically.
- Reorder without content change: drift or not? (Order is pinned, so both answers are
  implementable; the test must assert ONE.)
- Whitespace in `cmd`: pinned verbatim → any byte change is detectable; is it drift? (Natural
  answer: yes, cmd bytes are the behavior — say it.)
- The gate (or its phase) DELETED from the dag after passing: the strongest possible hand-edit of
  accepted surface, and "compare against the gate's current dag criteria" has no defined behavior
  for a missing gate. If the implementer skips missing gates, deletion beats weakening and the
  tripwire is bypassed by the louder crime. Not probed by prompt or selftest.

Required dag change: pin the comparison key and the expected verdict for reorder /
timeout_s-only / desc-only / whitespace / added / removed / gate-missing — and state the
timeout_s/desc blind spot honestly (regate remains their only sanctioned-change channel, but the
UNsanctioned change is invisible), or scope widening the pin (gate.sh + gate.py event shape
change, a runtime surface the plan would have to name).

## F11 — Severity is unpinned: "finding" is neither problem nor note, and only one choice honors the doctrine (dag change: one word)

Doctor's channel semantics, verified both runtimes: problems → `✗ hb doctor: N problem(s)` exit 1;
notes → healthy exit 0 (hb.js:1296-1299; cli.py:443-450). House precedent: tampered/unsanctioned
states are PROBLEMS (marker-sync hand-cleared/fabricated markers, stale-accepted — hb.js:399-404;
doctor.py:132-145); legitimate in-flight states are NOTES (pending regate, live detach). The
round-1 fold pinned the QUIET side on "zero PROBLEMS with exit 0" (F6) but left the LOUD side as
"a finding": an implementer who ships the drift finding as a NOTE keeps doctor exit 0 "healthy"
over hand-edited accepted criteria, and P2 as written cannot refuse it — "loud" collapses into
the same channel as benign appends. Collision check: no existing test runs doctor on a fixture
that hand-edits a passed gate's criteria (T28.7 / T160 / T161 edit-after-pass fixtures never call
doctor; regate-rearm.sh:264 pins healthy only during the sanctioned pending window; T183's detach
notes stay exit 0; py tests' `problems == []` fixtures do no post-pass criteria edits; the
doctor-parity bare-pass fixture is skipped under either F9 reading) — so pinning "PROBLEM, doctor
exit 1, twin-identical bytes" breaks nothing known today. The dag should say the word.

## F12 — Scope-line finding: the plan is silent on gate.sh --check/--all and tick for a drifted gate, while --all already refuses to greenwash the SANCTIONED revision state

- `gate.sh --all` counts a pending regate FAILING, by design: "the sweep must never say ALL GREEN
  over an unrefuted revision" (gate.sh:250-252, 278). The identical doctrinal sentence applies to
  an unsanctioned revision — yet a drifted gate re-passes its weakened criteria and the sweep
  prints `✅ ALL GATES PASS` (round-1 table, still true). The repo's own re-verify surface
  certifies the state this wave calls corruption.
- BOTH ticks already run doctor every tick but filter to rot: tick.sh:189-197 greps
  "no longer reproducible"; tick.py:99 via doctor.py:166 (same predicate). Even a problem-severity
  drift finding never wakes the driver loop — the loud side is loud only when someone remembers
  to run doctor by hand.

The wave need not build these surfaces, but the dag must either extend them (both have one-line
precedents: the gate_rot wake; the sweep's regate annotation) or carry an explicit exclusion with
the reason — today GATE_DS1's desc ("the editability boundary is real on BOTH sides") and the
how-to's planned "the drift tripwire makes the unsanctioned path LOUD" overclaim relative to a
doctor-only, on-demand channel. At minimum: a scope sentence in ds1b/_meta and an honest clause
in ds1c's parity-notes paragraph + ds2b's how-to.

## Nuance (fold into the fixes; not independently blocking)

- N1: "a gate_regated after that pass sanctions the window" leaves the whole declare→next-pass
  span sanctioned, INCLUDING edits made after the rearm that the rearm bar never certified
  (the rearm pins its artifact, and the next pass re-pins whatever is then current). Mitigated for
  accepted gates by the existing stale-accepted problem (hb.js "rearmed after its last provenanced
  pass"), and closing the window at the rearm would false-positive on the sanctioned revision
  itself — so sanction-until-next-pass is right, but say so, and note it is another reason F8's
  consecutive-pin comparison is the load-bearing fix.
- N2: terminology — doctor already uses "drift" for state-vs-projection and tick for WATCH_PATHS
  (`unsanctioned_drift`); keep the full "unsanctioned-criteria-drift" string in messages so the
  three channels stay greppably distinct.

## Sequence coherence — probed, NO contradiction found in the rule itself

The review prompt's sequences check out against the real machinery (given F8/F9/F10 fixes):
pass → declare → edit: quiet on drift, the pending-regate NOTE + fail-closed evaluation own the
window (verified: evaluation refused exit 3; regate-rearm.sh:264 pins doctor healthy there).
Rearm → fresh pass → hand-edit: drift fires keyed on the NEW pin; no gate_regated after it; no
double-report (staleRearm is cleared by the fresh pass). Regate pending + edit + hand-rollback:
pin == current → no mismatch → correctly quiet; marker/log machinery stays loud. Hand-edit then
declare-regate-after-the-fact: sanctions retroactively — acceptable, it is the loud, recorded
path the finding message itself recommends ("regate to revise"). Rebuild replays: the pin lives
in events; rebuild changes neither events nor dag — stable.

## The fold — re-checked, HOLDS

- P1 modulo-last_updated: wording correct and the cited anchors are EXACT — hb.js:107 ("Pure:
  (events, dag) → state. Deterministic (except last_updated timestamp)"), :185
  (`s.last_updated = nowIso()`); state.py:83, :169 (same, verified by line).
- F6 keying: unstarted case on PROBLEMS/exit 0 — correct and sufficient on both runtimes.
- ds2z: all three greps FAIL today (none pre-satisfied): no `T184` in docs/dev-tests.md, no
  `plan-to-the-horizon` in docs/howto/howto-list.md, no `grp "T184` in tests/run-tests.sh; `T184`
  is absent repo-wide (tests/, docs/, plugin/, py/), and `grp "T184 — …` matches the real
  registration idiom exactly (cf. run-tests.sh:235 `grp "T18 — …`, :1904, :1938, :1957).
- ALL-PROSE-OK:6: prose-check.sh prints `PROSE-OK:<file>` per doc, exits 1 on the first failure,
  and prints `ALL-PROSE-OK:<n>` only when all pass — the `^ALL-PROSE-OK:6` key is sound. Today:
  dev-tests.md, howto-list.md, heartbeat.md, howto/README.md all pass (`ALL-PROSE-OK:4` live);
  SKILL.md fails on the placeholder class only, and rewording JUST the l.244 "fill in" phrase on
  a copy (link targets present) yields `PROSE-OK:SKILL.md` — re-verified this round. So :6 is
  reachable iff ds2a's reword + the two new/changed texts are clean. 
- Selftest/strip and parity conventions the plan leans on are real: detach.sh's `mutate()`
  sed-strips marked single lines from COPIES (node --check parse guard; `mkpycopy` for the python
  package), and parity.sh's cross cases pair `cmp` with content-floor greps (detach:cross,
  parity.sh:199-203) — "drift:cross with a non-vacuity floor" is implementable per house pattern.
  doctor.py already carries strip-clean single-line guard markers (doctor.py:158-160), so a
  python drift-guard line strips to valid code.
- ds1q/ds2q: py/.venv exists, venv pytest 9.1.1 imports. Budgets unchanged from round 1
  (parity 4.9s, pytest 10.4s, node suite ~13.5min < 1500s).
- Env-hygiene header demanded verbatim matches the convention line (detach.sh:27,
  run-tests.sh:13).
- Review profiles (`correctness`, `default`) and all constraint subject paths are real files;
  the P1/P2 subjects now include the runtime files the claims pin (round-1 F5 fixed).
- Revised dag audits clean + lints clean on BOTH runtimes (on a copy).

---

Three findings (F8, F9, F10) put a launderable or unsatisfiable spec inside ds1a/ds1b/P2 — the
spec-first premise means the dag text IS the spec, and it must change before the test author can
write the RED test it mandates. F11 and F12 each need at least a sentence of dag text (severity
word; scope line). The fold itself is faithful; the new surface is what fails.

UNSOUND
