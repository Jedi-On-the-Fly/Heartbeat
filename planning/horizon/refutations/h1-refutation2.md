# GATE_H1 refutation attempt 2

Baseline (repo root): tests/horizon.sh -> HORIZON-OK; --selftest -> HORIZON-SELFTEST-OK; parity.sh -> PARITY OK; pytest -> 187 passed. Env-hygiene line 27 of horizon.sh is verbatim. run-tests.sh was started but did not finish inside my window (reached T36 clean); the T124.1/T185 row is known/out of scope.

Probes
- Round-1 fix re-verified: fuzz of 27 hostile dag shapes (/scratchpad/fz.py, mktemp fixtures) on both audits. String/object criteria, string/array/null/num gate values, string/num gates map, non-list review constraints, cmd list/num, tasks/files wrong types, dup ids: all SAME findings, no crash on either runtime. The speculative_tail rule fires identically.
- Mutant M8 (node close checks only the horizon phase's gate), in a scratchpad copy: tests/horizon.sh now goes RED: "FAIL: c6(open revision on an EARLIER live gate) (node): close ACCEPTED (exit 0)". The round-1 proof gap is closed.
- Remaining divergences found (all outside gate shapes, in pre-existing code, none in the new rule):
  - phase entry that is a string ("phases":[A,"B",C]): node audit runs and fires speculative_tail; python audit raises AttributeError at audit.py:126 `p.get("parked")` (line unchanged from HEAD); python lint also crashes, node lint says valid. phase null / phases string/object crash on both.
  - cosmetic message stringification in pre-existing messages (undefined vs None, [object Object] vs dict) for non-string criterion elements / gate_exit objects.
  These are malformed-file crashes in pre-existing code, not exploitable, and not the "hostile gate shape" class the claimed fix targets; noted as side findings.

P1: NOT-REPRODUCED — horizon.sh MARKER/PARKED/APPEND/LIMITS green; round-1 p1/p7/p8 probes stand; no change to those paths.
P2: NOT-REPRODUCED — c6 now includes the earlier-gate shape and M8 reddens it; other close clauses unchanged since round 1 probes.
P3: NOT-REPRODUCED — REPORT-OK, parity green; drivers STOP on replan_waiting/replan_pending per horizon.sh.
P4: NOT-REPRODUCED — t7 six hostile gate shapes pass; my 27-shape fuzz shows no gate-shape crash or finding divergence; parity green incl. horizon:* cases.
G1: NOT-REPRODUCED — horizon.sh LIMITS/REPORT green; exec drivers stop.
G2: NOT-REPRODUCED — tick logic unchanged since round 1 probes; horizon.sh APPEND green.
G3: NOT-REPRODUCED — unchanged since round 1.
G4: NOT-REPRODUCED — LINT-OK.
G5: NOT-REPRODUCED — the round-1 crash shapes (string/object criteria, string/array gate value) now give identical findings and exit codes on both runtimes; 27-shape fuzz found no crash in the gate-shape class. (Phase-entry-type crashes are pre-existing and listed above as side findings.)
G6: NOT-REPRODUCED — REPORT-OK.
G7: NOT-REPRODUCED — earlier-gate regate refusal now pinned (M8 RED at c6).
G8: NOT-REPRODUCED — unchanged since round 1.

CLEAR
HOLES: none
