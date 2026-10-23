# RG2 refutation, round 3 (focused; fixtures under /tmp/rf3.* ; probe script scratchpad/r3/probe.sh, output r3/probe.out; repo tree untouched)

## Astral exploit re-run (30 ASCII + 5x U+1F600 = 35 code points)
rearm: node rc=1 "too thin (35 chars)"; py rc=1 "too thin (35 chars)". review pass: both "too thin (35 chars)". Identical.
Boundary-crossing: 'GATE_B '+28 ASCII+5 astral = 40 cp -> BOTH accept rearm (rc 0), both then refuse review pass later for missing constraints (past the thin check). 39 cp variants (34x5, 32 astral) -> both refuse "39 chars". 33 all-astral = 40 -> both accept.
## Code-point change side effects
- Lone surrogate (CESU bytes ED A0 80 x5), truncated 4-byte seq, 0xFF/0xFE: node utf8 replacement and py errors=replace yield identical counts (50/44/40/40) and identical verdicts.
- Combining e+U+0301 (counts 2 on both): 40 and 41 cp accepted by both; ZWJ family sequence counts per code point (37) refused by both.
- Leading U+3000 (non-ASCII ws, not trimmed) + astral: both 40, both accept.
- Doctor healthy on both runtimes after astral/lone-surrogate rearms (no false thin/sha problem).
## Suites (shipped tree, all green)
regate-rearm.sh: MATRIX/SUCCESS/STALE/CYCLE/DOCTOR/DIAGNOSE/RESUME/TRUTH-OK, REGATE-REARM-OK (truth case now has an astral row, line ~360); --selftest REGATE-REARM-SELFTEST-OK; regate-fail-closed.sh REGATE-FAIL-CLOSED-OK; pytest -k regate 23 passed; parity.sh PARITY OK.

## Per-id answers
P1: NOT-REPRODUCED — round-2 astral exploit now refused identically (35 cp) by both; rest of refusal matrix verified rounds 1-2 and MATRIX-OK green.
P2: NOT-REPRODUCED — rounds 1-2 stale-pass/hand-clear/import probes clean; STALE-OK, SUCCESS-OK, CYCLE-OK, RESUME-OK green; code-point change touches only the length helper.
P3: NOT-REPRODUCED — rounds 1-2 doctor/diagnose probes clean; DOCTOR-OK/DIAGNOSE-OK green; doctor healthy after astral rearms on both runtimes.
P4: NOT-REPRODUCED — same astral/lone-surrogate/combining bytes decided identically (rearm and review pass) across 15 artifact variants x 2 runtimes; parity.sh green.
G1: NOT-REPRODUCED — rounds 1-2 triple-sha agreement; SUCCESS-OK green; doctor raises no rearm-artifact problem after astral rearms on either runtime.
G2: NOT-REPRODUCED — rounds 1-2 race probes; logic untouched this round.
G3: NOT-REPRODUCED — rounds 1-2 order comparisons; CYCLE-OK green; untouched this round.
G4: NOT-REPRODUCED — bash tests/regate-rearm.sh --selftest prints REGATE-REARM-SELFTEST-OK.

Verdict: SOUND
