# Wave-4 plan refutation — round 3 (session model)

Target: planning/horizon.dag.json after the round-2 folds. Mode: read-only; mktemp probes; never the repo's .hb.

## Section 1 — round-2 folds: landed and coherent?

**F8 (stale-rearm) — CONVERGED.** All four surfaces tell the same three-state predicate ("pending / unanswered in the log / rearmed without a fresh criteria-pinned pass"): h1a's c6, h1b's refusal list, P2 claim+violation, the GATE_H1 prompt's cycle walk. Implementable as worded on BOTH runtimes — py lacks nothing: regateBlocks hb.js:825 / regate_blocks state.py:200; unansweredRegate hb.js:847 / unanswered_regate state.py:227; staleRearm hb.js:861 / stale_rearm state.py:241. The verdict-class siblings refuse all three states on both sides (hb.js:1241-1245 review; review_policy.py:43-47; executor.py:309-312/484/545-548), and staleRearm's "criteria-pinned pass" semantics (hb.js:867-868) match c6's cure wording exactly. One probe gap remains — finding 2.

**F9 (close on all-parked) — CONVERGED.** c7 defined in h1a, mirrored in h1b, P2, and the prompt, consistent with p1: today's behavior confirmed at hb-next-task.js:107 — [].every vacuous-true → all_done, so "today's behavior" is accurately pinned.

**F10 (c5 initialized-reset) — NOT COHERENT AS WORDED (Finding 1, top-ranked).**

## Findings (ranked)

**1. (HIGH) c5's sequence is projection-invalid: appending only an `initialized` event at the END of the log makes the project UNREACHED, so "re-verdict replan_pending AND re-accept a close" is false on any correct implementation.**
Evidence: hb.js:120-124 (completed.clear(); active.clear(); all gateState deleted) and state.py:93-98 (identical) — an initialized event wipes completed tasks and every gate's det/rev, and the specced horizon_closed set resets too. After c5's sequence as worded, the resolver returns next_task (live phases incomplete), not replan_pending, and the re-close is refused for not-reached on BOTH a projection-reading and a log-scanning implementation — the probe discriminates nothing. The incoherence appears in three load-bearing places: h1a's c5, the GATE_H1 review prompt (b), P2's parenthetical. Fix (exact): insert a replay step in all three places — close → append initialized → replay the completion history (re-append the task_done/gate_passed events after the reset) → both runtimes must re-verdict replan_pending and re-accept a close. The replay is projection-valid and already parity-pinned (tests/parity.sh:320 proj_compare "mid": initialized followed by a task_done re-marks it). With the replay the probe genuinely discriminates: a projection read sees horizon_closed reset → re-wake + re-accept; a log scan still sees the old horizon_closed event → wedge. Drift/stale-rearm safe: no rearm events, bare replayed passes never pin.

**2. (MEDIUM) c6's three states never isolate the unansweredRegate clause — an implementation omitting it passes c6 green.**
State 1 (declare) is refused by regateBlocks (dag marker) alone; state 2 isolates staleRearm; the hand-cleared-marker window — gate_regated in the log, marker hand-edited to pending:false or removed — is exactly what unansweredRegate exists for (the recorded refuter catch behind hb.js:1131, hb.js:1244, constraints.py:183, review_policy.py:46), and no c6 state reaches it. Fix: a fourth shape — declare → hand-clear the regate marker in the mktemp dag → close must STILL be refused (the log is truth) — on both runtimes.

**3. (MEDIUM) Stale count from the F11 fold: GATE_H1's desc still says "three new parity cases"** vs h1d/h1p/P4/prompt (four). One-word fix. (No "seven docs" remains anywhere.)

**4. (MEDIUM-LOW) h2b's close-contract anchor list lags F8/F9: "(c1/c2/c5)" omits c6 and c7.**
GATE_H2 P2 requires the text to foreclose "close as an escape" — the regate-perimeter refusal (c6) IS that foreclosure, yet the how-to as specced never documents or anchors it; c7 likewise. Fix: "(c1/c2/c5/c6/c7)" plus a sentence that the close sits inside the regate perimeter.

