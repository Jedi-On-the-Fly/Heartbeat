# Plan to the horizon (and replan at it, loudly)

A plan is a hypothesis. For discovery work — projects where later phases depend on what
earlier phases will *learn* — part of the plan is unknowable at planning time, and a DAG
that pretends otherwise is lying with structure. The field case that forced this doctrine:
gates whose criteria hard-coded environment premises (hostnames, volume mounts, a vendor's
API shape) that died mid-project, leaving the operator to choose between hand-editing
accepted gates and abandoning the plan. HeartBeat's answer is a boundary with teeth on
both sides: plan only to the knowledge horizon, replan freely below it, and let nothing
cross the accepted side without its own rigor.

## The knowledge horizon

The horizon is the last phase whose gate you can spec **now** — concrete criteria,
runnable commands, premises you actually hold. Plan to it and stop:

- **Plan only the phases whose spec is known.** A detailed phase beyond the horizon is the
  planning analogue of a hollow gate: unfalsifiable structure that reads as rigor. `hb-audit`
  flags the shape as `speculative_tail` — two or more trailing live phases that are
  unverified (no gate, a gate without criteria, no behavioral criterion, or an empty
  placeholder phase) behind a verified head — as ONE warning naming the tail, the cut phase
  and the cure, identically on both runtimes (`tests/horizon.sh` `case_audit` t1, t6). It
  stays quiet on a fully-gated plan, a single unverified final phase, an all-unverified plan
  (no verified head to cut back to) and a parked tail (t2–t5). It is a warning, not an error:
  its job is the diagnosis — where to cut. A tail member carries its own finding when its
  shape has one (an unguarded phase warns, an empty or hollow gate errors); an empty
  placeholder phase carries none, and this rule is what names it.
- **Mark the horizon: `"horizon": true` on the last planned phase.** That marker IS the
  replan point. When the flagged phase is the last live phase and every live phase is
  complete, both resolvers return `replan_pending` instead of `all_done` (`case_marker` m1;
  without the marker the same plan still ends `all_done` — m3). Both ticks wake
  `replan_pending` once, with an action naming the two sanctioned moves, then sleep
  `replan_waiting` (m2); both exec drivers stop with `HB-EXEC STOP: replan_pending — <phase>`
  on every run (m4). The marker is a strict boolean: lint errors on anything else (`case_lint`
  n1), and a truthy non-boolean is no horizon on any surface (n3).
- **Put the learning inside the horizon phase.** A final task whose gate verifies the
  learning is *recorded* (a findings file, a decision doc — a real artifact a criterion can
  test) is the recommended content of the horizon phase; the marker makes sure the
  decision that follows it is never skipped.
- **Size the horizon honestly.** One phase is a fine horizon. The cost of a short horizon
  is one more replan point; the cost of a long one is fabricated phases you will either
  execute against dead premises or hand-edit — and the tripwire below makes the second
  path loud. An old flag left on a phase that is no longer last after an append is
  historical and inert, never a lint error (n2; `case_append` a2).

## At the horizon: exactly two moves

When the tick wakes `replan_pending`, a human decision is owed, and there are exactly two
sanctioned answers:

1. **Replan by append-continuation** (next section): append the NEXT horizon's phases, flag
   the new last phase, refute the appended plan, tick. The ticks hand out the appended work
   (`case_append` a1). The close is phase-scoped, so a new flagged horizon wakes again even
   after an older one was closed (a3), and a stale once-flag never silences a newer horizon
   (a4; the flag is one surface across both runtimes and is cleared when a task is handed
   out or `all_done` is reached — `case_flags` f1, f2, f4).
2. **End the project as a recorded decision**: `hb horizon close --reason "<why>"` (node:
   `node .hb/hb.js horizon close --reason <why…>`). It appends a `horizon_closed` event
   carrying the phase, the reason and the actor, reprojects, and the next tick wakes
   `all_done` (`case_close` c3); `hb rebuild` preserves the verdict (c4).

**The close is a verdict, and it fails closed.** It is refused — nonzero exit, no event
appended — when the horizon is not reached or the last live phase is unflagged (c1), when
the reason is missing or empty (c2), when the horizon is already closed by the projection's
own reading (c3; and c5 pins that reading as the projection's: after an `initialized` reset
and a replay of the completion history, the horizon is open again and accepts a new close), and when every phase is parked (c7). The
close sits inside the same regate perimeter as the review: an open revision on ANY live
gate — declared, unanswered in the log even with the dag marker hand-cleared, carried only
by a pending dag marker, or rearmed without a fresh pass — refuses it, so a close can never
retire a revision behind a finished project (c6). An all-parked plan keeps ending in
`all_done` (`case_parked` p1). Reports print the horizon line — planned, REACHED naming
both moves, or closed by its actor with the reason — and nothing on an unmarked project
(`case_report` r1–r4).

## Replanning at the horizon

Replanning is **append-continuation**, and its mechanics are pinned by a runnable proof
(`tests/replan.sh`, suite group T184):

- **Append** new phases with fresh ids — both lints error on a duplicate phase id
  (`replan.sh` selftest s1) — and set the first new phase's `gate_entry` to the last
  completed phase's `gate_exit` (`case_append`).
- The append **touches nothing above the horizon**: completed phases' projection is
  byte-untouched, and `hb rebuild` is deterministic modulo the `last_updated` stamp on
  both runtimes (`case_append`).
