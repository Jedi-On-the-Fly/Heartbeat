# Wave-4 plan refutation — round 2 (session model)

Target: planning/horizon.dag.json after the round-1 folds. Mode: read-only; mktemp probes; never the repo's .hb.

## Convergence (F1–F7)

**F1 — folded, but the fold is INCOMPLETE: a stale rearm slips the close (Finding 1).**
**F2 — folded and verified.** Resolver empty-live-list → all_done specced in h1b and pinned by p1; t6 widening consistent across h1a/h1c/P4. The highest-value probe ran clean: the widened rule (zero-task zero-gate = unverified; trailing run ≥ 2 behind ≥ 1 verified live phase), implemented in scratchpad/spectail_probe.py, replayed over all 63 planning/*.dag.json, plugin/templates/dag.json, every tests/fixtures/** dag, the nested planning/*/.hb/dag.json projects — 0 firings. Closest call: tests/fixtures/parity/broken.json (trailing_unverified=2) stays quiet — no gated head. example-dags-gated.sh (T136.1) fails only on lint errors / audit exit 1, and speculative_tail is warn → exit 0. parity-fuzz compares node↔py audit results to each other (tests/parity-fuzz.sh:27-44) — a symmetric new warn stays green.
**F3 — folded coherently, weakly pinned (Finding 3).** Both sides read the PROJECTED state.horizon_closed; the initialized sequence is coherent — but c5 as worded cannot distinguish the one-source implementation from a log-scan close (they agree in c5's fixture).
**F4 — folded** (P1 subjects include protocol.py). **F5 — folded, one stale remnant** (Finding 6): h2w pins 9 files, ALL-PROSE-OK:9 verified green today; the GATE_H2 prompt still said "seven". **F6 — folded and verified** (parity.sh's audit fixture loop iterates exactly 7 names; h1d mandates inline cases). **F7 — folded** (honest dogfood claim).

## New seams from the folds

- Flag stores a phase id: no existing check pins flag-file content; only .stuck-alerted/.noprogress-alerted/.rot-alerted are asserted (run-tests.sh:120,244,452) — untouched.
- Refusal-message bytes/order: P2 pins exit-nonzero + no-event only — matches the house precedent for CLI-verb refusals (T179 regate-declare refusals probed for refusal + no event, never bytes; runtime-flavored texts differ by design). GATE_DS1 pinned twin bytes only for doctor output, a shared diagnostic surface — the close is not one. Converged.
- (Low) single-source key-grep trap (Finding 7): single-source.sh:11 extracts protocol keys with `grep -oE '"[a-z_]+":'` over the whole protocol.py — a quoted `"horizon":` substring inside the new action text would read as a protocol key and red T138.1.

## Gate escape (clause-by-clause)

Covered: resolver shapes (m1/m3/p1/l1/l2/a1–a4), tick once-wake + stale-flag (m2/a4), close refusals c1/c2/c5/c6 + c3/c4, exec stop m4 (both drivers fail closed: executor.py:586-588, hb-exec.js:540), lint n1/n2, audit t1–t6, reports r1–r4 on both runtimes, selftest s1–s8. hb.js↔protocol.py key identity mechanically forced at GATE_H1 by h1p (parity protocol:reasons, tests/parity.sh:294-297).

Escapes (Finding 5): claim clauses with no h1a case and no GATE_H1 criterion — notify 'replan_pending' + the header notify-comment (tick.sh:42-44; T22 pins notify only for gate_blocked); data.action CONTENT (m2 pinned only non-empty); both usage strings; PROTOCOL.md regeneration (T33.2/T33.5 subset greps); the SKILL reason row (T138.1), heartbeat-detect stop lists (T143), mcp_server.py tick description — all pinned only by the full node suite, which no GATE_H1 criterion runs; they bind first at h2y. "T138.1 forces the SKILL row into H1" therefore overstates. Smallest fix: one cheap composite criterion at GATE_H1 (single-source.sh + hook-drives-loop.sh, each <5 s, deterministic). The SKILL-row-at-H1 sequencing itself is acceptable once that criterion exists.

## Suite interplay (final spec)

All clear: docs-currency.sh greps fixed tokens only (docs/howto/gate-examples/docs-currency.sh:15-41) — h1b cannot redden it mid-wave. T33.5 and test_smoke are subset checks. T143's hook check is presence-regex (hook-drives-loop.sh:24-33) — adding replan_pending keeps it green. No test asserts state.json key sets (parity state/fuzz extract named keys, tests/parity.sh:272-274), exact report bytes, usage bytes, PROTOCOL.md content beyond subset greps, or hb horizon absence. T138.1 pins SKILL↔protocol.py only; the third surface (hb.js PROTOCOL) is pinned to protocol.py by parity protocol:reasons — h1b covers all three; no fourth surface found. GROUPS-PASSED carries the trailing space (run-tests.sh:2002-2003).

## Dogfood + T185

.hb/ copies contain zero 'horizon' handling; the old resolver reads only id/parked/gate_entry/gate_exit/tasks (unknown fields inert); current lint and audit run clean on planning/horizon.dag.json as it sits today (exit 0/0) so T136.1 stays green from the moment the plan file exists; doctor's embedded lint is the same tolerant ruleset; gate.sh/anchors never validate dag fields. T185 appears nowhere in the repo outside the plan (h2z not vacuously green; all three greps fail today).

## House rules

≤8 tasks/phase (4+3) ✓; spec-first ordering ✓; P-ids strict ✓; subjects complete ✓; "violated" appears 0 times ✓; criteria deterministic; timeouts generous — tests/replan.sh (T184, the size-comparable precedent) measured 18.6 s against horizon.sh's 600 s; h2y's 1500 s covers the ~13 min full suite.

## Findings (ranked)

1. The close accepts in the stale-rearm window — the F1 fold is incomplete. After declare → rearm (no fresh pass): projection keeps det=true (state.py:91-133 never handles gate_regated/rearmed), regateBlocks clear (hb.js:825-830), unansweredRegate false (hb.js:847-854) — the close is accepted while the revised criteria have never passed. Verdict-class siblings refuse exactly this window: hb review (hb.js:1245, review_policy.py:47), both executors (hb-exec.js:448, executor.py:312). Fix: add staleRearm to the refusal list and P2, extend c6 with the intermediate probe (rearm alone → still refused; fresh pass → accepted).
2. hb horizon close is unspecified on an empty live list — the F2 crash class recurs inside the new verb (py live[-1] IndexError, node .at(-1) undefined); no case covers the close on an all-parked plan. Fix: empty live list → the not-reached refusal, never a throw; a close probe case.
3. The one-source rule (F3) is constraint-pinned but not proof-pinned: c5's fixture cannot distinguish projection-read from log-scan. Fix: fold the initialized-reset sequence into c5.
4. No parity case for the new projection surface (AGENTS rule 2: a new shared surface adds a parity case) — project()'s horizon_closed key gets none; multi-close insertion order compared nowhere. Fix: a fourth inline case (horizon:project) through the state_case/proj_compare normalization.
5. GATE_H1 executes none of the cheap mechanical pins for P3's surfaces (SKILL row/T138.1, hook stop lists/T143, mcp description, PROTOCOL.md, usage strings, notify, data.action content) — all review-pinned at H1, criterion-pinned only at h2y. Fix: a GATE_H1 criterion running single-source.sh + hook-drives-loop.sh; pin m2's data.action assert to content.
6. Stale count in the GATE_H2 review prompt: "all seven docs" vs the folded nine.
7. (Note) single-source.sh's key-extraction grep will misparse a `"horizon":` substring inside the new protocol action text as a protocol key — avoid quoted key-colon syntax in the action/SKILL row text.

VERDICT: UNSOUND
