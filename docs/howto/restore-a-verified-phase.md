# Restore a verified phase

Every gate pass commits the working tree and force-tags the gate id. So each phase HeartBeat
verified is a **restore point** — a known-good commit you can roll the project back to when a
later change breaks something. This is what makes long autonomous runs safe to experiment on.

## Do it

When a passed phase's gate is `GATE_P3`, the commit is tagged `GATE_P3` (the tag is the gate
id). To return to the state where that phase last verified:

```bash
git reset --hard GATE_P3     # tracked files := the working tree when P3's gate passed
```

The auto-commit is on by default; disable it with `HB_GIT_AUTOCOMMIT=0` (then no restore
points are created). Bootstrap runs `git init` unless `HB_NO_GIT=1`, and the commits use a
fallback identity, so tagging works even without a configured git user.

## Why it matters

A long run touches many files; a change in phase 6 can silently break what phase 3 proved.
Instead of trying to un-edit by hand, roll back to the last gate that passed and continue from
there. Combined with re-verification ([re-verify-completed-gates.md](re-verify-completed-gates.md)),
you get: detect the regression with `hb gate --all`, then restore to the last good tag.

Restore points cover **tracked** project state — `git reset --hard` restores committed files;
untracked scratch files are left alone (use `git clean` if you want them gone).

## Proof

[`gate-examples/restore-points.sh`](gate-examples/restore-points.sh) drives the real hb CLI in
a git repo: passing the gate creates the tag (absent before); a destructive change makes the
gate `would_block`; `git reset --hard <gate-tag>` restores the artifact and the gate
`would_pass` again; and with `HB_GIT_AUTOCOMMIT=0` no tag is created. Run it:

```bash
bash docs/howto/gate-examples/restore-points.sh   # -> RESTORE-POINTS-OK
```
