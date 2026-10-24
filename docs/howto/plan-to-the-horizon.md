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
  planning analogue of a hollow gate: unfalsifiable structure that reads as rigor. The plan
  refuter should flag it the way `hb-audit` flags `test -f`.
- **End the horizon with an explicit replan point** — a final task whose gate verifies two
  things behaviorally: the learning is *recorded* (a findings file, a decision doc — a real
  artifact a criterion can test), and the next horizon is *planned* (the appended dag
  lints clean and survives its own refutation).
- **Size the horizon honestly.** One phase is a fine horizon. The cost of a short horizon
  is one more replan point; the cost of a long one is fabricated phases you will either
  execute against dead premises or hand-edit — and the tripwire below makes the second
  path loud.

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

## Prove it

```bash
bash tests/replan.sh              # REPLAN-OK — every claim above, both runtimes
bash tests/replan.sh --selftest   # REPLAN-SELFTEST-OK — the proof's own teeth
```

The suite wires both as group T184 (outcome-keyed on those markers), and
`tests/parity.sh` holds the cross-runtime verdicts byte-identical (`drift:cross`).
