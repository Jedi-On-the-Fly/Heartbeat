# DS1 refutation (GATE_DS1) — adversarial refuter

What I ran (all in mktemp fixtures bootstrapped via plugin/bootstrap.sh; live .hb never touched; HB_NO_GIT=1, HB_DIR etc unset, HB_ROT_CHECK UNSET):
- tests/replan.sh (all cases -> REPLAN-OK) and --selftest (REPLAN-SELFTEST-OK); tests/parity.sh (PARITY OK); py pytest (171 passed).
- Hostile-log doctor matrix (hostile events.jsonl + dag.json, node hb.js doctor vs python cli doctor): /tmp/ds1r/t1.py.
- Phase-without-id / duplicate-id lint matrix on both lints: /tmp/ds1r/t2.py.
- Two-drifted-gate fixture (one hand-edited, one removed ever-pinned) incl. parked and unparked: doctor, tick, sweep on both runtimes: /tmp/ds1r/t3.py, t4.py.
- Real CLI cycle (complete H1-like gate via gate.sh, hand-edit, launder re-run, bare declare, same-actor rearm refused, different-actor rearm, fresh pass, re-edit): /tmp/ds1r/t5.sh, t6.sh.
- Stripping drift-guard lines from COPIES of py gate.py/cli.py/tick.py (/tmp/ds1r/pysrc).
- node tests/run-tests.sh (full).

