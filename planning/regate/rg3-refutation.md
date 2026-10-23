# GATE_RG3 refutation — whole-feature + docs review (adversarial refuter, unbound profile)

Phase under review: RG3 "surfacing + docs current-state" — the pending-regate report marker (both
runtimes) + dev docs/parity notes current-state. All work done in mktemp fixtures and copies; the
repo tree and its .hb/ untouched.

## Suites (all run by me, this session)

| Suite | Command | Result |
|---|---|---|
| Surfacing proof | `bash tests/regate-surfacing.sh` | MARKER-OK, CLEAR-OK, QUIET-OK, REGATE-SURFACING-OK, exit 0 |
| Surfacing teeth | `bash tests/regate-surfacing.sh --selftest` | REGATE-SURFACING-SELFTEST-OK, exit 0 |
| Perimeter proof | `bash tests/regate-fail-closed.sh` | REGATE-FAIL-CLOSED-OK, exit 0 |
| Rearm proof | `bash tests/regate-rearm.sh` | REGATE-REARM-OK, exit 0 |
| Full pytest | `cd py && PYTHONPATH=src .venv/bin/python -m pytest -q` | 165 passed, exit 0 |
| Parity | `bash tests/parity.sh` | "✅ PARITY OK — node ≡ python", exit 0 |
| Full node suite | `bash tests/run-tests.sh` | see "Full node suite result" below |

## P1 — surfacing loud, correct, non-invasive (probed directly, not via the proof script)

Fixture: bootstrapped mktemp project, task b1 done, `HB_ACTOR=alice node .hb/hb.js regate GATE_B
volumes were replaced`.

- Pending: node report phase line = `🔧 B reviewed work — 1/1  [gate: GATE_B]  ⛔ revised — rearm
  pending (by alice: volumes were replaced)`; python report line identical in substance. All four
  tokens (gate id, `revised`, `rearm pending`, reason) present on BOTH runtimes.
- Clear: criteria revised, evidence citing GATE_B/b1 written, `HB_ACTOR=bob … --rearm --artifact`
  accepted → both reports free of `revised` and `rearm pending`.
- Byte-unchanged: never-regated fixture rendered with the shipped renderers vs the pre-feature
  renderers (`git show HEAD:plugin/templates/hb-report.js`, `git show HEAD:py/src/heartbeat/report.py`):
  node text `cmp` equal, python text `cmp` equal, python `--json` byte-equal, node `--json` equal
  after normalizing only the `generated` run timestamp.
- Proxy note (not a violation): `case_quiet` in tests/regate-surfacing.sh asserts marker-word
  ABSENCE, a proxy for rg3a's "byte-unchanged" sentence. The strong byte-equal check needs the
  pre-feature renderer (git history), which a durable regression test cannot carry once this
  commits; I ran the strong check above and it holds today. Named for the record.
- Nit: `reports()` (tests/regate-surfacing.sh:31–35) is defined and never called — dead helper.

## P2 — docs current-state: one real gap found

Forward direction (docs → code), every documented item run verbatim on a mktemp fixture — all hold:

- Declare grammars: node trailing-words and python `--reason` both work; dag record keys exactly
  `{actor, at, pending, prev_criteria, reason}` with `pending: true`; `gate_regated` appended.
- Perimeter: `gate.sh GATE_B` → exit 3 with the documented refusal text; `--check` → exit 3;
  `--all` → "⛔ 1 regate-pending gate(s) … counted FAILING", exit 1; bare `gate.sh` usage → exit 2
  (so 3 is reserved vs 1 blocked / 2 usage, as documented); python `hb gate GATE_B` → prints
  `gate GATE_B: regate_pending`, exit 3 (the documented status→exit-3 mapping, live).
- Refusals while pending: `review pass`/`fail` refused on both runtimes with the documented
  message; `constraints --record` refused with the documented regate message on a CONSTRAINED gate
  (both runtimes); `anchor` refused; second declare refused ("already has a pending regate").