- **Below the horizon the plan is freely editable**: reshape or drop a never-started phase,
  its gate included — lint stays at 0 errors, `hb doctor` stays at zero problems, and the
  resolver follows the edited plan (`case_unstarted`).
- **Each falsification has its verb.** A dependency *claim* proved false → `hb detach`
  (loud, reversible — `tests/detach.sh`). A gate whose *premises* died → `hb regate`
  (declare, a DIFFERENT actor rearms with evidence, fresh pass — `tests/regate-rearm.sh`
  and the fail-closed perimeter in `tests/regate-fail-closed.sh`). Unstarted phases that
  the learning reshaped → edit or drop them directly (`case_unstarted`); phases to shelve
  without deletion → `hb park`.

**Replan is a refutation outcome.** When a refuter's UNSOUND refutes the *plan* — a
premise died, a claimed dependency is false, phases were fabricated beyond the horizon —
the resolution is the sanctioned surface above, never a weakened gate, constraint, or
review. The plan was the hypothesis; the findings are data; the replan is the fold.

## The tripwire: the boundary is enforced, not assumed

Above the horizon sits accepted work, and its gates' criteria are **evidence the log has
already pinned**: every real pass records `criteria: [{id, cmd, exit}]` on its
`gate_passed` event. Both doctors walk each gate's criteria-pinned pass history plus the
current dag criteria as a final element, comparing the ordered `(id, cmd)` pairs; any
adjacent unsanctioned difference is a **problem** (exit 1, byte-identical message on both
runtimes, naming the cure). What that catches, each anchored in `tests/replan.sh`:

- a hand-edit of a completed gate's criteria — even one byte (`case_drift` d1);
- the **launder**: weaken, then plainly re-run so a fresh pass pins the weakened bytes —
  the pin *history* is truth, so it still drifts (d2);
- a bare/import pass shadowing the pins — passes without a criteria field never pin (d3);
- an ever-pinned gate **removed** from the dag (d4) and criteria **reordered** (d5);
- and the reach is total: both sweeps (`gate.sh --all`, `hb gate --all`) EXCLUDE a drifted
  gate from re-evaluation (running weakened criteria proves nothing) and count it FAILING
  with an annotation — parked silences neither drift nor a pending regate (`case_sweep`);
  both ticks wake the human-needed `criteria_drift` reason every tick until cured, ahead
  of task dispatch, and both drivers escalate and STOP on it — `HB-EXEC STOP:
  criteria_drift`, exit nonzero, never a busy-loop (`case_tick` pins the ticks and both
  executors).

**The cure is a completed regate cycle** — declare (`hb regate <gate> --reason "<why>"`;
node takes trailing words instead: `node .hb/hb.js regate <gate> <why…>` — the park/detach
arg-style divergence), a DIFFERENT actor rearms with evidence
(`hb regate <gate> --rearm --artifact <file>`), then
a fresh pass pins the revised criteria. The whole cycle must postdate the drift; then the
last cycle absolves all earlier drift on that gate — late rigor is still rigor, and the
unsanctioned window stays in the log (`case_cure`). A bare declare absolves nothing;
declare + rearm without the fresh pass absolves nothing; a cycle on a different gate
absolves nothing; an old pre-drift cycle plus a plain re-pass absolves nothing (all in
`case_cure`).

**Strengthening is also a revision.** An honest "make the gate stricter, then re-run"
drifts exactly like a weakening — the tripwire pins *change*, not direction, because
direction is a judgment the review exists to make. Declare the regate first, or cure
after; either way it costs one extra gate run, and the review is the point.

**Honest limits, stated.** `desc` and `timeout_s` are not pinned — reword and re-budget
freely (`case_drift` d6). Criteria `id`/`cmd` are strings in any real dag and compare
byte-exact; out-of-schema values compare as a type class, identically on both runtimes
(d7). Sanctioned mutations stay quiet: a declared regate's window, the full
declare→rearm→fresh-pass flow, and `detach`/`reattach` (`case_quiet`) — and an append
(asserted in `case_append`). And the
trust model is **procedural**, not cryptographic: `HB_ACTOR` strings are self-declared
identity, one human can play declarer and rearmer, and a forged or truncated event log is
outside the tripwire's reach — the log is the same trusted input the whole event-sourced
design already assumes. The tripwire makes the quiet path loud; it does not authenticate
the actors walking it.

The horizon marker has the same honest edge. It is plan surface, like `desc` — the drift
tripwire pins only a completed gate's criteria — so deleting the flag from the completed
phase, or parking the flagged phase, silences the wake with doctor quiet on both runtimes
(`case_limits` l1, l2). The recorded way to end a horizon is the close verb; a hand-appended
`horizon_closed` event is accepted like any other log line, under the same procedural trust.

## Prove it

```bash
bash tests/replan.sh               # REPLAN-OK — the append/edit/tripwire claims, both runtimes
bash tests/replan.sh --selftest    # REPLAN-SELFTEST-OK — that proof's own teeth
bash tests/horizon.sh              # HORIZON-OK — the marker/wake/close/audit claims, both runtimes
bash tests/horizon.sh --selftest   # HORIZON-SELFTEST-OK — each stripped horizon guard reddens its check
```

The suite wires them as groups T184 and T185 (outcome-keyed on those markers), and
`tests/parity.sh` holds the cross-runtime verdicts byte-identical (`drift:cross`,
`horizon:resolve`, `horizon:project`, `horizon:lint`, `horizon:audit`).
