---
name: heartbeat
description: HeartBeat tick-driven agent orchestration — bootstrap projects, run ticks, validate DAGs, generate reports and visualizations, and schedule autonomous runs. Use when the user mentions HeartBeat, /heartbeat, or wants to orchestrate a multi-phase project with quality gates.
---

# HeartBeat Skill (Claude Code)

Tick-driven agent orchestration. **Stage A** (`tick.sh`, pure bash, ~0 tokens) runs
on a schedule and does 6 priority checks. **Stage B** (this LLM) wakes only when
real work exists, driven by `data.reason`.

A project is a DAG (`dag.json`): phases → tasks → dependencies + quality gates.
Bootstrap creates a `.hb/` directory inside any project folder.

**Plugin files** live under `${CLAUDE_PLUGIN_ROOT}`:
- Bootstrap: `${CLAUDE_PLUGIN_ROOT}/bootstrap.sh`
- Templates: `${CLAUDE_PLUGIN_ROOT}/templates/`

After bootstrap, each project carries its own copies of the tools in `<dir>/.hb/`.

---

## Commands

### `/heartbeat init <project-dir>`
Bootstrap a new HeartBeat project:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/bootstrap.sh" <project-dir>
```
Then tell the user to:
- Edit `<project-dir>/.hb/dag.json` (phases, tasks, gates).
- Validate: `node <project-dir>/.hb/hb-lint.js <project-dir>/.hb/dag.json`.
- Schedule autonomous runs: `/heartbeat schedule <project-dir>`.

### `/heartbeat status <project-dir>`
```bash
node <project-dir>/.hb/hb-report.js <project-dir>/.hb
```
Also read `<project-dir>/.hb/state.json` for current phase and task counts.

### `/heartbeat lint <project-dir>`
```bash
node <project-dir>/.hb/hb-lint.js <project-dir>/.hb/dag.json
```
Reports duplicate IDs, cycles, broken `requires`, undefined gates, phases > 8 tasks.

### `/heartbeat viz <project-dir>`
```bash
node <project-dir>/.hb/hb-viz.js <project-dir>/.hb
```
Output: `<project-dir>/.hb/dag-view.html` — self-contained, no external deps.

### `/heartbeat tick <project-dir>`
Run a manual Stage A tick:
```bash
bash <project-dir>/.hb/tick.sh
```
Returns `{ wakeAgent, data }`. If `wakeAgent: true`, act on `data.reason` per the
Tick Protocol below.

### `/heartbeat schedule <project-dir>`
Drive ticks autonomously on Claude Code using a **`/schedule` routine** (cron).
Present this ready-to-use routine to the user (fill in `<project-dir>`, `<slug>`,
`<repo>`), and offer to create it via `/schedule`:

```
Routine: HeartBeat tick — <slug>
Trigger: schedule, cron "*/20 * * * *"   (every 20 min)
Repositories: <repo>                     (the git repo containing <project-dir>)
Prompt: |
  Run one HeartBeat tick for project <slug>:
    bash <project-dir>/.hb/tick.sh
  Parse the JSON output. If wakeAgent is false, stop. If true, act on
  data.reason per the HeartBeat Tick Protocol (next_task, gate_pending,
  gate_blocked, state_corrupted, dag_corrupted, deadlock, unsanctioned_drift,
  build_stuck, all_done). Update .hb/state.json atomically (tmp + rename) and
  append a task_done event to .hb/events.jsonl.
  ALWAYS at end of session: rm -rf <project-dir>/.hb/.lock
