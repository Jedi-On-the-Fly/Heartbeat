# Plan refutation — Wave 3 "discovery" (DS1 / DS2), ROUND 5 (convergence verification)

Refuter: plan-level adversarial review of the round-4-folded dag
(/home/curtism/Drums/lab/heartbeat/.hb/dag.json, `_meta.refutation_rounds` = rounds 1–4).
Tree at **7cc9595 — the SAME commit round 4 probed**, so every file:line citation from
rounds 1–4 remains valid against today's code (re-spot-checked where load-bearing). All live
probes in the session scratchpad (`r5/fx1`, bootstrapped via `plugin/bootstrap.sh`,
`HB_NO_GIT=1`, the phase completed only through the CLI: `node .hb/hb.js start/done`,
`bash .hb/gate.sh`, regate verbs HB_ACTOR-stamped). The repo tree and the live `.hb/` were
untouched; no repo-root .hb tool was run against the repo's own .hb. The revised dag was
linted and audited on a COPY (`r5/dag-copy.json`): node + python both
`✓ DAG valid (0 warnings)` and `✓ gates look behavioural (0 warnings)` — the P1–P4 strict-id
split lints clean.

Round-5 job: verify the round-4 fold landed exactly; fresh-eyes over the full final dag;
one live spot-check of the cycle-anchored absolution wording; the wave's economics.

Verdict summary: the design core is CONVERGED — F20/F22/F23/F24 are resolved in the dag
text verbatim, the cycle-anchored absolution wording is implementable from ds1b's words
alone (proved live: a simulator written strictly from the CORE paragraph, run over a REAL
CLI-produced event log, returns exactly the mandated verdicts on every shape, including the
S2 discriminator), and the economics have one owner per work unit with no wrong-order
dependency. But the F21 fold is PARTIAL — `_meta`'s round-4 record claims "the four doc
surfaces" were gained while the operative text names only park-a-phase.md's correction,
leaving three sentences the wave falsifies (dev-tests.md's T179 row, dev-plugin.md:150,
dev-python.md:70) with additive-only mandates and no net — and the round-4 split created
P3 with a claim ("the six re-specified suite checks assert the new contract") whose
subjects omit every file those checks live in. Both are surgical text fixes; both require
dag text. UNSOUND.

---

## 1. Round-4 findings verified against the dag text

**F20 — cycle-anchored absolution: RESOLVED, all four sites.**
- ds1a: "the anchor is CYCLE-scoped: an old innocent cycle from BEFORE the drift plus a
  later plain re-pass cures NOTHING (the whole cycle — its gate_regated included — must
  postdate the pair's later point)". ✓
- ds1b: "(ii) a COMPLETED regate cycle for that gate — gate_regated then gate_rearmed then
  a fresh criteria-pinned pass, in order, the WHOLE cycle (its gate_regated included) after
  the pair's later point". ✓
- P2: "a COMPLETED cycle for that gate (… the whole cycle after the pair's later point)
  absolves it; … an old pre-drift cycle plus re-pass all remain drift". ✓
- Prompt (e): "an OLD innocent cycle from before the drift plus a later plain re-pass cures
  NOTHING (the anchor is the cycle's own position, not the pass's)". ✓
- Live confirmation in §3 below.

**F21 — PARTIALLY RESOLVED; the doc-surface half is the miss (see R5-F26).**
- Six checks named in ds1a ("the SIX existing suite checks … (T160.3/.4, T161.2, the two py
  gate tests round 3 names, and T179.4 / regate-fail-closed case_park — which pins the
  parked --all exit 0 this wave flips)") ✓ and operatively in ds1b ("re-specify the six
  existing checks (T160.3/.4, T161.2, T179.4/regate-fail-closed case_park node; the two py
  gate tests) to the new contract") ✓. The checks are real at today's lines:
  run-tests.sh:1774/1778/1793; regate-fail-closed.sh case_park :351-364 pins
  `[ "$rc" -eq 0 ]` over parked-pending-regate --all (the exact check the wave flips);
  py/tests/test_gate.py:203 (`test_all_dedup_respects_timeout_and_failure`) and :232
  (`test_sweep_flake_probe_labels_but_never_absolves`). ✓
- Sweep wording 'criteria-pinned': ds1a "(the sweep walks gates ever CRITERIA-PINNED in the
  log — bare imports never seed it)" ✓; ds1b "removed gates appear via the log walk over
  CRITERIA-PINNED passes only" ✓; P3 "including a criteria-pinned gate removed from the
  dag" ✓.
