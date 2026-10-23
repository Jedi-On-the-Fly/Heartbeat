# GATE_RG3 refutation — ROUND 2 (focused verification after the P2 fix)

Round 1 REFUTED on exactly one id: P2 — the report marker (this phase's own shipped behavior) was
absent from the runtime dev docs. This round verifies the fix and spot-checks that nothing else
moved. All probes in mktemp fixtures under the scratchpad and on COPIES; the repo tree and its
.hb/ untouched.

## 1. The fix, read as a skeptic (docs → shipped behavior)

The marker is now described in THREE places, and every claim in them was checked against the live
renderers:

- **docs/dev-plugin.md:34** (`hb-report.js` component row): "a phase whose gate is under a pending
  regate carries `⛔ revised — rearm pending (by <actor>: <reason>)` on its text line (cleared by a
  valid rearm; `--json` untouched)".
- **docs/dev-plugin.md:148** (Regate section): "Report surfacing: `hb-report.js` (and python
  `hb report`) mark a pending-regate phase line with `⛔ revised — rearm pending (by <actor>:
  <reason>)` — gone after a valid rearm, absent on a never-regated project, and never in the
  `--json` output (text render only)."
- **docs/dev-python.md:33** (`report.py` module row): "`render` marks a pending-regate phase line
  `⛔ revised — rearm pending (by <actor>: <reason>)` (cleared by a valid rearm; `--json`/`build`
  untouched; == node, T181)".

Accuracy probes (fresh mktemp fixture, task b1 done, `HB_ACTOR=alice node .hb/hb.js regate GATE_B
volumes were replaced`):

- **Exact marker text**: `grep -cF "⛔ revised — rearm pending (by alice: volumes were replaced)"`
  → 1 on the node text report AND 1 on the python text report. The documented template matches the
  shipped format strings verbatim (hb-report.js:143, report.py:82).
- **`--json` boundary**: on the pending fixture, `node .hb/hb-report.js .hb --json` and python
  `hb report --json` each contain 0 occurrences of `rearm pending`/`revised`/`⛔`. Source confirms
  the boundary structurally: node's `regateNote` (line 143) is defined/used after the `--json`
  early exit at line 133; python's marker lives only in `render()` (lines 81–82), never `build()`
  — so "`--json` untouched" and "`--json`/`build` untouched" are both literally true.
- **Cleared by a valid rearm**: revised criteria + evidence citing GATE_B/b1 +
  `HB_ACTOR=bob … --rearm --artifact` on the same fixture → 0 marker tokens in both text reports.
- **Absent on a never-regated project**: fresh quiet fixture → 0 occurrences of
  `regate|revised|rearm|⛔` in both text reports.
- **The row's companion claims**: `== node, T181` — T181 is registered (tests/run-tests.sh:1927,
  checks T181.1/T181.2 at 1930/1932); the Regate section's strip-clean sentence names three proof
  scripts with `--selftest` — all three (regate-fail-closed.sh, regate-rearm.sh,
  regate-surfacing.sh) grep-confirmed to carry one; guard markers exist where claimed
  (`regate-guard` count: hb-report.js 2, report.py 2, gate.sh 6).

