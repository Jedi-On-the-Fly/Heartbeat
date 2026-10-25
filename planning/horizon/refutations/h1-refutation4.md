# GATE_H1 refutation, cycle 3 round 4

Method: copy of the repo (no .git/.hb) in /tmp/tmp.SZjmZMnSNz/base; each mutant is a copy with one sed edit; run the copy's `bash tests/horizon.sh`. Real repo: only `bash tests/horizon.sh`, `--selftest`, `bash tests/parity.sh`, pytest (no writes, no .hb use).

Runs this round on the real tree: horizon.sh -> all *-OK + HORIZON-OK; --selftest -> HORIZON-SELFTEST-OK; parity.sh -> "PARITY OK" (horizon:project/lint/audit lines present); pytest -> 187 passed. Header `unset HB_DIR PROJECT_DIR GATE G DAG_FILE EVENTS_FILE` is verbatim identical to tests/detach.sh, replan.sh, parity.sh etc. (grep).

Mutation results:
- G1 py `p["horizon"] not in (True, False)`: FAIL n1 horizon=1 (node=1 py=0). RED. node `p.horizon != null && typeof...`: FAIL n1 horizon=null (node=0 py=1). RED.
- G2 report.js `horizon_closed.length > 0` and report.py `bool(s.get("horizon_closed"))`: both FAIL r3 "Horizon: H3 closed by ?: ". RED.
- G3 all_done-branch removal (tick.sh l.287; tick.py l.154): FAIL f1. task-branch removal (tick.sh l.369; tick.py l.204): FAIL f2. Each of the 4 independently RED.
- G4 hb.js l.1709 regateBlocks term dropped, cli.py l.389 regate_blocks term dropped: both FAIL c6 "dag-only PENDING marker ... close ACCEPTED". RED.
- G5: delete notify -> FAIL f3 (empty log); notify under replan_waiting instead -> FAIL f3; empty $3 -> FAIL f3. BUT:
  * mutant g5every (extra `notify "replan_waiting" "$RP_PHASE"` before the sleep_out on l.305) -> horizon.sh prints AUDIT-OK REPORT-OK HORIZON-OK. Its notify.log after wake+2 waits and H3 append: replan_pending|H2, replan_waiting|H2, replan_waiting|H2, replan_pending|H3, replan_waiting|H3.
  * mutant g5once (notify guarded by a never-cleared sentinel, so a later different horizon never notifies) -> HORIZON-OK; log only replan_pending|H2.
  * Real tick.sh behaves correctly (log: replan_pending|H2, replan_pending|H3; events 7 -> 7), so the code is right; the proof is not.
  f3 asserts only `grep -c '^replan_pending|H2$' == 1`; it never asserts zero notifier calls on the replan_waiting runs, never wakes a second (appended) horizon under HB_NOTIFY_CMD, and never asserts no event was appended. Those are three of the four clauses of G5 ("zero times on replan_waiting", "once more with the new id", "no run appends an event").

Constraint lines:
P1: NOT-REPRODUCED — horizon.sh marker/append/parked/flags/limits OK on both runtimes; parity OK; pytest 187 passed.
P2: NOT-REPRODUCED — horizon.sh close OK (c1-c7 incl. c5 reset+replay, c6 four regate shapes, c7 all-parked); mutants dropping regateBlocks term caught (see G4).
P3: NOT-REPRODUCED — marker m4 (both drivers STOP), report r1-r4 OK, parity OK, selftest OK.
P4: NOT-REPRODUCED — lint n1 loop covers "yes",1,0,1.0,null,[],{}; audit case OK; selftest OK; parity horizon:{project,lint,audit} present.
G1: NOT-REPRODUCED — both mutants (py `not in (True, False)`, node null-skip) go red at n1 with the exit-code mismatch shown above.
G2: NOT-REPRODUCED — both `length>0` / `bool(...)` mutants go red at r3 ("closed by ?:" leak onto H3).
G3: NOT-REPRODUCED — each of the four single-line flag removals (sh/py x all_done/task) goes red at f1/f2.
G4: NOT-REPRODUCED — both runtimes' regateBlocks-term-dropped mutants go red at the c6 dag-only-marker probe.
G5: VIOLATED — `bash tests/horizon.sh` in a copy with `notify "replan_waiting" "$RP_PHASE"` added to tick.sh's replan_waiting path prints HORIZON-OK (log shows replan_waiting|H2 twice); a copy where the notify fires only the first time ever also prints HORIZON-OK (the H3 wake never notifies). f3 does not pin zero calls on waiting runs, the second-horizon notification, or no-event-appended.

HOLES: G5 — extend case_flags f3 to (1) assert the notify.log has exactly one line total after wake + 2 waits, (2) append+complete a flagged H3 and assert the log gains exactly `replan_pending|H3` once, (3) assert events.jsonl line count unchanged across the ticks. The code itself is correct.

REFUTED
