# GATE_H1 refutation attempt 1 (correctness refuter)

All probing was done in mktemp fixtures. The scratch scripts are p1..p17.sh in this scratchpad. They source helpers.sh, which is the top of tests/horizon.sh with ROOT pinned. Nothing in the repo tree was modified, and nothing was run against the repo's own .hb. Mutants were built in scratchpad copies of plugin/py/tests; those copies are deleted now.

## Baseline runs (repo root, read-only)
- `bash tests/horizon.sh` printed MARKER/CLOSE/APPEND/LIMITS/PARKED/LINT/AUDIT/REPORT-OK and then HORIZON-OK.
- `bash tests/horizon.sh --selftest` printed HORIZON-SELFTEST-OK.
- `bash tests/parity.sh` ended "PARITY OK", including horizon:resolve/project/lint/audit.
- `py/.venv/bin/python -m pytest -q` gave 187 passed. Bare `python3 -m pytest` has no pytest installed, but the gate uses the venv.
- `bash tests/run-tests.sh` gave 475 passed, 1 failed. The failure is T124.1 (index-coverage.sh): "suite group T185 missing from dev-tests.md table".
  - That row is planned H2 work (h2c). T185.1 and T185.2, T137, T138 and T143 are all green.
  - Not an H1 defect, but the node suite is red at this commit.
- h1s: single-source.sh printed SINGLE-SOURCE-OK, and hook-drives-loop.sh printed HOOK-DRIVES-LOOP-OK. Both ran green at this gate.
- audit-rules-check.sh printed AUDIT-RULES-PROVEN:11.
- tests/horizon.sh line 27 is character-identical to the env-hygiene line in parity.sh, replan.sh, detach.sh, etc.: `unset HB_DIR PROJECT_DIR GATE G DAG_FILE EVENTS_FILE 2>/dev/null || true`.

## Probes and results
- **P1 all-parked (p1).** Both runtimes resolve all_done. The tick wakes all_done, then project_complete. Not an eternal no_pending_tasks. `horizon close` on the all-parked plan is refused: "no horizon is reached — every phase is parked", rc=1, and the event count is unchanged.
- **P1 stale flag (p1).** Wake at H2, then append H3 with horizon:true, complete it through the CLI with no tick, and resolve. Both runtimes return replan_pending/H3. Then the tick gives replan_pending, then replan_waiting.
- **P2 c5 (p1).** Close, append `initialized`, replay the completion history. Both runtimes re-verdict replan_pending/H2 and re-accept a close. No wedge.
- **P2 regate cycle (p3, on both runtimes, with the regate on GATE_H2 and on the earlier GATE_H1).**
  - Declared: refused.
  - Hand-cleared marker: refused.
  - Rearmed without a fresh pass: refused, event count unchanged.
  - After a fresh criteria-pinned `gate.sh` pass: accepted, event count +2 (the pass and the close).
- **G7 drift (p2).** With a completed gate's criteria edited, both runtimes accept the close with an identical delta.
- **Edge shapes (p2).** `--reason '   '`, no subaction and `open` are refused on both runtimes with no event.
  - Divergence: unquoted multi-word `--reason a b c` is accepted by node as "a b c" but refused by python (argparse exit 2, "unrecognized arguments"). `--reason --x` is accepted by node and refused by python.
  - Python never appends an event on these, so this is accept-vs-refuse drift on CLI parsing only.
- **G3 (p7/p8).** Events with phase missing, null, 7, "", [..], true or {..} project no horizon_closed key on either runtime. The ZZ,H1,ZZ sequence gives ['ZZ','H1'] on both. Hand-edited state.horizon_closed values of "str", {}, 5, null, "H2" and {"H2":1} give identical replan_pending on both resolvers, with no throw.
- **Byte stability (p8).** HEAD's projection versus the worktree's, on the same closeless log, is identical modulo last_updated on both runtimes (checked with `git archive HEAD`).
- **G1 pre-alerted exec (p6).** After a tick consumed the wake, both `hb-exec.js run` and `hb exec run` print `HB-EXEC STOP: replan_pending — H2` with rc=1. No INVOKED file was created and the events delta was 0. This covers wake by node or py.
- **G2 (p4/p5/p6).**
  - Interleavings node-py-node-py, py-node-py-node, py-py-node and node-node-py each gave exactly one replan_pending wake, then replan_waiting. events.jsonl was unchanged and only .replan-alerted exists, containing "H2".
  - STUCK_TICKS=1 gave one wake, then waiting, with no stuck flags.
  - A pre-existing .deadlock-alerted is removed on both runtimes.
  - HB_NOTIFY_CMD fired once as `replan_pending|H2` (tick.sh only; python has no notifier, so a py-first wake notifies nothing, which is by design).
  - `git check-ignore .hb/.replan-alerted` returns rc=0 after a git-mode bootstrap.
