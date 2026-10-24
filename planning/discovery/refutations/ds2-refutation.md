# Refutation attempt — GATE_DS2 (phase DS2, docs/doctrine of the discovery wave)

Refuter: adversarial reviewer, different actor from the phase doer. Target claim: "the doctrine is
shipped as words that cannot rot: the skill's horizon rule and replan-as-outcome, the anchored
how-to, and the changed docs — all prose-check-clean, docs-currency green, the how-to's proof
anchor green in the owning suite (T184 in GROUPS-PASSED), and full pytest green."

## What I ran and read

Read in full: `docs/howto/plan-to-the-horizon.md`, `tests/replan.sh` (all case bodies, d1–d7,
case_cure steps, case_sweep w1–w5, case_tick, case_quiet, selftest s1–s8),
`plugin/skills/heartbeat/SKILL.md` (horizon rule, replan-as-outcome, the full reason table),
`plugin/templates/hb.js` (PROTOCOL `criteria_drift`, `canonField`/`canonCrit`/`driftedGates`,
the `drift` verb), `py/src/heartbeat/protocol.py`, `py/src/heartbeat/state.py::drifted_gates`
and `_canon_crit`, `py/src/heartbeat/cli.py` (every `add_parser`), `plugin/templates/hb-exec.js`
(reason dispatch, incl. the `criteria_drift` escalate case), `py/src/heartbeat/executor.py`
(reason dispatch), `tests/regate-fail-closed.sh::case_park`, the T179/T184 wiring and
`GROUPS-PASSED` emission in `tests/run-tests.sh`, `docs/dev-plugin.md` (gate.sh `--all` row l.110,
park row l.134, Regate paragraph l.150, doctor paragraph l.154), `docs/dev-python.md` (state.py
row l.25, gate row l.61, park row l.70, regate row l.71), `docs/dev-tests.md` (T179 row l.183,
T184 row l.187), `docs/howto/park-a-phase.md`, `re-verify-completed-gates.md`,
`block-pushes-on-failing-gates.md`, `howto-list.md` l.190, `README.md` l.44,
`tests/parity.sh` drift_case (`drift:cross`), `hb-lint.js`/`lint.py` duplicate-phase-id guards,
`docs/howto/gate-examples/prose-check.sh` marker logic.

Ran (mktemp fixtures / scratchpad, `HB_NO_GIT=1`, env unset per the suite's hygiene rule; the
live `.hb` was only read, never touched):

- `bash tests/replan.sh drift` → DRIFT-OK; `… cure` → CURE-OK; `… sweep` → SWEEP-OK;
  `… tick` → TICK-OK; full `bash tests/replan.sh` → REPLAN-OK;
  `bash tests/replan.sh --selftest` → REPLAN-SELFTEST-OK.
