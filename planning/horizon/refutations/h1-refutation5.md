# H1 refutation, cycle 4 round 5
Baseline in this round: `bash tests/horizon.sh` -> HORIZON-OK; `--selftest` -> HORIZON-SELFTEST-OK; `bash tests/parity.sh` -> PARITY OK; pytest -> 187 passed.
Mutations were made in tar copies of the repo (no .hb) under /tmp/tmp.3b7JF7cjly, and each copy's `bash tests/horizon.sh` was run.

G1 mutants:
- tick.sh flag write changed to `echo "$RP_PHASE" > "$REPLAN_FLAG"`. Result: FAIL f4, "after a node wake the py tick did not sleep replan_waiting".
- tick.py flag write changed to `write_text(phase + "\n")`. Result: FAIL m2 (py), "second tick did not sleep replan_waiting". It reddens, but through m2 and not f4.
G2 mutants:
- tick.py wake appends a wake event. Result: FAIL f4, "a horizon tick appended an event (py wake, node + py waiting)".
- tick.py waiting sleep appends an event. Result: FAIL f4, same message with the node wake.
- tick.sh waiting sleep appends an event. Result: FAIL f3.
G3 mutants:
- executor.py named replan_pending case commented out. Result: FAIL m4, "python hb exec did not stop on replan_pending naming H2: HB-EXEC STOP: replan_pending".
- executor.py replan_waiting print stripped of its phase. Result: FAIL m4 (node-woken).
- hb-exec.js escalate phase dropped. Result: FAIL m4 (node).
- tick.sh replan_waiting without data.phase. Result: FAIL m4 (node-woken).
- tick.py replan_waiting without phase. Result: FAIL m4.
- tick.py wake without phase. Result: FAIL m4.

P1: NOT-REPRODUCED. horizon.sh marker, flags and append cases pass on both runtimes; f1/f2 cover flag clearing, and the f4 flag test covers the cross-runtime case.
P2: NOT-REPRODUCED. The close case passes, and the mutations showed no looseness. I did not re-probe c5 manually this round.
P3: NOT-REPRODUCED. m4 now pins the phase id on every stop line, as the G3 mutants show.
P4: NOT-REPRODUCED. Selftest, parity and pytest are green.
G1: NOT-REPRODUCED. Both flag-newline mutants go red. The py-newline mutant is caught by m2 and not f4, which is still red.
G2: NOT-REPRODUCED. All three event-append mutants go red.
G3: NOT-REPRODUCED. All six phase-id and named-case mutants go red.

HOLES: none
CLEAR