**rg3c satisfied in the runtime docs**: the plan's "doctor/diagnose/report surfacing" bullet for
dev-plugin.md is now covered for all three — doctor (line 148 "doctor: a pending regate is a
note…" + line 150), diagnose (line 150 incl. `regate_pending` branch + rearm-recovery routing),
report (line 148 "Report surfacing:" sentence + the line-34 component row). dev-python.md's
report.py row carries the python side. The behavior is no longer described only in dev-tests.md's
T181 catalogue row.

## 2. Spot-checks — nothing else moved

| Check | Result |
|---|---|
| `bash tests/regate-surfacing.sh` | MARKER-OK, CLEAR-OK, QUIET-OK, REGATE-SURFACING-OK, exit 0 |
| `bash tests/regate-surfacing.sh --selftest` | REGATE-SURFACING-SELFTEST-OK, exit 0 |
| `bash docs/howto/gate-examples/prose-check.sh docs/dev-plugin.md docs/dev-python.md` | PROSE-OK:dev-plugin.md, PROSE-OK:dev-python.md, ALL-PROSE-OK:2, exit 0 |
| Dead helper gone | `grep -n "reports()" tests/regate-surfacing.sh` → no match (exit 1); the file now defines `both_have`/`both_lack` (lines 31–43), both called by every case |
| Renderers unchanged since round 1 | guard lines at the same places round 1 recorded (hb-report.js:143/146, report.py:81/82; 2 `regate-guard: report` lines each), identical marker strings |
| G1 strip re-probe | `sed -i '/regate-guard: report/d'` on a copy of `.hb/hb-report.js` and of `py/src` → both render the pending fixture with exit 0, Phases section and phase row intact, no error text — the same report minus the marker |
| G3 re-extraction over the AMENDED docs | 25 distinct backticked `hb <verb>` phrases (identical set to round 1 — the fix introduced no new verb); every one resolves in the python CLI registry, none hits argparse invalid-choice |

Round 1 (rg3-refutation.md) already ran the full perimeter: full node suite (464 passed, 0 failed,
GROUPS-RAN 181 incl. T179/T180/T181), full pytest (165 passed), parity (PARITY OK), the byte-level
pre-feature comparisons, the stripped-copy cmp-equality on four fixture×runtime combinations, and
every documented regate command verbatim. The fix touched only docs/dev-plugin.md,
docs/dev-python.md and tests/regate-surfacing.sh; my re-runs above confirm the behavioral surface
is exactly where round 1 left it, and the stated gate re-pass (6/6 deterministic criteria, suites
inside) is consistent with everything re-probed here.

## Answers

P1: NOT-REPRODUCED — round 1 verified in full (marker loud on both runtimes, cleared by cross-actor rearm, never-regated report byte-identical to pre-feature HEAD renderers); this round's re-runs on a fresh fixture confirm: both phase lines carry the exact string "⛔ revised — rearm pending (by alice: volumes were replaced)", 0 marker tokens after a valid bob rearm, 0 on a quiet fixture, and the renderers are unchanged since round 1 (same guard lines/strings).
P2: NOT-REPRODUCED — round 1's gap is closed: the marker is described in docs/dev-plugin.md twice (hb-report.js row, line 34; "Report surfacing:" sentence in the Regate section, line 148) and in docs/dev-python.md's report.py row (line 33), each stating the exact marker text (grep -F of the documented template instantiated with the fixture's actor/reason matches the live line on BOTH runtimes), the rearm-clear, the never-regated silence and the --json boundary (verified: 0 marker tokens in either runtime's --json; node marker code sits after the --json early exit, python's only in render()); rg3c's "doctor/diagnose/report surfacing" is now fully present in the runtime docs, not just dev-tests.md's T181 row; prose-check green on both amended docs; T181 and the three --selftest proof scripts named by the new prose all exist as claimed.
G1: NOT-REPRODUCED — round 1 verified cmp-equality on four fixture×runtime combinations; re-probed this round: after stripping both `regate-guard: report` lines from copies, node and python each exit 0 on a pending-regate fixture and print the complete report (Phases section and phase row intact, no ReferenceError/NameError/traceback) minus only the marker; --selftest green over the intact tree.
G2: NOT-REPRODUCED — round 1 verified byte-identity (python raw; node modulo only the per-run `generated` timestamp, the noted drafting looseness); re-probed this round: neither runtime's --json on the pending fixture contains "rearm pending", "revised" or "⛔", and the renderers' JSON paths are untouched since round 1 (marker code unchanged, after node's --json exit / outside python's build()).
G3: NOT-REPRODUCED — re-extracted over the four changed docs as amended: the same 25 distinct `hb <verb>` phrases as round 1 (the fix added no new verb), every one a registered subparser in py/src/heartbeat/cli.py (none yields argparse's invalid-choice error); prose-check prints PROSE-OK for both amended docs.

## Verdict

Round 1's single finding is fixed accurately — the docs now describe the shipped marker, and every
sentence of the new description was checked against live behavior and holds. Nothing else moved:
the dead helper is gone, the surfacing proof and its selftest are green, prose-check is green, the
renderers and the verb surface are exactly as round 1 verified them.

CLEAR — SOUND
