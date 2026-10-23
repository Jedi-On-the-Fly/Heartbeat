# GATE_DT1 refutation, round 2

Re-runs (all green, rc=0): tests/detach.sh (DETACH-OK), tests/detach.sh --selftest (DETACH-SELFTEST-OK), pytest full (171 passed), tests/parity.sh (PARITY OK, incl. detach:lint-reserved), tests/regate-rearm.sh, tests/regate-fail-closed.sh.

Round-1 exploits re-run:
- Reserved-name lint twins, 10 hostile gate names through both lints: "_start\n", "_start ", " _start", "_START", "_detach_", "_detach_X", "_start\r", "_detach_\n", "x_detach_y", "_starting". Node and python AGREE on all 10 (errors only for _detach_, _detach_X, _detach_\n). Non-string gate keys cannot occur: JSON object keys are always strings.
- grep: no "detach-guard: lock" marker remains in hb.js, hb-lint.js, cli.py, anchors.py or lint.py. Marker classes left: validate, warn, reattach, anchor, changed-base, and the bare lint call-site marker.
- Stripping every line of each marker class per file: all stay syntactically valid (node --check / ast.parse OK).
- Spot-strip in a py/src copy (imports fine) run through tests/detach.sh: validate strip -> "FAIL: declare: python empty reason accepted" (rc=1, named reason). reattach strip -> main suite stays green (only the selftest s10 and pytest test_reattach_restores_and_refuses_brick carry that tooth, by design; selftest s10 is green).
- Race tooth is the 6-way race in detach.sh (RACES-OK); the prose header says so.

P1: NOT-REPRODUCED — DECLARE-OK, RACES-OK, 171 pytest green; the python validate strip reddens with the named reason.
P2: NOT-REPRODUCED — WEASEL-OK, RESOLVER-OK; round 1 verified clean; re-runs green.
P3: NOT-REPRODUCED — BASE-OK, LINT-OK; the "_start\n" divergence is fixed: the 10-name probe agrees on both runtimes, parity detach:lint-reserved passes with a non-empty guard.
G1: NOT-REPRODUCED — round 1 clean; DECLARE-OK/BASE-OK and parity detach:cross re-run green.
G2: NOT-REPRODUCED — round 1 clean; WEASEL-OK and parity re-run green.
G3: NOT-REPRODUCED — round 1 clean; DECLARE-OK and pytest 171 green.
G4: NOT-REPRODUCED — no lock marker remains; every marker-class strip parses; selftest (s1..s10, incl. s9/s10) prints DETACH-SELFTEST-OK; my own validate and reattach strips go red for the named reason.

Verdict: SOUND
