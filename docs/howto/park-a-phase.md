# Park a phase (retire a gate without deleting it)

A drafted phase you have decided not to build — or a phase whose gate was refuted as unsound
and set aside — must come out of the plan's **live surface**. Deleting it is the wrong move:
phases carry `gate_exit`, so removing a gate leaves a dangling reference (`hb lint` catches
exactly that), and deletion destroys the record of what was planned. **Parking** keeps every
reference intact and is reversible.

## Do it

```bash
hb park GATE_P19 --reason "refuted as unsound" --dir <project>   # by GATE id…
hb park P19 --dir <project>                                      # …or by PHASE id
hb unpark P19 --dir <project>                                    # bring it back
```

(Node runtime: `node .hb/hb.js park GATE_P19 refuted as unsound` / `node .hb/hb.js unpark P19`.)

`park` accepts a phase id or a gate id — a gate id resolves to the phase that carries it as
`gate_exit`. It sets `parked: true` (and `parked_reason`) on the phase in `dag.json`; nothing
else changes, and an unknown id is refused.

## What parked means

Everything that reads the plan honors it, loudly:

- **Resolver / tick** — the phase's tasks are never offered, it never raises `gate_pending`,
  and `all_done` is reachable without it. (A parked *completed* phase still satisfies
  downstream `gate_entry` references — parking never re-blocks other phases.)
- **Audit** — the phase's gate is skipped, so an unsound-but-parked gate no longer blocks
  `hb audit` from coming back clean; the skip is reported
  (`⏸ skipped 1 parked phase(s): P19 (unpark to re-audit)`). Unparking restores the audit
  findings — the debt returns with the phase.
- **Regression sweep / pre-push** — `--all` retires the phase's gate from **evaluation** even
  if it was **armed** (ever-passed), reported as `— skipped N parked gate(s): …`, never
  silently. Parking does NOT silence the gate's open obligations: a pending regate or
  unsanctioned criteria drift on a parked gate stays in the failing count, annotated
  (`tests/regate-fail-closed.sh` case_park, `tests/replan.sh` case_sweep).
- **Report** — the phase is listed under `parked`, marked `⏸`, and excluded from the
  progress denominator; it is never silently gone.

## Why parking, not hand-editing

`dag.json` is the plan, and editing it is normal — the "never hand-edit" rule protects
*state* (`events.jsonl` / `state.json`), not the plan. But retiring a phase touches several
invariants at once (dangling `gate_exit`, audit-clean, sweep arming), and the command makes
the safe move atomic and reversible instead of an under-pressure improvisation.

## Proof

[`gate-examples/park-phase.sh`](gate-examples/park-phase.sh) (T162) drives the real CLI:
park by gate id → audit goes clean and reports the skip; unpark → the audit error returns
(reversible, not a deletion); the resolver offers only live work and reaches `all_done`;
report shows the phase as parked with an honest denominator; `--all` skips an armed parked
gate loudly; an unknown id is refused. Node and python are held to the same semantics
(T162.2–6 + the `parked` parity cases in `tests/parity.sh`). Run it:

```bash
bash docs/howto/gate-examples/park-phase.sh   # -> PARK-PHASE-OK
```