```

**Important caveat — where the routine runs.** Claude Code `/schedule` routines
execute in Anthropic's cloud and clone a **GitHub repo** for each run. So a routine
drives ticks correctly only when `<project-dir>` lives in a git repo the routine
clones. For **local-only** projects, use one of:
- **In-session:** `/loop 20m /heartbeat tick <project-dir>` (runs only while a
  Claude Code session is open).
- **System cron** on the user's machine calling headless Claude Code, e.g.
  `*/20 * * * * cd <project-dir> && claude -p "Run bash .hb/tick.sh and act on data.reason per the HeartBeat Tick Protocol; rm -rf .hb/.lock at end."`

### `/heartbeat help`
Reply with:
```
*HeartBeat v1.3 — commands:*
• /heartbeat init <dir>     — bootstrap a new project
• /heartbeat status <dir>   — progress report
• /heartbeat lint <dir>     — validate the DAG
• /heartbeat viz <dir>      — generate dag-view.html
• /heartbeat tick <dir>     — manual tick
• /heartbeat schedule <dir> — ready-to-use /schedule routine
• /heartbeat help           — this help
```

---

## HeartBeat Tick Protocol (Stage B)

**Never hand-edit `state.json`.** It is a projection of `events.jsonl`. Mutate
state ONLY through the `hb` CLI — it appends the event and reprojects atomically:

```bash
node .hb/hb.js start <taskId>      # claim the task (lease) + mark active
node .hb/hb.js done  <taskId>      # completed → frees the lease, resets stuck count
node .hb/hb.js fail  <taskId>      # failed    → frees the lease, bumps stuck count
node .hb/hb.js heartbeat <taskId>  # long task: refresh the lease so it isn't reclaimed
node .hb/hb.js rebuild             # reproject state.json from the log (sync / recover)
node .hb/hb.js state               # print current projected state
```

**Long-running tasks:** call `node .hb/hb.js heartbeat <id>` at least every
`HEARTBEAT_STALE_S` (default 180s) — e.g. between sub-steps. A heartbeated lease
that goes silent is reclaimed fast (hung agent); a lease that never heartbeats
falls back to the slower `LOCK_STALE_S` deadline.

When woken by a tick (`data.reason` present), act by reason:

| `data.reason` | Action |
|---|---|
| `next_task` | `node .hb/hb.js start <id>` → do the work → `node .hb/hb.js done <id>` (or `fail <id>` if you couldn't complete it). No hand-edited JSON. |
| `gate_pending` | `bash .hb/gate.sh <data.next_task.gate>`. gate.sh reprojects, so a pass advances the phase automatically; a fail sets `gate.errors`. |
| `gate_blocked` | Fix the failing criteria, re-run `bash .hb/gate.sh <gate>`. |
| `at_capacity` | Nothing to do — max tasks already in flight (or the only ready task is leased). The tick handled it; no wake. |
| `state_corrupted` | `node .hb/hb.js rebuild` (replays events.jsonl). The tick self-heals this; only surfaces if the log itself is unusable. |
| `dag_corrupted` | Restore dag.json from git/backup (structure is immutable). |
| `deadlock` | `active_orphan` → the stale-lease reclaim frees it automatically; if it persists, `hb fail <id>`. `dag_invalid` → surface errors for human review. |
| `unsanctioned_drift` | Review the diff. If intended: `bash .hb/tick.sh --freeze`. |
| `build_stuck` | `signal: no_progress` means the agent was woken repeatedly without progressing. Produce a blocker report for human review. |
| `all_done` | Write the final project report. |

**End of session:** finish each claimed task with `hb done`/`hb fail` — that frees
its lease. The tick's handout lock is released automatically (no more `rm -rf .lock`).
A crashed session's lease is reclaimed after `LOCK_STALE_S`.

**Parallelism:** set `HB_MAX_CONCURRENCY > 1` (env) to run independent DAG branches
concurrently — overlapping ticks hand out distinct ready tasks up to the cap.
Default `1` keeps the classic one-task-at-a-time behavior.

---

## Reference
- Bootstrap: `${CLAUDE_PLUGIN_ROOT}/bootstrap.sh`
- Templates: `${CLAUDE_PLUGIN_ROOT}/templates/`
- Full guide, install docs, and the regression suite live in the HeartBeat
  repository (README.md, INSTALL.md, tests/run-tests.sh).