## Findings (real, reproduced)
F1 (G2) node/python disagree on drift for degenerate id/cmd. driftedGates uses String(c.id) (undefined -> "undefined", null -> "null"); state.drifted_gates uses str(c.get("id")) (missing and null both -> "None"). Fixture: dag GATE_X criteria [{"id":null,"cmd":"true"}], log gate_passed GATE_X criteria [{"cmd":"true","exit":0}] (no id). node doctor: "GATE_X: criteria drifted ..." exit 1 (4 problems); python doctor: no GATE_X line (3 problems). Same split for pin id null vs dag id missing, and pin cmd missing vs dag cmd null. Also id true (pin) vs "true" (dag): node quiet, python drifts; id 1.0 (pin) vs 1 (dag): node quiet, python drifts (str(1.0)="1.0").
F2 (G2) python tracebacks where node reports: a pin criteria entry that is a non-dict (gate_passed criteria ["str"]) -> py state.py:279 c.get AttributeError traceback from doctor; node returns a normal doctor result. A gate_passed with a non-hashable gate (list) crashes python in project() (pre-existing) while node proceeds. Node also stack-traces in driftedGates (hb.js:899 cur.map is not a function) when a dag gate's criteria is a string/non-array (python crashes earlier, in doctor.py:31, so both crash but differently).
F3 (G5) python lint KeyError on a phase lacking "id": lint.py:25 `if p["id"] in phase_ids` (new in this phase's diff). Fixture: phases [{"title":"t","gate_entry":null,"gate_exit":"GATE_P0","tasks":[]}]. node hb-lint.js: "DAG valid (1 warning)" exit 0; python `hb lint`: Traceback ... KeyError: 'id', exit 1. Two id-less phases: node reports "duplicate phase ID: undefined" (error), python crashes. Also finding text differs for null ids: node "duplicate phase ID: null" vs python "duplicate phase ID: None".
F4 (P4) The selftest never strips the PYTHON sweep or PYTHON tick guards. replan.sh selftest s3/s4 strip doctor (node, py); s5 strips only plugin gate.sh; s6 only tick.sh. Python gate.py/cli.py/tick.py carry "drift-guard: sweep/tick" markers that no sabotage uses. Worse, the py tick markers sit on structural lines: py/src/heartbeat/tick.py:97-99 — stripping them leaves `if HB_ROT_CHECK != "0":` with no body -> IndentationError on import (reproduced). So "markers on strip-clean single lines, drift-guard lines (doctor, sweep, tick classes) stripped from COPIES of each runtime" does not hold for python sweep/tick. Also s5 passes vacuously if the strip makes the sweep exit 0 or crash (it only fails when exit==1 AND the annotation survives; the assertion does not check the named case reddens).
F5 (side) Node suite not green: tests/run-tests.sh T124.1 FAILS ("every guide is listed and every suite group is in the dev-tests table") — docs/dev-tests.md has no T184 row (last row T183). AGENTS.md rule 4/7 require suites green and docs in step. (May be deferred to a later docs phase, but the phase claim says "full ... green".) The run was still in T167 when I stopped waiting; only this one red was seen so far.

## Probed and held
- Two drifted gates (hand-edited GATE_P0, removed ever-pinned GATE_Z): both doctors print one line per gate in sorted order, byte-identical lines, exit 1; both sweeps annotate both ("2 drifted gate(s) ... GATE_P0 GATE_Z"), count +2, exit 1 even with zero evaluable gates ("re-verifying 0"), never ALL PASS; both ticks wake criteria_drift count=2 with HB_ROT_CHECK unset, even with ready P1 work (no next_task). Cosmetic: python tick also emits a "gates" list and python says "re-verifying 1" where node says 0.
- Parked (park P0 and P1): doctor still exit 1 naming both, tick still criteria_drift, sweep still counts 2 failing; rebuild preserves the verdict.
- Real CLI cycle: hand-edit -> drift (both runtimes); launder (plain re-run) -> still drift; declare after the launder pass -> still drift; same-actor rearm refused; different-actor rearm without fresh pass -> still drift; fresh pass -> cured on both (doctor quiet, tick proceeds); new hand-edit afterwards -> drifts again.
- Observation (not claimed as violation): hand-edit THEN bare declare, no pass: doctor goes quiet and the tick returns next_task (a one-actor declare sanctions the final pair per the code/spec text "gate_regated between the two points"); the sweep still fails (pending regate). The refute checklist wording "a bare declare cures nothing" is not what the code does, but P2's text matches the code.
- G4 surfaces: PROTOCOL.md row, `hb protocol criteria_drift` on both runtimes, hook text (both lists), mcp tick description, SKILL.md row, hb-exec.js escalate case all present; none offers --freeze for criteria_drift.
- replan.sh unset-line equals run-tests.sh/parity.sh line (comment prose differs, command identical); T184.1/.2 key on ^REPLAN-OK / ^REPLAN-SELFTEST-OK; parity has drift:cross with a non-empty-node check and a clean-twin floor. T160/T161 re-specs assert positive execution counts (2 y lines, 2 f lines, 3 failing criteria, exactly one probe), so a drift-excluded gate would fail them, not satisfy them.

## Verdicts
P1: NOT-REPRODUCED — replan.sh append case green; append lints 0 on both, H1 slice untouched, rebuild idempotent mod last_updated per its checks (I did not find a counterexample).
P2: NOT-REPRODUCED — real-CLI hand-edit, launder, same-actor rearm refusal, rearm-without-pass, full cycle cure and re-edit all behaved per spec on both runtimes with identical doctor lines (only degenerate-id cases diverge; filed under G2). Note the bare-declare observation above.
P3: NOT-REPRODUCED — sweeps exclude and count drifted gates (parked, removed, zero-evaluable), ticks wake criteria_drift with identical keys, exec driver case escalates; re-specified checks assert the new contract.
P4: VIOLATED — F4: python sweep and python tick drift-guards are never stripped by --selftest, and py tick.py:97-99 guard markers sit on structural lines (strip -> IndentationError, reproduced via `sed -i '/drift-guard: tick/d'` on a copy of py/src, then `import heartbeat.cli`).
G1: NOT-REPRODUCED — two-gate fixture, parked and unparked: doctor lines/order/bytes identical, sweeps +2 and zero-evaluable exit 1, ticks count=2 (/tmp/ds1r/t3.py, t4.py).
G2: VIOLATED — F1/F2: fixture dag id null vs pin id missing -> node doctor flags GATE_X (exit 1, 4 problems), python does not (3 problems); id true/"true" and 1.0/1 split the other way; non-dict pin entry tracebacks python (state.py:279). Script: /tmp/ds1r/t1.py.
G3: NOT-REPRODUCED — parked phases and ready work with HB_ROT_CHECK unset: doctor exit 1 and tick criteria_drift on both runtimes.
G4: NOT-REPRODUCED — all listed surfaces carry criteria_drift with the regate-cycle cure and no freeze path.
G5: VIOLATED — F3: id-less phase -> node lint exit 0 "DAG valid", python lint KeyError traceback (lint.py:25); duplicate/triple/valid cases otherwise agree ("duplicate phase ID: A" errors both). Script: /tmp/ds1r/t2.py.
G6: NOT-REPRODUCED — T160.3/.4, T161.1-.2 assertions pin positive run counts that a drift-excluded gate could not satisfy; I did not mutate the dedup memo/probe in a fixture copy.

## Overall
REFUTED — 3 violated ids (P4, G2, G5), plus side finding F5 (node suite T124.1 red: dev-tests.md lacks the T184 row).

## Addendum: full node suite result
tests/run-tests.sh finished: 472 passed, 2 failed. Failures: T124.1 (dev-tests.md lacks T184 row) and T184.1 (replan.sh -> REPLAN-OK) failed once inside the full run, while running concurrently with parity.sh and pytest. Standalone replan.sh passes on rerun, so T184.1 is load-sensitive/flaky under concurrency (not reproduced alone). Overall verdict unchanged: REFUTED (P4, G2, G5 violated).