**5. (LOW) Selftest sabotage asymmetry on the close's regate-perimeter guard.**
s5/s6 strip only the not-reached refusal; every other guard class gets a per-runtime sabotage, and the prompt (e) says "close classes" plural. Partial mitigation exists (c6's accept-after-cure is a non-vacuity floor; state 2 detects a missing staleRearm). Fix: widen s5/s6 to strip ALL horizon-guard: close lines (c1 AND c6 must redden).

**6. (LOW) _meta.design's close summary still enumerates the refusal predicate as "(reached + flagged + unclosed + reasoned)" — pre-F1/F8/F9.**

Nit: tick.sh's header notify-reason comment (l.42-44), which h1b edits, also omits criteria_drift — the F5 currency-debt class; folding it in the same edit is one word.

## Section 2 — h1s today: CONVERGED, no hole

Both scripts read first: read-only against the repo (single-source.sh greps repo files and requires hb-audit.js — side-effect-free under the require.main guard; hook-drives-loop.sh runs the hook against mktemp dirs). No args/env needed. Run from repo root today: SINGLE-SOURCE-OK exit 0 and HOOK-DRIVES-LOOP-OK exit 0. The F14 defensive clause is necessary and correctly scoped: single-source.sh:11 greps `"[a-z_]+":` over ALL of protocol.py; the SKILL side (l.12) reads row-leading cells only, so prose `"horizon": true` elsewhere in SKILL.md is safe.

## Section 3 — remaining incoherences

Finding 3 is the only stale count. Full id cross-check: every case id referenced anywhere (c5, c6, c7, m1-m4, a1-a4, t1-t6, l1/l2, p1, n1/n2, r1-r4, s1-s8) is defined in h1a; no orphans either direction. Doc line-areas all verified current (dev-plugin.md ll.100/102/156/160/201/241; README.md l.165 + l.200-214 — confirmed missing criteria_drift as F5 claims; CLAUDE-MD-SNIPPET.md l.56 likewise; SKILL.md l.48/l.213/l.279 real). h2z's three greps all fail today (non-vacuous; grp "T185 matches the real group-line format, T184 at l.1989 the current last). h1s needs no constraint house-style-wise. Supporting mechanics verified: env-hygiene header verbatim in five existing suites; the .all-done-alerted once-then-sleep precedent (tick.sh:286-292) matches the specced replan pattern exactly; both exec drivers idle-exit-0 on unknown sleeps (hb-exec.js:395-399, executor.py:443-448) so replan_waiting cannot busy-loop a driver; HB_EXEC_BACKEND=script supported by both (m4 feasible); lint precedent for n1 real (hb-lint.js:140, '?' rendering l.41); py/.venv exists; 'horizon'/'replan' absent from both runtimes as _meta claims; howto-list.md:190 is the real T184 row h2c re-specifies.

## Section 4 — fresh eyes

Findings 2 and 5 are the sabotage/probe gaps. Independent verification: re-implemented h1c's speculative_tail definition (including t6, using the real classify from hb-audit.js) and replayed over 87 dag-shaped files (all 63 planning dags, the seeded template, every test fixture): fires on NONE — round 2's claim independently reproduced. The park/launder dances are foreclosed or honestly pinned (l1/l2, c7, a4's phase-id flag); the resolver's empty-live branch is real; m2's content assert folded; F13/F14 folded.

The plan is one wording defect away from sound, but that defect (finding 1) sits inside a gate-pinned review prompt and a constraint — as written, GATE_H1's review cannot execute c5's sequence and reach the asserted outcome on a correct implementation. With findings 1-4 folded (5-6 at the author's discretion), I'd expect convergence.

VERDICT: UNSOUND
