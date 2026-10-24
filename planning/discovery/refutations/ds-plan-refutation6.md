# Plan refutation — Wave 3 "discovery" (DS1 / DS2), ROUND 6 (focused convergence check)

Refuter: round-6 verification of the round-5 folds against
/home/curtism/Drums/lab/heartbeat/.hb/dag.json. Tree at **7cc9595 — the same commit
rounds 4–5 probed**, working tree clean, so every file:line citation from earlier rounds
remains checkable (each load-bearing one re-checked live below). The repo tree and the
live `.hb/` were untouched; lint/audit ran against a COPY in mktemp
(`/tmp/tmp.OlZiPJm6pJ/dag-copy.json`, removed after).

Round-6 job: (1) verify the six round-5 changes landed exactly; (2) fold-introduced-defect
check (coherence, P3 subjects vs the recorder rule, GATE_DS2 P1 envelope); (3) last sweep —
lint + audit both runtimes, dangling cross-references.

Verdict summary: all six folds landed verbatim and every baked-in citation is true today;
lint and audit are clean and byte-identical across runtimes; P3's widened subjects are all
wave-changed files and sail under the recorder rule; GATE_DS2 P1's claim is well inside the
house envelope. But the F26 fold recreated, in GATE_DS2 P1, the exact claim/subject
correspondence gap this wave has folded four times (F5, F17, F24, F25): the claim now pins
the truth of rows in dev-plugin.md and dev-python.md while the subjects name neither file —
and the reviewer answering P1 is the ONLY net for those rows' truth (round 5's own F26
rationale). One two-path fix. Plus one minor: the `_meta.design` honesty fold introduced a
false clause ("checked by the suites' existing prose floor" — no suite prose-checks
planning/). UNSOUND.

---

## 1. The six round-5 changes, verified in the dag text

**F25 — P3 subjects gained the three check-hosting files. LANDED.** GATE_DS1 P3 subjects
are now nine, ending:

    "tests/run-tests.sh",
    "tests/regate-fail-closed.sh",
    "py/tests/test_gate.py"

(after `"plugin/templates/gate.sh"`, `"py/src/heartbeat/gate.py"`,
`"plugin/templates/tick.sh"`, `"py/src/heartbeat/tick.py"`,
`"plugin/templates/hb-exec.js"`, `"tests/replan.sh"`). ✓

**F26 — ds2c mandates RE-SPECIFYING the three rows; GATE_DS2 P1 carries their truth.
LANDED (but see R6-F27).**
- ds2c: "AND the three rows the parked-count flip FALSIFIES are re-specified, not merely
  added to — dev-tests.md's T179 row ('never failing the sweep'), dev-plugin.md's
  parked-pending-regate sentence (l.150), dev-python.md's park row (l.70) — each must state
  the new truth: parked silences neither drift nor a pending regate in the --all count". ✓
- GATE_DS2 P1 claim: "…as are the three re-specified dev-doc rows the parked-count flip
  falsifies (dev-tests' T179 row, dev-plugin's parked-pending-regate sentence, dev-python's
  park row)". ✓

**Minor a — the two py gate tests named. LANDED.** ds1a: "the two py/tests/test_gate.py
sweep tests (l.203, l.232)"; ds1b: "the two py/tests/test_gate.py sweep tests at l.203 and
l.232". ✓ Verified today: py/tests/test_gate.py:203 =
`def test_all_dedup_respects_timeout_and_failure(tmp_path):`, :232 =
`def test_sweep_flake_probe_labels_but_never_absolves(tmp_path):`.

**Minor b — "in ds1b's change". LANDED.** ds1a: "are re-specified to the new contract in
ds1b's change — updated, never weakened". ✓ (Antecedent unambiguous; the ds1a doer no
longer has a reading that reddens wired suites mid-phase.)

**Minor c — the PROTOCOL.md regeneration note. LANDED.** ds1b: "the PROTOCOL.md template
(it regenerates from the hb.js table — one edit point serves both)". ✓ True today:
plugin/bootstrap.sh:113 `node "$HB_DIR/hb.js" protocol --md > "$HB_DIR/PROTOCOL.md"`.

