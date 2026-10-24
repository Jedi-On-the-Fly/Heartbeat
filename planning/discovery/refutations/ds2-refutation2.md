# Refutation attempt, round 2 — GATE_DS2 (phase DS2, docs/doctrine of the discovery wave)

Refuter: round-2 adversarial reviewer, different actor from the phase doer and from the
round-1 refuter's doer. Round 1 ended REFUTED (P1, G1, G4); the doer folded on all three plus
the degenerate-id side note. This round verifies the folds are real, spot-checks ids not
re-verified here, and renders the final verdict. Target claim unchanged: "the doctrine is
shipped as words that cannot rot: the skill's horizon rule and replan-as-outcome, the anchored
how-to, and the changed docs — all prose-check-clean, docs-currency green, the how-to's proof
anchor green in the owning suite (T184 in GROUPS-PASSED), and full pytest green."

## Fold verification (the three findings + the side note)

**G4 fold — the cure paragraph's declare form.** `docs/howto/plan-to-the-horizon.md` l.77–79
now reads: declare (`hb regate <gate> --reason "<why>"`; node takes trailing words instead:
`node .hb/hb.js regate <gate> <why…>` — the park/detach arg-style divergence). Ran every form
live on fresh copies of my own bootstrapped fixture (mktemp under the scratchpad,
`HB_NO_GIT=1`, env unset; the live `.hb` only read, never touched):

- python console, the doc's exact spelling: `hb regate GATE_H1 --reason "premise died"` →
  exit 0, regate declared, fail-closed message printed;
- python rearm, same sentence: `hb regate GATE_H1 --rearm --artifact e.md` (HB_ACTOR=dave,
  distinct from the declarer carol) → exit 0, evidence stored;
- the full cure completes verbatim: fresh pass exit 0, then `hb doctor` exit 0 (quiet);
- node, the labeled divergent form: `node .hb/hb.js regate GATE_H1 premise died` → exit 0;
- the form the label warns off: python positional reason `hb regate GATE_H1 premise died` →
  exit 2, "hb: error: unrecognized arguments: premise died" — exactly the divergence the new
  label declares. The label's name is accurate: `cli.py` l.83 registers `detach` with
  `--reason` too, while node's `case_quiet` uses trailing-words detach, so "the park/detach
  arg-style divergence" names a real shared divergence, consistent with dev-python.md l.71
  ("the park arg-style divergence") and park-a-phase.md l.17 ("Node runtime: …"). Fold real.

**P1+G1 fold — the exec claim now has a runnable anchor.** `tests/replan.sh` `case_tick`
(l.466–473) now runs BOTH executors on the drifted fixture — `HB_ROT_CHECK=1
HB_EXEC_BACKEND=script node .hb/hb-exec.js run` and the python `hb exec run` — asserting
nonzero exit AND `HB-EXEC STOP: criteria_drift` on each, before the cure un-sticks the loop.
The how-to sentence (l.72–75) now states exactly that and cites it: "both drivers escalate and
STOP on it — `HB-EXEC STOP: criteria_drift`, exit nonzero, never a busy-loop (`case_tick` pins
the ticks and both executors)." Reproduced independently on my own drifted fixture: node prints
`HB-EXEC STOP: criteria_drift — count=1` exit 1, python prints `HB-EXEC STOP: criteria_drift`
exit 1 — both contain the doc's promised string.

**Sabotage check — the new pin has teeth.** In a COPY of the fixture, deleted the
`case 'criteria_drift':` line from the copy's `.hb/hb-exec.js` (shipped at
plugin/templates/hb-exec.js l.536) and re-ran: the escalation degrades to
`HB-EXEC STOP: unknown_reason — criteria_drift` (the `default:` arm). Exit stays 1, so the
exit-nonzero assertion alone would not catch the deletion — but case_tick's
`grep -q 'HB-EXEC STOP: criteria_drift'` does NOT match the degraded line (verified live:
grep fails), so the shipped assertion reddens on the sabotage. The anchor genuinely depends on
the shipped case. Fold real, teeth real.