- park-a-phase.md owned: ds2c "re-verify-completed-gates.md, block-pushes-on-failing-gates.md
  and park-a-phase.md updated for the new --all semantics (drifted gates
  excluded-and-counted; parked silences neither drift nor a pending regate)" ✓; in ds2w's
  11-file cmd ✓; in GATE_DS2 P1 claim + subjects ✓.
- MISS: dev-tests.md's T179 row, dev-plugin.md:150, dev-python.md:70 — see R5-F26.

**F22 — RESOLVED.** ds1b: "ALL FOUR protocol surfaces updated in the same change —
PROTOCOL.md template, hb.js protocol table, protocol.py, and hb-exec.js's human-needed case
table (the driver ESCALATES AND STOPS on criteria_drift, stated, never busy-loops) — plus
the driver stop-lists that enumerate human-needed reasons (heartbeat-detect.sh hook,
mcp_server.py's tick tool description)". ✓ All named surfaces verified real:
hb-exec.js:525-540 (the escalate-only case table with `default: escalate('unknown_reason')`),
heartbeat-detect.sh:13-16 (the loop stop-list), mcp_server.py:81 (the tick tool description's
loop-exit list). P3's claim carries the four surfaces + "the driver escalates and stops",
its violation "the exec driver busy-loops instead of escalating", and hb-exec.js is a P3
subject. ✓ Observation (no change owed): `PROTOCOL.md` is a GENERATED artifact —
bootstrap.sh:113 `node "$HB_DIR/hb.js" protocol --md > "$HB_DIR/PROTOCOL.md"` — so the
first two of the "four surfaces" are one edit point (the hb.js table feeds the template);
satisfiable as written, an implementer updating the table gets the template for free.

**F23 — RESOLVED.** GATE_DS1 constraints measured: P1 claim 63 words, P2 139, P3 102,
P4 77 (violations 36/50/59/49). House envelope re-measured from the ARCHIVED wave dags:
the detach wave (the immediately preceding wave) carries GATE_DT1 P1=141, P3=131, P2=120,
GATE_DT2 P1=115 — so every split constraint is at or under the house maximum (139 ≤ 141;
round 4's 107 ceiling was the regate wave only — the detach wave superseded it). Each id is
independently falsifiable (P1 append-continuation; P2 detection+cure+quiet; P3 reach incl.
park/removed/tick/protocol/six-checks; P4 teeth/hygiene), subjects partitioned per round 4's
suggestion (P2: hb.js, doctor.py, replan.sh; P3: gate.sh, gate.py, tick.sh, tick.py,
hb-exec.js, replan.sh — but see R5-F25), and lint accepts the strict P1–P4 ids on both
runtimes (copy-linted clean).

**F24 — RESOLVED.** GATE_DS2 P1 claim: "the re-specified how-tos
(re-verify-completed-gates.md, block-pushes-on-failing-gates.md, park-a-phase.md) are true
against the shipped --all and park semantics"; subjects list all three files. ✓

**Round-4 minors:** ds2w desc now honest ("the 11 docs the wave writes or re-specifies") ✓;
the HB_ACTOR procedural-trust clause present in ds1c ("HB_ACTOR strings are self-declared,
one human can play both actors, and a forged event log is outside it") and ds2b ("the trust
model procedural — HB_ACTOR self-declared, one human can play both actors; a forged log
outside it") ✓; `_meta.design`'s stale ":6" reworded ✓ (but see M2).

## 2. Fresh-eyes pass — what held

- The dag copy lints + audits clean on BOTH runtimes. ds2z still non-pre-satisfied (all
  three greps miss today; `T184` absent from tests/ docs/ plugin/ py/; `grp "T184` absent
  from run-tests.sh). ds2y's `GROUPS-PASSED:.* T184 ` idiom still mechanically correct
  (run-tests.sh:1971 `echo "GROUPS-PASSED:$_gp "` — trailing space live).
- ds2w's premise verified TODAY: the 9 existing non-SKILL files of the 11 pass in one run
  (`ALL-PROSE-OK:9`), SKILL.md fails on the placeholder class only, and l.244 is still the
  one 'fill in' phrase (`grep -n 'fill in'` → :244 only). The cmd cannot pre-satisfy
  (plan-to-the-horizon.md missing + SKILL red). The three sites agree on the count (desc
  "the 11 docs", cmd lists 11 paths, grep `^ALL-PROSE-OK:11`).
- The drift premise is still true at 7cc9595: on the laundered fixture (hand-weakened
  completed criteria + plain re-pass), `hb doctor` is `healthy` rc=0 on BOTH runtimes —
  the tripwire remains genuinely new, spec-first work; ds1a's "RED TODAY" holds.
- Spec-site consistency re-read as if round 1: the sweep contract
  (exclude-from-re-evaluation + count-failing + parked-counts + removed-via-pinned-walk) is
  worded identically across ds1a, ds1b, P3 and prompt (f); the cure message, severity
  (PROBLEM exit 1, twin-identical bytes, runtime-neutral verbs), desc/timeout_s honest
  limit, bare-pass immunity, and the every-tick wake + driver-stops pairing are each stated
  once per surface with no contradiction found. The every-tick wake is a stated departure
  from the rot wake-once flag — coherent because the driver escalates and stops (no
  busy-loop), and the hook/MCP stop-lists gain the reason in the same change.
- SKILL.md protocol row ownership is coherent: ds1b owns the runtime tables, ds2c owns
  "SKILL.md's protocol reason table row (owned by ds2a's file) kept consistent" (:333 row;
  the :256 reason list is adjacent context of the same edit). Mid-wave staleness between
  DS1 and DS2 is phase-gated, not a contradiction.
- GATE_DS2 P2 (prohibition + sanctioned path) unchanged and still sound against SKILL.md's
  existing never-weaken rule.

## 3. Live spot-check — the cycle-anchored wording is implementable from ds1b's words alone

Fixture `r5/fx1`: minimal H1 completed through the CLI, then the event shapes assembled
with the REAL verbs (every step accepted by the machinery):

    3 gate_passed  GATE_H1  [h1c1: grep -q '^hello$' …]     ← pin A
    4 gate_regated GATE_H1                                   ← reg1 (alice) — EARLY INNOCENT CYCLE
    5 gate_rearmed GATE_H1                                   ← arm1 (bob, artifact citing GATE_H1/H1)
    6 gate_passed  GATE_H1  [h1c1: grep -q '^hello$' …]     ← pin A2 (cycle C1 complete)
    7 gate_passed  GATE_H1  [h1c1: grep -q h …]             ← pin B — the LAUNDER (hand-weaken + plain re-run)
    8 gate_passed  GATE_H1  [h1c1: grep -q h …]             ← pin C — plain re-pass

A simulator (`r5/sim.py`) written STRICTLY from ds1b's CORE paragraph — pinned-pass walk +
current-dag final element, ordered (id, cmd) byte-exact, sanction (i) between-the-points,
absolution (ii) whole-cycle-after-the-later-point — run over this real log:

- **Old-cycle + launder + plain re-pass → DRIFT** (exactly one problem, the 6→7 pair).
  The wording's "(its gate_regated included) after the pair's later point" excludes the
  losing pass-anchored reading mechanically — reg1(4) < pin B(7), so cycle C1 cannot
  absolve, even though its pass-shaped tail (pin C at 8) postdates the drift. The S2
  discriminator now yields one determined answer from the text alone.
- **Bare declare cures nothing; declare+rearm cures nothing** (truncated-log replays: the
  6→7 drift persists through reg2 and reg2+arm2).
- **Completed post-drift cycle cures** (reg2 → arm2 by a different actor → fresh pass,
  all accepted live over the weakened-but-behavioral criteria): verdict `[]` — the launder
  pair absolved, the sanctioned pair regated-between, final pair pin==current.
- **A new hand-edit after the cure drifts again** (final pair 11→12).
- **desc/timeout_s-only edit → quiet** (the pin carries {id, cmd, exit} only — re-confirmed
  on the live event bytes).
- **Gate removed from the dag → problem** (the ever-criteria-pinned walk reaches it).

Nothing in the real machinery blocks the words: the pins carry ordered (id, cmd) on both
runtimes; gate_regated/gate_rearmed are gate-scoped; a post-hoc declare is accepted; the
rearm bar (different actor + ≥40-code-point artifact citing a phase anchor + in-lock audit)
is passable exactly at the sanctioned revision's own cost; evaluation refuses during a
pending regate, so "reg then arm then pass, in order" is the only assembly a real log
admits. The round-4 absolution verdict stands, now proved against a CLI-produced log rather
than a synthetic one.

## 4. Economics — owners, duplicates, sequence

One owner per unit: tripwire core both runtimes (ds1b: hb.js+doctor.py); sweep both (ds1b:
gate.sh+gate.py); tick both (ds1b: tick.sh+tick.py); reason surfaces + stop-lists (ds1b);
six re-specified checks (ds1b, operative imperative); drift:cross parity case (ds1b,
asserted by P4); proof + selftest (ds1a); T184 wiring + parity-notes (ds1c, falsified by
ds2z/ds2y); skill (ds2a); how-to (ds2b); docs current-state (ds2c); 11 docs clean (ds2w).
No unit is specced twice operatively (ds1a's passive "are re-specified … in the same
change" mirrors ds1b's imperative — see M1). Sequence sound: spec(ds1a) → impl(ds1b) →
wire+record(ds1c) → gate → skill(ds2a) → how-to(ds2b) → docs(ds2c) → gate; no task consumes
a later task's artifact (ds2a's how-to citation dangles only mid-phase, gate-evaluated at
phase end — round-4 adjudication re-confirmed; replan.sh is red-by-design and UNWIRED until
ds1c, so no suite reddens mid-phase from ds1a's own work). Orphan hunt: the only unowned
consequences found are the three doc sentences in R5-F26.

## R5-F25 — BLOCKING (fold-created). P3's six-checks clause has no subject file: the claim pins tests/run-tests.sh, tests/regate-fail-closed.sh and py/tests/test_gate.py and P3's subjects name none of them

P3's claim ends "…and the six re-specified suite checks assert the new contract"; its
violation clause includes "or a re-specified check still asserts the old silence". The six
checks live in tests/run-tests.sh (T160.3/.4 at :1774-1779, T161.2 at :1793),
tests/regate-fail-closed.sh (case_park, :351-364) and py/tests/test_gate.py (:203, :232) —
and P3's subjects are gate.sh, gate.py, tick.sh, tick.py, hb-exec.js, tests/replan.sh:
none of the three. This is the exact defect class this wave's own rounds folded three times
(round-1 F5, round-3 F17, round-4 F24: subjects must match what the claim pins); the gap is
NEW — P3 was created by the round-4 split, and the six-checks clause landed in it while its
files landed nowhere (round 4's suggested P2b partition predated the clause's inclusion).
A gate-time reviewer answering P3 must gather evidence from files no subject points at.

Required dag change (one line): add `tests/run-tests.sh`, `tests/regate-fail-closed.sh`
and `py/tests/test_gate.py` to P3's subjects.

## R5-F26 — BLOCKING (fold completeness). The round-4 record claims "the four doc surfaces" were gained; the operative text names only park-a-phase.md — the three other sentences the parked-count flip falsifies are owned by nobody and caught by nothing

`_meta.refutation_rounds[3]`: "the respec list gains the SIXTH check … and the four doc
surfaces (park-a-phase.md, dev-plugin.md:150, dev-python.md:70, dev-tests.md's T179 row) —
ds2w widens to ALL-PROSE-OK:11". What actually landed: park-a-phase.md is named for
correction in ds2c and P1(DS2); the other three files entered ds2w's PROSE list only, and
their ds2c mandates are purely ADDITIVE:

- **docs/dev-tests.md:183** (T179 row): "park composes (annotated, never failing the
  sweep)" — FALSE once ds1b re-specifies T179.4/case_park to counted-failing. ds2c's
  dev-tests mandate is "gains the T184 row" only.
- **docs/dev-plugin.md:150** (Regate section): "the --all sweep COUNTS the gate failing
  whether armed or planned (a parked one stays retired but its pending regate is annotated
  in the parked line)" — the parenthetical becomes false. ds2c's mandate for this file is
  "tick/doctor/sweep tables gain the criteria_drift reason and the drift problem row" —
  the Regate section is prose, not one of those tables.
- **docs/dev-python.md:70** (park row): "resolver/audit/report/sweep all skip it, loudly"
  — half-false (the sweep now counts a parked gate's drift/pending-regate failing). Same
  additive-only table mandate.

No net catches them if left stale: ds2w is prose STYLE (all three files pass prose-check
today and would pass with false sentences); ds2x is verified v1.29-era-token checks only
(docs-currency.sh:14-32 — accept_review/GROUPS-SKIPPED/stale-fixture-paths/STATUS v1.29);
GATE_DS2's prompt asks truth only of re-verify/block-pushes; P1(DS2)'s claim scopes the
skill, the how-to and the three re-specified how-tos (dev-tests.md is a subject but only
its T184 row and prose-cleanness are claimed); dev-plugin.md/dev-python.md appear in no
DS2 constraint. ds2c's umbrella ("Docs current-state across every surface the tripwire and
doctrine touch") gestures at them, but the wave's own standard — set by F3, F18c, F21, F24
— is named ownership, and the fold's record says the naming happened. GATE_DS2 is
satisfiable with the three sentences still asserting the contract this wave deletes —
AGENTS.md rule 7 violated by the wave's own hand.

Required dag change (one clause in ds2c; all three files are already in ds2w's 11, so no
criterion changes): e.g. "dev-tests.md gains the T184 row AND its T179 row reworded to the
new parked-sweep contract; dev-plugin.md's regate-section parked sentence and
dev-python.md's park row likewise". Recommended rider while touching that clause (same
class, round-4-advisory): docs/howto/drive-heartbeat-over-mcp.md:61-62's human-needed
enumeration mirrors the mcp_server.py tick description ds1b updates — add criteria_drift
there (and CLAUDE-MD-SNIPPET.md's condensed table, or record the snippet as deliberately
condensed; it already lags two reasons today).

## Minor notes (recommendations — not independently dag-blocking)

- **M1**: ds1a's "the SIX existing suite checks … are re-specified to the new contract in
  the same change" — "the same change" has no antecedent inside ds1a; the operative owner
  is unambiguous (ds1b's imperative "re-specify the six existing checks"), but a ds1a doer
  taking "the same change" as ds1a's own would redden three wired suites mid-phase (rule 4).
  Two words at the next fold: "in ds1b's change".
- **M2**: `_meta.design` ends "GATE_DS2 pins prose-check over every doc the wave touches" —
  overstates: ds1c touches planning/parity-notes.md, which is not in ds2w's 11 (it passes
  prose-check today). Non-operative narrative; align at the next fold.
- **M3**: ds1a names "the two py gate tests round 3 names", but the in-dag round-3 record
  says only "two py gate tests" — the names live in the session-scratchpad refutation file,
  which may not survive to execution. The set is objectively derivable from the stated
  property (the py sweep tests arming via post-pass hand-edits:
  `test_all_dedup_respects_timeout_and_failure`,
  `test_sweep_flake_probe_labels_but_never_absolves`), but naming them in ds1a (or
  archiving the refutation files into planning/ before the wave runs, the detach-wave
  precedent) removes the dangling reference.
- **M4** (observation, no change): "PROTOCOL.md template" and "hb.js protocol table" are
  one edit point (bootstrap.sh:113 generates the former from the latter); the four-surface
  list is satisfiable as written.
- **M5** (observation, no change): GATE_DS2 P1's claim asserts howto-list.md prose-clean
  without listing it as a subject — redundant with deterministic ds2w; harmless.

---

Two findings require dag text: R5-F25 (three subject paths added to P3) and R5-F26 (one
ownership clause in ds2c naming the three stale-sentence corrections the fold record
already claims). Both are surgical; neither touches the design. Everything else converged:
F20/F22/F23/F24 verified in the text verbatim, the cycle-anchored absolution implemented
from the words alone returns the mandated verdict on every shape including the S2
discriminator against a real CLI log, the economics are single-owner and well-ordered, and
the dag lints + audits clean on both runtimes.

UNSOUND