**Minor d — `_meta.design` prose-scope sentence reworded. LANDED, but the new clause is
false (R6-M1).** The sentence now reads "GATE_DS2 pins prose-check over the 11 named docs
(parity-notes.md is owned by ds1c and checked by the suites' existing prose floor)". The
"11 named docs" half and the ds1c-ownership half are true; the prose-floor half is not —
see R6-M1.

## 2. Fold-introduced-defect checks

**Coherence.** All six edited sentences read coherently in context: ds1a's (sweep) case
hands the re-spec to ds1b explicitly; ds1b's four-surface list now acknowledges the
template/table single edit point without dropping either surface; ds2c's re-spec clause
states the falsified text, the three exact locations and the replacement truth; GATE_DS2
P1's lengthened claim parses as one sentence with the three rows as a parallel clause. The
quoted falsified phrases match the files today: docs/dev-tests.md:183 contains "park
composes (annotated, never failing the sweep)"; docs/dev-plugin.md:150 contains "the --all
sweep COUNTS the gate failing whether armed or planned (a parked one stays retired but its
pending regate is annotated in the parked line)"; docs/dev-python.md:70 is the park row
("resolver/audit/report/sweep all skip it, loudly").

**P3 subjects vs the recorder rule.** The actual rule (hb.js:928–958 `groundingErrors`,
twin constraints.py:139, both enforced only at `hb constraints --record`, hb.js:1080 /
constraints.py:199) is: at least ONE subject per constraint must be a file in the phase's
`hb changed` list or a directory holding one — "Areas and unchanged files may sit
alongside" (hb.js:932). Plan-time P<n> subjects are machine-checked only for non-empty
strings (hb-lint.js:184, lint.py:201–203). So the recorder cannot refuse P3; and even
under the strictest reading, all nine P3 subjects ARE files the phase changes per the task
texts: replan.sh (ds1a authors), gate.sh/gate.py/tick.sh/tick.py/hb-exec.js (ds1b's sweep,
tick and protocol work), run-tests.sh (ds1b re-specifies T160.3/.4+T161.2; ds1c wires
T184), regate-fail-closed.sh (ds1b re-specifies case_park), py/tests/test_gate.py (ds1b
re-specifies l.203/l.232). No break.

**GATE_DS2 P1 envelope.** Measured: claim 85 words / 681 chars (violation 23 words).
House maximum from the archived planning/detach.dag.json: GATE_DT1 P1 = 141 words /
1021 chars (then P3 131, P2 120, GATE_DT2 P1 115). 85 ≤ 141 with a third to spare; the
wave's own largest (GATE_DS1 P2 at 139) also stays ≤ 141. Within envelope.

## 3. Last sweep

**Lint + audit, both runtimes, mktemp copy.** Node: `✓ DAG valid (0 warning(s))`,
`✓ gates look behavioural (0 warning(s))`, both rc 0. Python (heartbeat.cli): identical.
JSON projections byte-identical under the parity.sh idiom: audit `[0,0,[]]` ≡ `[0,0,[]]`,
lint `[]` ≡ `[]`.

**Cross-reference sweep.**
- Constraint-id references in prose: exactly one — GATE_DS1 prompt (e) "either breaks P2";
  correct post-split (detection + cure live in P2). No stale/renumbered id anywhere.
- Every path the dag names exists today (all 24 checked: the 11 ds2w docs,
  prose-check.sh, docs-currency.sh, the 9 P3 subjects, parity-notes.md, state.py,
  doctor.py, hb-lint.js, lint.py); docs/howto/plan-to-the-horizon.md and tests/replan.sh
  are the two the wave produces (ds2b, ds1a) — each criterion naming them depends on the
  producing task's phase.
- Baked-in line anchors re-verified today: hb.js:107/185 and state.py:83/169
  (last_updated), gate.sh:253+ (the pending-regate sweep precedent region), SKILL.md:244
  the sole 'fill in' occurrence (count 1), test_gate.py:203/:232, dev-plugin.md:150,
  dev-python.md:70, dev-tests.md:183.
- ds2w's cmd lists exactly 11 paths and greps `^ALL-PROSE-OK:11`; the six-checks list is
  worded consistently at ds1a, ds1b, P3 and prompt (f); no prompt probes a case no task
  specs (prompt (h)'s rebuild-survival is a direct property of doctor being a pure
  function of events+dag, probed independently by the refuter per the prompt's own
  "build the fixtures YOURSELF" instruction — unchanged by the folds).

## R6-F27 — BLOCKING (fold-created). GATE_DS2 P1's claim pins the truth of rows in dev-plugin.md and dev-python.md; its subjects name neither file

The F26 fold extended P1's claim with "as are the three re-specified dev-doc rows the
parked-count flip falsifies (dev-tests' T179 row, dev-plugin's parked-pending-regate
sentence, dev-python's park row)" — but P1's subjects stayed at six:
plugin/skills/heartbeat/SKILL.md, docs/howto/plan-to-the-horizon.md, docs/dev-tests.md,
docs/howto/re-verify-completed-gates.md, docs/howto/block-pushes-on-failing-gates.md,
docs/howto/park-a-phase.md. dev-tests.md covers the first row; docs/dev-plugin.md and
docs/dev-python.md appear in no DS2 constraint's subjects.

Why it matters (round 5's own F26 rationale): nothing deterministic checks those rows'
TRUTH — ds2w is prose style (a false sentence passes), ds2x is v1.29-era token currency —
so the reviewer answering P1 is the only net. Subjects are the machine-rendered coverage
list that steers that reviewer: refuter_profiles.py:304 prints each constraint's
`subjects:` line into the gate-time refuter prompt (and hb.js:977 into the constraint
author's). Two of the three evidence files are absent from it.

This is the defect class the wave's own rounds folded four times — F5 (round 1), F17
(round 3), F24 (round 4: when P1's claim gained the three how-tos' truth, ALL THREE files
joined subjects, and round 5 verified the subject presence as part of the resolution), F25
(round 5, blocking). The F26 fold recreated the gap in the very constraint F24 had fixed.
(Distinct from round 5's M5, which was harmless because deterministic ds2w already caught
the claimed property; here nothing deterministic does.)

Required dag change (two array entries): add `docs/dev-plugin.md` and `docs/dev-python.md`
to GATE_DS2 P1's subjects. Envelope unaffected (subjects are not the measured claim; P3
already carries nine).

## R6-M1 — minor (recommendation; same class round 5 ruled non-blocking). `_meta.design`'s reworded prose-scope clause is false

The M2 fold produced "(parity-notes.md is owned by ds1c and checked by the suites'
existing prose floor)". No suite prose-checks planning/parity-notes.md: the suites' prose
floor is T93.1 (tests/run-tests.sh:1256–1258), whose glob is `find docs -name '*.md'` plus
root `*.md` minus CLAUDE.md — planning/ is outside it; repo-wide, the only suite check that
touches parity-notes.md is T137.1 (doc-fixture-count.sh — the audit-fixture COUNT, a
currency check, not prose), and no tests/*.sh, py test or docs-currency.sh references it
otherwise. (The file does pass prose-check when run by hand today — but nothing runs it.)
Non-operative narrative with no operative consumer, exactly R5-M2's class, so not
independently blocking — but since R6-F27 requires touching the dag anyway, fix it in the
same fold, e.g.: "(parity-notes.md is owned by ds1c; planning/ sits outside the suites'
docs-and-root prose floor by design — it passes prose-check today, unwired)".

---

Everything else converged: all six round-5 folds landed verbatim with every baked-in
citation true at 7cc9595; the edited sentences are coherent; P3's widened subjects are all
wave-changed files and cannot trip the recorder; GATE_DS2 P1 is well inside the detach-wave
envelope; lint and audit are clean and byte-identical on both runtimes; and no renumbered
id, unspecced probe or unproduced file dangles. One surgical finding requires dag text
(R6-F27: two subject paths), with R6-M1's one-clause rewording to take in the same fold.

UNSOUND