**G1 fold — append-quiet attribution.** The sentence (l.96–98) now reads "…and
`detach`/`reattach` (`case_quiet`) — and an append (asserted in `case_append`)", and
`case_append` l.160 carries `assert_quiet … "append (an append is sanctioned quiet)"` — the
claim and its anchor are now in the same case. Fold real.

**Side-note fold — the degenerate-id `?` rendering is pinned.** `case_append` now appends an
id-less 9-task phase and asserts both lints exit 0 with byte-identical `[?]` warning lines
(replan.sh l.161–177), anchoring the dev-tests.md T184-row claim "degenerate ids classifying
identically and rendering `?`" that round 1 flagged as untested. Ran green inside the full run.

## Suite and doc-integrity runs (this round)

- `bash tests/replan.sh` → APPEND-OK … TICK-OK, **REPLAN-OK**.
- `bash tests/replan.sh tick` → **TICK-OK** (the new exec sub-checks included).
- `bash tests/replan.sh --selftest` → **REPLAN-SELFTEST-OK** (the proof's own teeth survive
  the fold).
- ds2w verbatim: `prose-check.sh` on the 11 docs → **ALL-PROSE-OK:11** (no new
  placeholder-class phrase from the rewording).
- ds2x verbatim: `docs-currency.sh` → **DOCS-CURRENT-OK**, exit 0.
- T184 wiring re-read (run-tests.sh l.1974–1981): outcome-keyed on `^REPLAN-OK` /
  `^REPLAN-SELFTEST-OK`; `GROUPS-PASSED` lists only groups with zero failing checks and ≥1
  registered check. (Full node suite not re-run per round-2 scope — the gate ran it green
  twice; ds2y's criterion is that run.)

## No new contradictions from the reworded sentences

- The exec sentence agrees with dev-plugin.md l.201 ("Any human-needed reason → escalate
  (`HB-EXEC STOP: <reason>`); escalate-only, never auto-fixes"), l.156 (criteria_drift in
  PROTOCOL), SKILL.md's reason table (criteria_drift = HUMAN NEEDED), and dev-python.md l.31/36
  (tick wakes it every tick; executor.py is the twin) — and with AGENTS.md rule 5 (the driver
  escalates, never auto-weakens).
- The cure paragraph agrees with SKILL.md l.355 (node spellings — the node skill), hb.js
  PROTOCOL l.58 and protocol.py l.18 (each in its own runtime's arg style — the designed
  action-text divergence), and dev-python.md l.71 (the `--reason` row with the labeled node
  twin). No surface drops the different-actor rearm or the fresh pass.
- The append sentence agrees with dev-tests.md's T184 row ("Sanctioned quiet: … an append"),
  and the row's degenerate-id claim is now anchored rather than contradicted.

## Spot-checks of ids not folded this round

- **P2** (my P choice): re-read SKILL.md l.45–56 (horizon rule) and l.104–110
  (replan-as-outcome) and the how-to l.50–53 against the reworded cure paragraph; re-attempted
  the escape-detach / gate-weakening misreading. The replan point is still mandatory ("END the
  planned horizon with an explicit replan point"), the UNSOUND resolution still enumerates only
  sanctioned surface and ends "NEVER weaken a gate, constraint, or review", detach stays tied
  to a falsified claim and regate to dead premises, and the new cure wording adds commands, not
  permissions. No reading found.
- **G3** (my G choice): byte-compared the four cure surfaces this round (SKILL.md row 355,
  hb.js PROTOCOL l.58, protocol.py l.18, the reworded how-to paragraph): all name
  declare → DIFFERENT actor rearms with evidence → fresh pass, git-restore only as retraction
  of the content; `--freeze` appears only in the `unsanctioned_drift` rows and the T8/tick.sh
  references — no changed doc offers freeze or an edit-past for criteria_drift.
- **G5** (extra, live): two load-bearing tripwire properties probed on fixture copies —
  a desc rewording + `timeout_s` edit leaves both doctors at exit 0 (the unpinned exclusion),
  and a cleanly removed ever-pinned gate trips both doctors at exit 1 with twin-identical
  problem bytes ("GATE_H1: criteria drifted from the pinned evidence without sanction — …"),
  confirming the current-dag-final-element walk catches removal via the log.
- **G2** (grep re-check): no changed doc retains old-truth phrasing ("never failing the
  sweep" / annotated-skip-at-exit-0 / stray "exit 0" in the four how-tos) — grep empty;
  round 1's live sweep probes stand.

## Per-id answers

P1: NOT-REPRODUCED — round 1's hole is closed: the exec claim is now anchored in `case_tick`
(both executors run on the drifted fixture, asserting nonzero exit + `HB-EXEC STOP:
criteria_drift`), the anchor passes (REPLAN-OK, TICK-OK), and the sabotage probe (criteria_drift
case deleted from a copy's hb-exec.js) reddens the assertion — the anchor depends on the
shipped behavior. Prose-check ALL-PROSE-OK:11, docs-currency green, verbs/links unchanged
since round 1's exhaustive pass.

P2: NOT-REPRODUCED — probes: misreading re-construction against SKILL.md l.45–56/l.104–110 and
the how-to l.50–53 plus the new cure paragraph; the replan point stays mandatory, the
resolution surface stays sanctioned-only with the NEVER-weaken close, and the new wording adds
command forms, not permissions. No escape or weakening reading constructs.

G1: NOT-REPRODUCED — both round-1 infidelities cured and verified in the case bodies:
`case_tick` l.466–473 asserts the exact exec behavior the sentence that cites it states, and
the append-quiet claim now names `case_append`, where its `assert_quiet` lives (l.160). The
side-note gap is also closed: `case_append` pins the degenerate-id `[?]` rendering
byte-identically on both runtimes. All other anchors were verified faithful in round 1 and
their text is unchanged.

G2: NOT-REPRODUCED — probes: old-truth grep across the four changed how-tos (empty), the six
subject docs' sweep text unchanged since round 1's side-by-side read, and this round's full
replan run (case_sweep, case_park semantics green); one `--all` truth holds everywhere.

G3: NOT-REPRODUCED — probes (this round's deliberate spot-check): the four cure surfaces
byte-compared; identical full cycle in substance, runtime-specific arg styles only, git-restore
only as retraction, freeze confined to `unsanctioned_drift`. The reworded cure paragraph
changed spelling and labeling, not the cycle.

G4: NOT-REPRODUCED — the one rejected invocation is cured: the declare form is now shown in
python style with the node trailing-words divergence labeled, and every displayed form was run
live on its labeled runtime this round (python `--reason` exit 0, python rearm exit 0, full
cycle to doctor-quiet, node trailing words exit 0, python positional exit 2 — the divergence
the label states). Markers and T184 wiring re-confirmed (REPLAN-OK / REPLAN-SELFTEST-OK
printed; run-tests.sh l.1977/1979 key on them).

G5: NOT-REPRODUCED — probes: round 1's line-by-line code read stands (text unchanged), plus
this round's live property probes: desc/timeout_s edits quiet on both doctors (exit 0), a
removed ever-pinned gate trips both at exit 1 with twin-identical problem bytes.

## Overall finding

All three round-1 findings are genuinely folded, not papered over: the exec claim gained a
real anchor whose teeth survive a sabotage probe, the append claim now names the case that
asserts it, and the cure paragraph's declare form runs verbatim on the runtime it is written
for with the node divergence labeled per the repo's own precedent. The fold also closed the
unflagged degenerate-id gap. The reworded sentences introduce no contradiction with SKILL.md,
dev-plugin.md, dev-python.md, or dev-tests.md; prose-check, docs-currency, the full replan
proof, its selftest, and the spot-checked doctrine wording (P2), cure unanimity (G3), and
tripwire properties (G5) all hold. One honest observation, not a finding: in the sabotaged
executor the exit code stays nonzero (the default arm also stops), so the pin's teeth live in
the STOP-line assertion, which the probe confirmed reddens — the assertion pair is sufficient.
No id reproduces and no exploitable side defect was found. Phase DS2's gate claim stands.

COULD-NOT-REFUTE
