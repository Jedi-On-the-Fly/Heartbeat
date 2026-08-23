# Block pushes on failing gates (the pre-push guard)

HeartBeat verifies work with gates, but a gate only helps if it's still *run*. Between commits, a gate
can silently rot — a file it checks gets moved, a dependency changes, a doc drifts from the code it
describes. The **pre-push gate guard** closes that window at the last safe moment: before anything leaves
your machine, it re-verifies **every** gate and blocks the push if any no longer passes.

## What bootstrap installs

Every HeartBeat project — bootstrapped by the node `bootstrap.sh` **or** the Python `hb init` — gets a
`.git/hooks/pre-push` hook that, on `git push`, runs a **read-only re-verification of all gates**
(`gate.sh --all` in a node project, `hb gate --all` in a Python one) and:

- **exits 0** (push proceeds) if every gate still verifies;
- **exits 1** (push blocked) if any gate fails, printing which command to run to see the failure.

It's the push-time complement to the existing **pre-commit rot guard** (which blocks a *commit* that
deletes a file a completed gate depends on). Together: you can't commit a change that breaks a gate's
reproducibility, and you can't push a state where a gate no longer passes.

## Why pre-push, not pre-commit

HeartBeat **auto-commits on every gate pass** (`HB_GIT_AUTOCOMMIT`), so a full re-verification on every
commit would fire dozens of times during a run and could abort HeartBeat's own commits. A push is
manual, happens once, and is the boundary where a bad state actually escapes — so that's where the full
re-verification belongs. (HeartBeat never auto-pushes, so this hook only ever fires on *your* `git push`.)

## Installation is safe

- **Non-destructive.** If a `pre-push` hook already exists, bootstrap leaves it untouched — it never
  clobbers your hook.
- **Fresh or existing repos.** It installs whether bootstrap just ran `git init` or the project was
  already a repo.
- **Opt-out.** Skip the whole re-verification for one push with `git push --no-verify`, or set
  `HB_NO_HOOK=1` in the environment. Disable git integration entirely at bootstrap with `HB_NO_GIT=1`.

## Proof

The behavior is backed by runnable proofs wired into the suite:

```bash
bash docs/howto/gate-examples/pre-push-hook.sh           # -> PRE-PUSH-HOOK-OK  (T117: blocks on fail, allows on pass, non-clobber, HB_NO_HOOK, existing repos)
bash docs/howto/gate-examples/pre-push-hook-parity.sh    # -> PRE-PUSH-PARITY-OK (T118: node ≡ python — both block iff gate re-verify fails)
bash docs/howto/gate-examples/pre-push-selfcontained.sh  # -> PRE-PUSH-SELFCONTAINED-OK (T122: hook is self-contained — tested as it runs)
```

The proofs bootstrap throwaway projects and assert the hook blocks exactly when `gate.sh --all` /
`hb gate --all` fails, leaves an existing hook alone, and honors `HB_NO_HOOK`. The two runtimes' hook
bodies differ (each calls its own gate tool), so parity is **behavioral** — the hook blocks iff a gate
regresses — not byte-identical, as noted in [parity-notes.md](../../planning/parity-notes.md).

The self-containment proof (T122) runs the hook under a **stripped toolchain PATH** — no `PYTHONPATH`, no
`hb` on `PATH` — because a hook that only works with your shell's conveniences isn't self-contained: the
node hook (`gate.sh --all`) must still block on a failing gate, and the Python hook must **skip with a
message** when `hb` is absent (not die on an import error). That proof derives the clean PATH from where
`node`/`git`/`python3` actually live (they sit in a toolcache, not `/usr/bin`, on CI runners) — the
portability trap catalogued in
[writing-behavioral-gates.md](writing-behavioral-gates.md#environment-portability).
