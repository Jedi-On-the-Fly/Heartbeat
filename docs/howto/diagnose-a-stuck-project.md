# Diagnose a stuck project

When a run stops progressing, HeartBeat doesn't leave you guessing. `hb diagnose` reads the
settled state and computes the **specific** root cause and the recovery step — which criterion
failed, which file a completed gate can no longer find, which gate is waiting on a review.

## Do it

```bash
hb diagnose            # infer the current blocker and how to recover
hb diagnose <reason>   # diagnose a specific reason the tick handed you (e.g. gate_rot)
```

What it names, by blocker:

- **`gate_blocked`** — the gate and each failing criterion (the `✗` lines), plus the attempt
  count. Recovery: fix the code, not the criterion.
- **`gate_rot`** — the completed phase's gate references a file that no longer exists; it names
  the missing file (and, with git, the commit that deleted it). Recovery: restore the file or
  re-point the gate.
- **`review_stuck`** — the gate whose adversarial review never resolved. Recovery: run the
  refuter and record the verdict.
- **`build_stuck` / `deadlock`** — repeated no-progress, or an orphaned lease / invalid DAG; a
  `deadlock` whose resolver is missing or crashed names `Cause: resolver_error` and the cure
  (restore `.hb/hb-next-task.js`, or repair the python install).
- **`dag_corrupted`** — `dag.json` is unreadable or structurally malformed: the diagnosis names the
  first structure error (the one `hb lint` lists first) and the restore-or-fix cure; doctor then
  reports only the structure errors ([a-malformed-plan-fails-closed.md](a-malformed-plan-fails-closed.md)).

A healthy project reports `no blocker detected` — the diagnosis is not a constant. The
mechanisms behind these (rebuild, rot, liveness) are covered in
[recover-a-dead-or-corrupted-run.md](recover-a-dead-or-corrupted-run.md) and
[prove-liveness.md](prove-liveness.md).

## Proof

[`gate-examples/diagnose-accuracy.sh`](gate-examples/diagnose-accuracy.sh) drives the real hb
CLI, blocks a project three ways, and asserts diagnose names the *actual* cause each time — the
failing criterion `c2` (not the passing `c1`), the missing file `out.txt`, the awaiting gate
`GA0` — and that a healthy project reports no blocker. Run it:

```bash
bash docs/howto/gate-examples/diagnose-accuracy.sh   # -> DIAGNOSE-ACCURACY-OK
```