- **G8 (p5/p17).**
  - At the drift, both ticks and both exec drivers give criteria_drift, and no flag is written.
  - With no intermediate ticks during the regate cycle, the post-cure tick gives replan_pending once, then replan_waiting, on both runtimes.
  - Side note: a tick taken while the regate is merely declared (before the rearm and fresh pass) consumes the once-only wake. After the cure, the first tick then sleeps replan_waiting. The exec drivers still STOP, so no silent finish.
- **G4 lint (p9).** The values 1, 0, 1.0, "true", "yes", null, [] and {} give byte-identical errors and exit 1/1 on both. There is one error line per offending phase. true and false give 0 errors. A degenerate id renders `[?]`. Audit emits no horizon finding on a non-boolean marker.
- **G5 / P4 audit (p9, p11, p12).**
  - The gated head with a two-phase tail fires once (warn). The four-phase tail names all four ids in plan order with cut A. JSON tail/cut are identical on both runtimes.
  - Quiet on single-tail, all-unverified, parked-tail, only-verified-parked, and unverified-middle-with-verified-last.
  - Fires with a horizon flag present, with a missing gate, with a zero-task zero-gate placeholder, with parked-middle skipping, and with criteria null / [null] / cmd:5 / no cmd.
  - The seeded template, planning/*.dag.json and tests/fixtures/**/*.json are all quiet on both runtimes.
  - **Hostile criteria that is a string or an object:** the audit CLI crashes on node before the new rule runs, with `TypeError: crit is not iterable` at hb-audit.js:125. That line is not in the diff, and the same crash occurs on the HEAD copy. Python survives that shape and fires the finding.
  - **Gate value that is a string or an array:** python crashes at audit.py:132 (also pre-existing, HEAD identical), and node fires.
  - So on those shapes only one runtime emits speculative_tail.
- **G6 report (p13).** Checked byte-identically on both runtimes, rc=0 throughout:
  - planned, REACHED, then closed by `unknown: say "hi" & <b> — ok → ✓`, with the reason verbatim.
  - After appending H3: H3 planned, H3 REACHED, H3 closed by zed.
  - Parking H3 falls back to the H2 closed line. An unflagged appended H4 prints nothing. An unmarked project prints nothing.
- **Event and doctor (p16).** The event carries phase, reason (trimmed, quotes preserved), ts and actor "unknown" when HB_ACTOR is unset, on both runtimes. doctor and diagnose exit 0 on a reached open horizon and after a close.
- **Surfaces.**
  - Protocol keys are identical in hb.js and protocol.py. The bootstrapped PROTOCOL.md has replan_pending.
  - SKILL row, detect.sh stop list, mcp tick description and both exec tables carry it.
  - `PY protocol` prints the action texts, which include replan_pending.
