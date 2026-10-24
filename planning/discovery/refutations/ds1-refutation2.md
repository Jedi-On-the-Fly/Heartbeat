# DS1 round-2 refutation (GATE_DS1)

Phase DS1 (replan contract / drift tripwire). Ran, all in mktemp fixtures (plugin/bootstrap.sh) or COPIES, HB_NO_GIT=1, env vars unset, HB_ROT_CHECK unset; live .hb untouched:
- Round-1 hostile matrix /tmp/ds1r/t1.py (node hb.js doctor vs python cli doctor), new numeric/unicode/nested matrix t8.py, t9.py.
- Lint matrix t2.py + t10.py (id-less, two id-less, null/int dup, id-less with 9 tasks).
- Drift/cure event-level matrix t12.py (9 shapes, both runtimes' doctor).
- P4 strip test: copy of py/src, `sed -i '/drift-guard: tick/d'` tick.py and `'/drift-guard: sweep/d'` gate.py+cli.py -> `import heartbeat.cli, tick, gate` OK; on a drifted fixture (t11.py) the stripped runtime tick falls back to next_task and `gate --all` prints ALL GATES PASS (rc 0), real runtime wakes criteria_drift / rc 1.
- bash tests/replan.sh -> REPLAN-OK; --selftest -> REPLAN-SELFTEST-OK; tests/parity.sh -> PARITY OK. dev-tests.md now has a T184 row.

## Folds verified REAL
- G2 original shapes: pin id missing vs dag id null, pin id null vs dag missing, cmd missing vs null: now quiet on BOTH. true vs "true": DRIFT on both. 1.0 vs 1: quiet on both. Non-dict pin entry: DRIFT on both, no traceback. Nested object id, key-order difference, 2^60, 1e-7, -0.0 vs 0, astral/NFC-vs-NFD unicode, lone surrogate, 1e21 int vs float: all agree.
- G5 original: id-less phase, two id-less phases, null/int ids, 'A' dup, triple dup: lints agree (dup string ids error "duplicate phase ID: A" on both).
- P4: strips are clean one-liners; teeth vanish on strip (above).

## Findings (reproduced, remaining)
F1 (G2) The numeric canonicalization still splits at the JS/Python number boundary.
  - Dag criteria id 9007199254740992, pin id 9007199254740993 (JS parses both to the same double -> node QUIET). Python: _canon_crit maps the >2^53 int to float -> dumps "9.007199254740992e+15" vs exact-2^53 int "9007199254740992" -> python DRIFT. node doctor 3 problems, python 4 problems (GATE_X: criteria drifted). Repro: /tmp/ds1r/t9.py.
  - Pin id 1e400 (raw JSON) vs dag id null: node JSON.stringify(Infinity) -> null -> QUIET; python json.dumps(inf) -> "Infinity" -> DRIFT. Repro: /tmp/ds1r/t8.py.
  The fold's claim "python >2^53 ints to float to match JS semantics" is wrong at the boundary (float repr switches to exponent form at 1e16, JS keeps integer form). Verdict split on the same log+dag = exactly the G2 violated-if.
F2 (G5) id-less phase with more than 8 tasks still crashes python lint: lint.py:34 `f"[{p['id']}] ..."` KeyError: 'id' (rc 1 traceback) while node prints "[undefined] 9 tasks (>8)" and "DAG valid" rc 0. The fold scoped only the duplicate rule, not the other p['id'] use. Repro: /tmp/ds1r/t10.py.
F3 (G5, scope) The rule is now narrowed to non-empty STRING ids: numeric duplicate ids (1,1) and null duplicate ids are accepted silently by both lints (identical, so no parity split, but "any repeated phase id ... rejected" is not met for those shapes).
F4 (side, doc/code contradiction) docs/dev-tests.md T184 row says "bare declare or declare+rearm cures nothing", but doctor goes QUIET after hand-edit + bare declare (t12.py 'bare declare' and 'declare+rearm' -> no drift on either runtime; tick proceeds per round 1). Behavior matches P2's text (declare between the points sanctions), the doc claim does not. Sweep still fails closed (pending regate).
Notes (pre-existing, not new): dag criteria as a string/object/null-entry crash both doctors in other code (hb.js:252, doctor.py:31); node driftedGates also throws `cur.map is not a function` on a string criteria; dag gates entry string/null crash python. Not counted.

## Per-id
P1: NOT-REPRODUCED — replan.sh green; append case untouched by this round's folds; no counterexample.
P2: NOT-REPRODUCED — t12.py: hand-edit, launder re-pass, bare-pass shadow, other-gate cycle, old cycle + re-pass all drift identically on both; full cycle cures; cycle-then-edit drifts again. (See F4: doc wording vs bare-declare behavior, spec text itself holds.)
P3: NOT-REPRODUCED — stripped-copy test shows sweep/tick teeth real; replan.sh SWEEP-OK/TICK-OK green.
P4: NOT-REPRODUCED — strips of tick/sweep guards from py COPIES import fine and remove the behavior (tick -> next_task, sweep -> ALL GATES PASS); selftest s7/s8 present and green; replan --selftest and parity green; T184 doc row present.
G1: NOT-REPRODUCED — spot-checked in round 1; replan.sh SWEEP-OK/TICK-OK and parity green this round, no change in the code path.
G2: VIOLATED — F1: 2^53+1 vs 2^53 and 1e400 vs null classify differently on node (quiet) vs python (drift); repros /tmp/ds1r/t9.py, t8.py.
G3: NOT-REPRODUCED — HB_ROT_CHECK unset throughout; py tick wakes criteria_drift on drifted fixture (t11.py), TICK-OK green.
G4: NOT-REPRODUCED — surfaces unchanged by the folds; no --freeze offered; round-1 verification stands.
G5: VIOLATED — F2: id-less phase with 9 tasks: py lint KeyError traceback (lint.py:34) vs node "DAG valid" rc 0. (F3 also: numeric/null dup ids not rejected.)
G6: NOT-REPRODUCED — re-specs unchanged by folds; full replan/parity green; not mutated again.

## Overall
REFUTED (2 ids: G2, G5). The folds repaired the originally reported shapes and P4, but the G2 canonicalization still splits on number-boundary values and the G5 fold left a second p['id'] crash in py lint.
