# Add HeartBeat to an existing repository

**Outcome:** add HeartBeat to a repo that already has code and history, without disturbing any
of it. Bootstrapping is additive — it creates a `.hb/` directory and leaves your files and
commits alone.

## Do it

From inside (or pointing at) your repo:

```bash
hb init .                 # scaffold .hb/ in the current repo
hb audit --dir .          # refuse hollow gates before you run anything
```

`hb init` creates `.hb/` (the DAG, the event log, the state projection, the gate runner) next
to your existing files. It does **not** rewrite your code, and if the directory is already a
git repository it will **not** re-initialize git — your history is untouched.

## What it adds, and how it coexists

- **`.hb/`** holds everything HeartBeat needs; nothing outside it is modified on setup.
- **Git.** On a fresh (non-git) directory HeartBeat runs `git init` for you; in an existing
  repo it detects git and skips that. Every gate pass then commits the working tree and tags
  the gate id, so each verified phase is a restore point. If you'd rather HeartBeat not commit,
  set `HB_GIT_AUTOCOMMIT=0`; to disable git integration entirely, `HB_NO_GIT=1`.
- **`.gitignore`.** Decide whether to track `.hb/`. Tracking it makes the plan and event log
  part of history (useful for a shared or CI-run project); ignoring it keeps HeartBeat's state
  local. `state.json` is a disposable projection of `events.jsonl` either way — never hand-edit
  it (see [never-hand-edit-state.md](never-hand-edit-state.md)).

## Then use it

Describe the work you're adding as a DAG (`phases → tasks → behavioral gates`), audit and
refute the plan, and drive it with whatever worker suits the repo — see
[choose-a-backend.md](choose-a-backend.md) and [choose-runtime.md](choose-runtime.md). Existing
CI keeps working; HeartBeat runs alongside it and gates on exit codes
([run-heartbeat-in-ci.md](run-heartbeat-in-ci.md)).

## Prove it worked

A runnable proof starts from a repo with a tracked file and a commit, adds HeartBeat, and
asserts the files are byte-for-byte unchanged and the prior commit is still reachable:

```bash
bash docs/howto/gate-examples/existing-repo.sh   # -> EXISTING-REPO-OK
```