- Tick: `.hb/tick.sh` and python tick both emit `{"wakeAgent":false,"data":{"reason":
  "regate_pending_waiting","gate":"GATE_B"}}` — the documented non-PROTOCOL sleep reason, live.
- diagnose: both runtimes print `Diagnosis: regate_pending` + the 4-step rearm recovery;
  doctor: both runtimes print the documented pending note.
- Rearm bar: missing `--artifact` → documented usage refusal; same actor (alice) refused ("the
  rearm must come from a DIFFERENT actor"); thin artifact refused ("too thin (5 chars)"); uncited
  artifact refused ("expected one of: GATE_B, b1"). Valid rearm: evidence stored at
  `.hb/reviews/GATE_B.regate.md`, ONE sha256 identical across stored bytes ≡ `gate_rearmed` event
  ≡ dag `regate.rearm` record; `pending: false`.
- Post-rearm: review refused with the documented stale-pass message until `gate.sh GATE_B` passes
  fresh (exit 0 observed after); second declare+rearm OVERWRITES `reviews/GATE_B.regate.md`
  (last-rearm-wins, exactly as the honest-limits sentence says; one file in reviews/).
- Documented symbols exist where named: `gate.eval_gate` carries the refusal (`_regate_refusal`,
  py/src/heartbeat/gate.py:54–66, guard at run_gate:183), `review_policy.accept_review`
  (review_policy.py:41–47 incl. phase-id resolution, log-truth, stale-pass),
  `constraints.record`, executor writers (executor.py:309–312), node `hb-exec.js:439` exit-3
  escalation + `:506–507` review-fail wrap, `import` writes bare `gate_passed` (hb.js import case),
  `reviewCycle` cycle-start includes `gate_rearmed` (hb.js:674) ≡ `constraints._cycle_start`
  shared by `review_cycle` and `review_cycle_full` (constraints.py:33/43/55),
  `state.substantive_len/stale_rearm/unanswered_regate/with_wlock` all present.
- parity-notes: arg-style divergence recorded ("node declares with trailing words…, python with
  `--reason`"), exit-3 ≡ `regate_pending`-status equivalence recorded, and the named parity cases
  exist in tests/parity.sh (`regate:lint-malformed` line 54 with the non-empty-error guard at 56,
  `regate:declare-cross` line 82, `regate:rearm-cross` line 138). The dag-writer number-fidelity
  section is present above the Regate section.
- dev-tests.md: T179/T180/T181 rows present and matching registered groups in tests/run-tests.sh
  (grp lines 1887/1904/1927); the venv-pytest precondition line is present and the exact command
  it prescribes ran green.
- Honest-limits line present in dev-plugin.md: "the rearm bar is PROCEDURAL evidence inside the
  self-declared `HB_ACTOR` trust model, never mechanical proof — the human reviews the
  `prev_criteria` diff; each rearm overwrites `reviews/<G>.regate.md` (last-rearm-wins…); a forged
  event log is outside the model." Procedural-evidence ✓, prev_criteria diff ✓, last-rearm-wins ✓,
  forged-log boundary ✓. Nothing sells the bar as mechanical proof.

REVERSE direction (shipped behavior → docs) — THE FINDING:

**The report marker — this phase's own shipped behavior — is absent from the runtime dev docs.**
The plan's task rg3c reads, verbatim: "docs/dev-plugin.md: the regate verb (node grammar), the
fail-closed perimeter with the exit-3 refusal signal, the rearm evidence bar, stale-pass
invalidation, **doctor/diagnose/report surfacing**, executor escalation and the tick's
regate_pending_waiting sleep". The shipped dev-plugin.md Regate section (line 148) documents
doctor surfacing and (line 150) diagnose surfacing — but says nothing about report surfacing:
the word "report" does not occur in the Regate paragraph (`sed -n '148p' docs/dev-plugin.md |
grep -o "report…"` → zero matches; line 150 → 0), the `hb-report.js` component row (line 34)
still reads "Progress report (`--json`) + refuter-impact" with no marker, and
`grep -n "revised\|rearm pending\|⛔" docs/dev-plugin.md docs/dev-python.md` finds no description
of the marker anywhere in either runtime doc. dev-python.md's regate rows (lines 71–72) document
the chokepoints but not report.py's marker, and its report.py module row (line 33) is unchanged.
The only place the behavior is described is docs/dev-tests.md's T181 row — the test catalogue,
which rg3c assigns a different job (the new test groups + proof scripts). Per AGENTS.md rule 7
("Docs are source of truth, current-state only… describe what is"), a reader of the component
docs for hb-report.js/report.py — the two files this phase changed — does not learn the report
now carries a pending-regate marker, nor that its guard lines are strip-clean
(`regate-guard: report`). P2's violation clause — "a shipped regate behavior is absent from the
dev docs" — is met, and it is the one behavior this phase shipped.

## G1 — report guard strip-clean (probed on copies)

`grep -c 'regate-guard: report'`: 2 lines in each renderer. `sed -i '/regate-guard: report/d'` on
a COPY of `.hb/` (node) and of `py/src/` (python); no residual `regateNote`/`_rg` references.
Run on BOTH a pending-regate fixture (enriched with a prior `gate_passed` so the node Gates,
Phase-durations and Longest-tasks sections all render) AND a never-regated fixture, both runtimes:

- exit 0 everywhere; no ReferenceError/NameError/traceback text; Phases line, phase row, and the
  node Gates section all present.
- Stripped output `cmp`-equal to the original output with only the marker substring removed, on
  all four (fixture × runtime) combinations — "the same report minus the marker", exactly.
- So the property holds independently of the selftest (whose `grep -qi 'rearm pending'` indeed
  could not distinguish marker-gone from renderer-crashed — verified moot).

## G2 — JSON neutrality (probed on the pending fixture)

- python: `hb report --json` via shipped src vs guard-stripped copy → `cmp` byte-identical, raw.
- node: `hb-report.js <dir> --json` shipped vs stripped copy → raw bytes differ ONLY at the
  `"generated"` field (the per-run `new Date().toISOString()` timestamp, confirmed by inspecting
  the differing line); identical after normalizing that one field. Note for the record: the
  constraint's literal "differs by any byte" cannot hold on node for ANY two invocations — even
  the same renderer twice — because of that timestamp; the constraint's intent (no feature leak
  into JSON) is what I tested, and it holds. The marker lives entirely in the text path
  (hb-report.js line 143 executes after the `--json` early exit at 133; python `--json` routes to
  `build()`, which the diff never touched).
- Neither runtime's JSON contains `rearm pending`, `revised`, `⛔`, or `⛔`.

## G3 — doc verbs vs the python CLI registry

Extraction `grep -ohE '\x60hb [a-z][a-z-]*'` over the four changed docs yields 25 distinct verbs:
audit bench changed constraints diagnose doctor done evidence exec fail gate init mcp-serve next
park protocol ready rebuild refute-prompt refuters regate report review reward start. Every one is
a registered subparser in py/src/heartbeat/cli.py — start/done/fail via the loop at lines 47–48
(`python3 -m heartbeat.cli start|done|fail` each print their own `usage: hb start …`, not
argparse's invalid-choice error). `hb.js project` (parity-notes line 11) is `hb.js project()` —
the projector FUNCTION reference in a parity table, not a `hb <sub>` command phrase; the node-only
table verbs in dev-plugin.md (`import`, `anchor`, `evidence`, `changed`) all exist as cases in
plugin/templates/hb.js (lines 1514/975/1221/1046) and `anchor`'s regate refusal was exercised live.
No doc names a nonexistent verb.

## Gate-criteria falsification checklist

- rg3x/rg3y: the OK markers print only after every case passes (`fail()` exits 1 first);
  `REGATE-SURFACING-OK` is not a substring of `REGATE-SURFACING-SELFTEST-OK`; run-tests.sh T181
  greps them anchored (`^`). Not foolable by a header-before-red-run.
- rg3d: an honest grep FLOOR — its own desc says "the review's P2 does the deep read". It would
  pass on a stub; the deep read is this review, and the deep read found the P2 gap above.
- rg3p/rg3n/rg3q: run the real suites (no stubs); I re-ran parity and pytest myself (green) and
  the full node suite (below).
- Real runtimes exercised throughout: real bootstrapped .hb projects, real node + python CLIs,
  no mocks.

## Full node suite result

`bash tests/run-tests.sh` (full, this working tree): exit 0 — "RESULT: 464 passed, 0 failed",
"✅ ALL GREEN", GROUPS-RAN: 181, GROUPS-SKIPPED: 0; GROUPS-PASSED includes T179, T180 and the new
T181 (and T169, which runs the constraint-author.sh proof this phase's mutant-pattern edit
targets).

## Constraints-are-claims cross-check

G1/G2/G3 are consistent with the plan (rg3a/rg3b/rg3c) and sharpen it; none pins code-as-spec
against the plan. One drafting looseness recorded under G2 (node's `generated` timestamp makes the
literal any-byte clause unsatisfiable; intent tested and held). P1/P2 restate the plan faithfully;
P2's deep read is what surfaced the finding.

## Answers

P1: NOT-REPRODUCED — pending fixture: both runtimes' phase line carries GATE_B + "revised" + "rearm pending" + "volumes were replaced"; after a valid cross-actor rearm both reports are clean; never-regated fixture renders byte-identical (cmp) to the pre-feature HEAD renderers in text on both runtimes and in JSON (python raw; node modulo only the `generated` run timestamp).
P2: VIOLATED — the shipped report marker is absent from the runtime dev docs: rg3c requires "doctor/diagnose/report surfacing" in docs/dev-plugin.md, but the Regate paragraph (line 148) and the doctor/diagnose paragraph (line 150) never mention the report (grep for "report" in both lines: 0 matches), the hb-report.js row (line 34) is unchanged, dev-python.md's report.py row (line 33) and regate rows say nothing of the marker, and `grep -n "revised\|rearm pending\|⛔" docs/dev-plugin.md docs/dev-python.md` finds no description of it — the behavior is described only in dev-tests.md's T181 test-catalogue row; every forward-direction documented command/flag/exit-code/path/message I ran verbatim does exist and behave as written, and the honest-limits line is present and honest.
G1: NOT-REPRODUCED — after `sed -i '/regate-guard: report/d'` on copies (2 guard lines each), both renderers exit 0 on both a pending-regate and a never-regated fixture with Phases and Gates sections intact, output cmp-equal to the original minus the marker substring; no error text; the property holds independently of --selftest.
G2: NOT-REPRODUCED — python `hb report --json` is byte-identical raw between shipped and guard-stripped src on the pending fixture; node `--json` differs only in the `generated` timestamp field (inherent to any two runs — the constraint's literal any-byte clause is unsatisfiable on node, noted as drafting looseness; the intent holds) and neither JSON contains "rearm pending", "revised", "⛔" or "⛔".
G3: NOT-REPRODUCED — all 25 distinct backticked `hb <verb>` phrases across the four docs name registered subparsers (start/done/fail via the cli.py:47–48 loop, each printing its own usage rather than invalid-choice); `hb.js project()` is a function reference, not a command; node-only table verbs (import/anchor/evidence/changed) exist as hb.js cases.

## Verdict

One plan-pinned task deliverable (rg3c's "report surfacing" in dev-plugin.md) did not ship: the
dev docs do not describe the one behavior this phase added. Everything else — surfacing behavior,
guards, JSON neutrality, doc accuracy in the forward direction, verb integrity, all six suites —
held against every probe.

REFUTED — UNSOUND
