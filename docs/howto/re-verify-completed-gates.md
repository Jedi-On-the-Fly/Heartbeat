# Re-verify completed gates

A passed gate is not a permanent stamp — it is a claim about reality **at the time it ran**.
Because HeartBeat's gates are behavioral and re-runnable, that claim can be re-checked later,
read-only, and caught if the work has decayed. This is what keeps a long project's "done"
honest.

## Do it

```bash
hb gate <GATE> --check     # re-run one gate read-only: would_pass / would_block
hb gate --all              # re-run every EVER-PASSED gate; non-zero if any would block
```

`--check` runs the same criteria without recording anything — it never advances or blocks a
phase, it just tells you whether the proof still holds. `--all` is the regression sweep: run
it after a change that could invalidate earlier work.

`--all` arms only gates with a recorded `gate_passed` event. A **planned** gate — a drafted
future phase whose criteria name files that don't exist yet — has never passed, so it has
nothing to regress from; the sweep skips it and says so
(`— skipped N planned gate(s) (never passed): …`), never silently. This is what keeps drafting
a DAG's future phases from failing the sweep (and, via the
[pre-push guard](block-pushes-on-failing-gates.md), from blocking pushes on unrelated work).
An explicit `hb gate <GATE> --check` still runs *any* gate, planned or not — a deliberate
probe is not a regression sweep.

## Why it matters

Two decay modes this catches:

- **Rot** — a completed gate references a file that has since been deleted or changed, so the
  gate can no longer reproduce its result. (`doctor` also flags this statically — see
  [recover-a-dead-or-corrupted-run.md](recover-a-dead-or-corrupted-run.md).)
- **Regression** — a later change breaks something an earlier phase proved. `hb gate --all`
  turns a silent "still green" into an actual re-check.

Never "fix" a re-verification failure by weakening the criterion — that just hides the decay.
Fix the work, or restore to the last good state
([restore-a-verified-phase.md](restore-a-verified-phase.md)).

## Proof

[`gate-examples/gate-reverify.sh`](gate-examples/gate-reverify.sh) drives the real hb CLI:
a completed gate re-verifies (`would_pass`, `--all` passes) and appends **no events**
(read-only); a drafted planned gate does **not** fail the sweep and its skip is reported;
then it regresses the artifact and shows re-verification still catches it
(`would_block` — the planned-skip never over-skips an armed gate); restoring the artifact
restores `would_pass`. Run it:

```bash
bash docs/howto/gate-examples/gate-reverify.sh   # -> REVERIFY-OK
```