- An independent hand-built fixture (my own dag, my own hand-edit of a completed gate's pinned
  `cmd`, not the suite's helpers): node and python doctor both exit 1 with the byte-identical
  problem line "GATE_A: criteria drifted from the pinned evidence without sanction — sanction the
  revision through a full regate cycle: declare, rearm with evidence, fresh pass; git-restore
  first to retract the content"; both sweeps exit 1, exclude GATE_A from re-evaluation and
  annotate it (py: "⛔ 1 drifted gate(s) (criteria changed without sanction — counted FAILING):
  GATE_A"); both ticks wake `reason: criteria_drift` with the cure in `data.action`. The how-to's
  tripwire promises reproduce on both runtimes.
- The exact `hb` console forms the changed docs display, against the python CLI
  (`python3 -m heartbeat.cli`): `regate <id> --reason <why>` → accepted; `regate <id> --rearm
  --artifact <file>` → accepted; `gate <G> --check` / `gate --all` → accepted; `park <id>
  --reason …` / `unpark` → accepted; `detach <id> --reason …` / `reattach` → accepted; and the
  how-to's displayed declare form `hb regate <gate> <reason>` (positional reason) → **usage
  error, exit 2** (see G4).
- `bash docs/howto/gate-examples/prose-check.sh <the 11 ds2w docs>` → `ALL-PROSE-OK:11`
  (the marker is emitted only after every doc passes; a failing doc exits 1 before it prints).
- `bash docs/howto/gate-examples/docs-currency.sh` → DOCS-CURRENT-OK, exit 0.
- Full python suite: `PYTHONPATH=src ./.venv/bin/python -m pytest -q` → **171 passed**.
- Searched both suites exhaustively for any runnable assertion of the executor's behavior on
  `criteria_drift`: `grep -rn criteria_drift tests/ py/tests/` → only `tests/replan.sh` and the
  T184 group *title*; `replan.sh` never invokes `hb-exec.js` or `hb exec`; `py/tests/test_exec.py`
  has no drift case. (The behavior itself exists in code: `hb-exec.js` ~l.535 has a named
  `case 'criteria_drift': escalate(...); return 1`, and `executor.py` l.586–588 stops on any
  unhandled reason — true, but pinned by no test.)

Checks that held (summarized): the horizon rule is prohibition + sanctioned path ("plan ONLY the
phases whose spec is known now, and END the planned horizon with an explicit replan point" —
mandatory, not optional); replan-as-outcome says "NEVER weaken a gate, constraint, or review to
fit the old plan" and conditions `detach` on a *falsified claim* and `regate` on *dead premises*,
never on a blocked gate — I could not construct an escape-detach or gate-weakening reading;
no contradiction with AGENTS.md rules 3/5/6 or the continuation rule. The criteria_drift
reason-table row, hb.js PROTOCOL and protocol.py all name the same cycle (declare → DIFFERENT
actor rearms with evidence → fresh pass), git-restore appears only as retraction of the content,
and freeze stays confined to the `unsanctioned_drift` row. All eight changed `--all` surfaces
tell one story (drifted: excluded from re-evaluation AND counted FAILING, annotated;
pending regate: counted FAILING without re-run; both parked or not; exit 1) — no changed doc
retains the old parked-exit-0 truth. The tripwire walk described three times (how-to, dev-plugin
doctor paragraph, dev-python state.py row) is the algorithm `driftedGates`/`drifted_gates`
implement: current-dag final element (absent gate = always-different), ordered pairs, adjacency,
byte-exact strings, `!num`/`!bool:`/`!obj`/`!invalid` type classes identical across runtimes,
bare/import passes never pin, only (id, cmd) pinned. Every backticked `hb` verb in the changed
docs names a registered subcommand; every relative link resolves; PARK-PHASE-OK / REVERIFY-OK /
REPLAN-OK / REPLAN-SELFTEST-OK are the exact strings their named scripts print; T184 is wired on
`grep -q "^REPLAN-OK"` / `"^REPLAN-SELFTEST-OK"` and `GROUPS-PASSED` lists only groups with zero
failing checks and at least one registered check. ds2w/ds2x/ds2q run real behavior; none is
satisfiable by a stub I could construct.

## Per-id answers

P1: VIOLATED — `docs/howto/plan-to-the-horizon.md` l.73: "and `hb exec` escalates and stops on
it." sits inside the bullet list introduced (l.62) by "What that catches, each anchored in
`tests/replan.sh`" — but no runnable proof anywhere anchors it: `tests/replan.sh` never invokes
an executor, and `grep -rn criteria_drift tests/ py/tests/` finds no exec/driver assertion in
either suite (only replan.sh and the T184 group title). The behavior exists in code
(`hb-exec.js` `case 'criteria_drift'`; `executor.py` generic stop) but the constraint's bar is a
runnable anchor that exists and passes, and this claim has none — a reader who deletes the
hb-exec case or makes the driver continue past drift leaves every cited proof green. Everything
else under this id held: the re-specified how-tos and the three dev-doc rows match the shipped
semantics (reproduced on my own fixture + case_park + case_sweep), all 27 distinct backticked
`hb` verbs are registered subcommands, links resolve, ALL-PROSE-OK:11.

P2: NOT-REPRODUCED — probes: misreading-construction against SKILL.md l.45–56 (horizon rule) and
l.104–110 (replan-as-outcome) and the how-to l.50–53. The replan point is stated as a required
terminal task ("END the planned horizon with an explicit replan point"), the UNSOUND resolution
enumerates only sanctioned surface and closes with "NEVER weaken a gate, constraint, or review to
fit the old plan (strengthening is also a revision: it goes through the same regate cycle)";
detach is tied to "the falsified dependency claim" and regate to "a gate whose premises died" —
neither is presented as a way past a blocked gate, and the gate_blocked row separately says
"never weaken the gate". I could not build an escape reading.

G1: VIOLATED — two anchor-infidelity instances, both reproduced by reading the cited case bodies.
(1) `docs/howto/plan-to-the-horizon.md` l.72–73: "both ticks wake the human-needed
`criteria_drift` reason every tick until cured, ahead of task dispatch (`case_tick`), and
`hb exec` escalates and stops on it." — `case_tick` (replan.sh l.429–462) asserts tick reasons,
action text, every-tick persistence and the cure, but contains no `hb exec`/`hb-exec.js`
invocation or assertion; the exec-on-drift behavior is asserted nowhere in either suite, so
breaking it leaves the cited anchor green. (2) l.92–93: "Sanctioned mutations stay quiet: a
declared regate's window, the full declare→rearm→fresh-pass flow, `detach`/`reattach`, and an
append (`case_quiet`)." — `case_quiet` (l.192–217) asserts the window, the flow and
detach/reattach, but the append-quiet assertion lives only in `case_append` (l.160,
`assert_quiet … "append (an append is sanctioned quiet)"`): the behavior is tested in a different
case than the one the sentence names. All other anchors are faithful: d1–d7, case_sweep w1–w5,
case_cure's four absolve-nothing steps and the old-cycle step, selftest s1, case_append,
case_unstarted, park-a-phase's bullet (regate-fail-closed case_park asserts parked+pending-regate
exit 1, not evaluated, annotated, both runtimes), and every behavior G1 enumerates from the
dev-tests T184/T179 rows (launder d2, bare-pass shadow d3, reorder d5, removal d4, old pre-drift
cycle case_cure, desc/timeout_s quiet d6, parked-pending-regate counted failing case_park +
case_sweep w3). Side note, same class but outside the enumerated list: the T184 row
(dev-tests.md l.187) also claims "degenerate ids classifying identically and rendering `?`" —
implemented in both lints (hb-lint.js l.36–41, lint.py l.23–31) but exercised by no test I could
find (replan.sh s1 uses a well-formed duplicate id; the parity fuzz generator emits only
well-formed phase ids).

G2: NOT-REPRODUCED — probes: read all six subject docs' sweep text side by side
(park-a-phase l.34–38, re-verify l.31–38, block-pushes l.27–31, dev-plugin l.110/134/150,
dev-python l.61/70, dev-tests T179/T184 rows) and grepped the changed docs for any surviving
old-truth phrasing ("never failing the sweep", annotated-skip-at-exit-0) — none; every surface
states drifted = excluded + counted FAILING annotated, pending regate = counted FAILING without
re-run, both parked or not, non-zero exit; reproduced live on my own fixture (both sweeps exit 1,
drifted gate not re-evaluated, annotated) and by case_park/case_sweep.

G3: NOT-REPRODUCED — probes: byte-compared the four cure surfaces. SKILL.md's criteria_drift row,
hb.js PROTOCOL l.58 and protocol.py l.18 all name the identical full cycle (declare → a DIFFERENT
actor rearms with evidence → fresh pass) with git-restore only as retraction of the content; the
how-to's cure paragraph (l.75–82) names the same cycle and adds only conditions replan.sh pins
(whole cycle postdates the drift; bare declare / declare+rearm / cross-gate / old pre-drift cycle
absolve nothing — all in case_cure, all green when run); no changed doc offers `tick.sh --freeze`
or an edit-past as a criteria_drift resolution — freeze appears only in the unsanctioned_drift
row. (Action-text arg-style differs per runtime by design; the substance is identical.)

G4: VIOLATED — `docs/howto/plan-to-the-horizon.md` l.75: "declare (`hb regate <gate> <reason>`)".
Reproduced: `PYTHONPATH=py/src python3 -m heartbeat.cli regate GATE_A premise died --dir <fixture>`
→ exit 2, "hb: error: unrecognized arguments: premise died" — `cli.py` l.82 registers `regate`
with only a positional `id` and a `--reason` option. The doc carries no node-form label at this
line, while the same doc uses `hb <verb>` as the python console elsewhere (l.69 pairs
"`gate.sh --all`, `hb gate --all`" as the two runtimes' sweeps), and the repo's own precedent
labels exactly this divergence (park-a-phase.md l.17 "Node runtime: …"; dev-python.md l.71 calls
it "the park arg-style divergence" and labels the node twin). The rearm form in the same sentence
(`hb regate <gate> --rearm --artifact <file>`) parses fine on python — so the one sentence mixes
a node-only declare spelling with a py-valid rearm spelling, unlabeled. An operator on the python
runtime following the cure paragraph verbatim gets a usage error at the exact moment the doctrine
is guiding them. Everything else under this id held: every other displayed command parses on its
runtime (verified live), the four promised markers are the exact strings the named scripts print
(replan.sh l.529/538; park-phase.sh l.66; gate-reverify.sh l.59), and T184 is outcome-keyed on
the replan markers (run-tests.sh l.1976–1979).

G5: NOT-REPRODUCED — probes: read `hb.js::canonField/canonCrit/driftedGates` (l.894–935) and
`state.py::_canon_crit/drifted_gates` (l.260–327) line by line against the three descriptions.
Every load-bearing property is implemented as described: pins = gate_passed with a non-empty
criteria array only (bare/import passes never pin or seed), current dag criteria appended as the
final element with pos ∞ (gate absent from dag → null → always-different → removal trips),
identity = per-criterion compact-JSON of (id, cmd) with strings byte-exact and out-of-schema
values as a type class (`!num` for all numbers, `!bool:x`, `!obj`, `!invalid` for non-dict
entries — identical tokens both runtimes), comparison only of ADJACENT pairs, sanction = a
gate_regated strictly between the pair's positions, absolution = the last completed cycle's
declare after the pair's later point, desc/timeout_s never read. The how-to's tripwire section,
dev-plugin's doctor paragraph + `--all` row, and dev-python's state.py row agree on all of it
(dev-python's "canonical (id, cmd) identity" is the same canonicalization, not a divergence);
d7a–d7f and my own fixture confirm the classifications live, and parity.sh `drift:cross` holds
the problem bytes twin-identical.

## Overall finding

DS2's substance is real: the tripwire, sweep, tick and cure behave exactly as documented on both
runtimes (reproduced independently of the suite's own helpers), the doctrine wording resists the
escape/weaken misreadings, the eight `--all` surfaces are mutually consistent, prose-check,
docs-currency and the full python suite are green, and the T184 anchor is outcome-keyed. The
failures are three documentation-integrity defects in the new how-to — one displayed command its
own runtime rejects (the cure's declare form, G4), one behavioral claim with no runnable proof
anywhere (`hb exec` on drift, P1/G1), and one claim anchored to the wrong case (append-quiet to
case_quiet, G1) — exactly the rot-resistance this docs phase exists to guarantee. The phase is
not refutation-proof as shipped; the fixes are small (label or re-spell one command; anchor or
drop the exec clause, or add the missing exec-on-drift case; re-point the append-quiet anchor at
case_append), but per the gate's own bar they are findings, not footnotes.

REFUTED (3 ids: P1, G1, G4)
