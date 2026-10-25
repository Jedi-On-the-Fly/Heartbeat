# Wave-4 plan refutation — round 4 (session model) — SOUND

Target: planning/horizon.dag.json after the round-3 folds. Mode: read-only; mktemp probes; never the repo's .hb. Heavy probes from rounds 2-3 (speculative_tail over 87 dags, h1s checkers, helper-twin existence, doc line refs, id cross-check) not redone — independently reproduced earlier.

## Section 1 — F15 (the c5 replay): converged, no hole

Presence + identical spec in all three places (h1a's c5, GATE_H1 prompt (b), P2's parenthetical): same sequence, same discriminator, verbatim-coherent.

Projection validity: hb.js:120-124 — the reset wipes completion; replayed task_done/gate_passed re-complete; the (planned) horizon_closed set resets on the same precedent and no close event follows the reset → re-verdict replan_pending, re-accept close on a projection read; a log-scan still sees the pre-reset horizon_closed and wedges. The probe discriminates exactly as claimed. The precedent is real: tests/parity.sh:320 (proj_compare "mid" — initialized then a bare replayed task_done; the adjacent parked case replays bare gate_passed).

Drift coherence: driftedGates (hb.js:905-934), line 909: only gate_passed events with non-empty criteria enter the pin walk. The fixture's ORIGINAL passes are criteria-pinned (m1) and unchanged; bare replayed passes never enter pins[]; the walk stays quiet. So "bare replayed passes never pin, so the replay is drift-safe" is TRUE against the real logic — and the dag text does not spec criteria-pinned replays, so it asserts nothing false. Subtlety checked: the dag says re-VERDICT replan_pending (resolver-level), not re-wake, so the once-flag's state after the close cannot falsify the probe. The fixture class is review-less (the replan.sh pattern), so task_done/gate_passed is the complete completion history (hb.js:168 review-owed branch never binds).

## Section 2 — F16–F20: all folds landed, converged

F16: the fourth c6 shape in h1a and the prompt, verbatim-equivalent; mechanism-coherent (unansweredRegate hb.js:847; the marker-sync doctor precedent hb.js:401 "the log is truth"). F17: every current-spec occurrence says four; the only "three parity cases" strings are historical round-records. F18: h2b carries "(c1/c2/c5/c6/c7)" plus the perimeter sentence. F19: s5/s6 strip ALL close-guard lines, c1 AND c6 redden. F20: _meta's close summary is the same six-condition semantic set as h1b's refusal list and P2's claim (h1b's extra "subaction is not 'close'" is CLI usage, not a close-contract condition); case coverage maps c1↔not-reached/unflagged, c2↔reason, c5↔unclosed-projected, c6↔regate (4 shapes), c7↔empty-live.

## Section 3 — internal consistency sweep: converged, no hole

Every case id referenced anywhere is defined in h1a; no orphans either direction. Every P1-P4 violation clause maps to a case or criterion (P1→m1-m4/c3/a1-a4/l1-l2/p1 + horizon:resolve/project; P2→c1/c2/c5/c6/c7/c3/c4/a3; P3→m4/r1-r4/h1s/parity-notes-in-subjects; P4→n1-n2/t1-t6/s1-s8/h1y + horizon:lint/audit + T137 pin). Counts uniform: four parity cases, nine docs (h2w's list is exactly 9 and equals h2a+h2b+h2c's edit surfaces). h2z's three greps match h2c's three named outputs. The [].every vacuous-true matches p1/c7. Two non-blocking nits, no fold required: (i) the GATE_H1 prompt (e) lumps the audit sabotage under "horizon-guard lines (… audit classes)" while h1a/h1c spec a speculative_tail block strip — the reviewer also reads h1a, no misdirection; (ii) h2b anchors t1-t5 but not t6 — an anchor-choice, not a falsity (t6 is a sub-shape of the same rule).

## Section 4 — final adversarial pass: converged, no hole

- Unpark after an l2-style silence: the resolver is projection-pure — an unparked, complete, flagged, unclosed last-live phase re-verdicts replan_pending, never all_done. The repeat NOTIFY depends on the flag, which h1b specs cleared on the all_done branch (the parked-period tick), so the wake comes back; even under a buggy no-clear implementation the failure is bounded to a suppressed repeat notification for a phase the human was already alerted on and personally parked — the verdict, the exec STOP (m4) and the report's REACHED line (r2) all stay loud. No sequence reaches all_done past the open horizon.
- Detach/reattach vs "last live phase": isLive = !parked (hb-next-task.js:50) — detached_from leaves the phase live, but detach only RETRACTS an ordering claim: it can only unblock, never block. A detached-but-unfinished phase holding off all-live-complete is ordinary incompleteness with reachable work; plan order (array order) untouched. No hole.
- Hand-forged horizon_closed without the verb: the log is truth — projection accepts it and the horizon goes quiet — but this is zero new power: pre-wave, forging task_done+gate_passed already bought all_done past open work; the forged close even carries a self-declared actor, which is precisely the limit h1d's parity-notes section records ("the trust model stays procedural"). The refusals bind the VERB; whoever holds the pen on the log owns the state system-wide. The already-recorded procedural-trust honest limit, not a new hole.
- Constructed variant: park a regated phase to slip its open revision past the close's live-gate perimeter — the close accepts, but doctor's regate checks (hb.js:398-401, keyed on gates, not live phases) stay loud, so the revision is not silently retired; parking-as-silence is the named honest limit. Also: a flagged zero-task/zero-gate final phase can never complete (hb.js:164 `if (!G) continue;`) so its wake never fires — today's degenerate-placeholder wedge for ANY gateless trailing phase, horizon or not; the wave's own t6 tooth warns against the shape; outside this wave's blast radius.

All round-3 folds landed verbatim-coherent; the replay is projection-valid and drift-coherent against the real code; the spec text asserts nothing false; no uncovered sequence reaches all_done past an open horizon or wakes replan_pending falsely.

VERDICT: SOUND