- **Proof hygiene via mutants.** I copied plugin, py and tests to scratchpad dirs, mutated one thing and ran horizon.sh there.
  - M1 (drop unansweredRegate from the node close): RED at c6.
  - M2 (drop staleRearm, node): RED at c6.
  - M3 and M4 (the same two drops in python): RED at c6.
  - M5 (python already-closed check reads a log scan instead of the projection): RED at c5.
  - M6 and M7 (once-flag becomes a bare exists-check on tick.sh and tick.py): RED at a4.
  - M8 (node close checks only the horizon phase's own gate instead of every live gate): **horizon.sh stays GREEN (rc=0)**, and the mutant really accepts a close with a declared regate on the earlier GATE_H1. The real code is correct (p3), but the earlier-live-gate perimeter (G7) is unpinned by the proof.
  - The selftest sabotages strip whole marker classes at once (the close class strips all refusals together), so individual refusal clauses are only covered by the main cases, not the teeth.

## Answers

P1: NOT-REPRODUCED — p1/p7/p8: the replan_pending/all_done verdicts, the all-parked case, the stale once-flag after an untick'd append, and the sparse byte-identical projection all held on both runtimes with identical keys.
P2: NOT-REPRODUCED — p1/p3/p2: every refusal exits nonzero with no event; c5 reset-and-replay re-accepts; the declared, hand-cleared, rearmed-without-pass and fresh-pass sequence is correct on both runtimes; the close survives rebuild; phase scope held (H3 re-wakes after an H2 close).
P3: NOT-REPRODUCED — both drivers STOP replan_pending (fresh and pre-alerted); the reason is on every surface with identical keys; reports match; limits are in parity-notes.
P4: NOT-REPRODUCED — lint/audit/parity probes held. The hostile-criteria crash is a pre-existing audit crash outside the new rule, so it is recorded under G5; the horizon:* parity cases carry non-vacuity floors; T137, T143, T138 and T185.1/2 are green.
G1: NOT-REPRODUCED — p6: both drivers rc=1 `HB-EXEC STOP: replan_pending — H2` on the pre-alerted shape, no INVOKED, events delta 0.
G2: NOT-REPRODUCED — p4/p5/p6: four interleavings, STUCK_TICKS=1 and the deadlock flag all held; exactly one wake, flag content `H2` with no newline, notifier `replan_pending|H2` once, gitignore rc=0.
G3: NOT-REPRODUCED — p7/p8: the hostile events and hand-edited state shapes behave identically on both runtimes with no throw.
G4: NOT-REPRODUCED — p9: every value in the list gives identical lines and exit 1/1; one error per offending phase; `[?]` for a degenerate id; audit is quiet and does not crash.
G5: VIOLATED — shape (c) `criteria` as a string or object. Command: p11.sh, gates `{"GB":{"criteria":"x"},"GC":{"criteria":{"a":1}}}` on a gated-head plan A,B,C. `node plugin/templates/hb-audit.js` gives `TypeError: crit is not iterable` at hb-audit.js:125 with no speculative_tail, while `heartbeat.cli audit` prints the speculative_tail warning. Reversed for a gate value of string or array: python raises a Traceback at audit.py:132 while node fires. The crash sites are pre-existing code before the new rule, and horizon.sh never probes these shapes. The rule itself is not at fault: criteria null, [null], cmd 5 and a missing cmd all matched on both. Every other shape (a), (b), (d)-(g) matched byte-for-byte.
G6: NOT-REPRODUCED — p13: every step of the H2-closed then H3 sequence matched on both runtimes; reason verbatim; actor "unknown"; rc=0.
G7: NOT-REPRODUCED — p3/p2/p16: the earlier-gate regate (declared, rearmed without pass) refuses naming GATE_H1 with no event; whitespace reason, no subaction and `open` refuse; the accepted close writes event/phase/reason/ts/actor; doctor and diagnose exit 0; drift behaves identically (both accept). Caveats: the proof does not pin the earlier-gate clause (mutant M8 stays green), and node accepts unquoted multi-word or dash-leading `--reason` text that python refuses.
G8: NOT-REPRODUCED — p5/p17: criteria_drift outranks the wake on both ticks and exec drivers with no flag; after a complete regate cycle plus fresh pass, the first tick wakes replan_pending once and the second sleeps replan_waiting on both runtimes.

Side findings (not constraint violations):
- tests/run-tests.sh T124.1 is red because docs/dev-tests.md has no T185 row. That is planned H2 work (h2c).
- A tick during a declared regate on the horizon gate consumes the once-only wake, so it does not re-fire after the cure. The exec STOP still holds.
- The proof leaves the earlier-live-gate close perimeter and the hostile-criteria audit shapes unpinned (mutant M8 green; no string/object-criteria case in horizon.sh).

REFUTED
