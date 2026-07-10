# Snippet to add to CLAUDE.md
# (paste at the end of the file)
# Only needed for the install-script path — the plugin ships this protocol in its skill.
# Adjust HEARTBEAT_HOME if you installed elsewhere.

---

## HeartBeat — native system integration

Bootstrap: `~/.claude/heartbeat/bootstrap.sh`
Templates: `~/.claude/heartbeat/templates/`
Skill: `/heartbeat` (installed under `~/.claude/skills/heartbeat/`)

### Manual commands (`/heartbeat`)

| Command | Action |
|---|---|
| `/heartbeat init <dir>` | `bash ~/.claude/heartbeat/bootstrap.sh <dir>` |
| `/heartbeat plan <dir>` | Convert a written plan into a lint-clean `dag.json` (spec-first, behavioral gates, adversarial `review` on sensitive gates); gate on `hb-lint`+`hb-viz` |
| `/heartbeat status <dir>` | `node <dir>/.hb/hb-report.js <dir>/.hb` |
| `/heartbeat lint <dir>` | `node <dir>/.hb/hb-lint.js <dir>/.hb/dag.json` |
| `/heartbeat viz <dir>` | `node <dir>/.hb/hb-viz.js <dir>/.hb` → `<dir>/.hb/dag-view.html` |
| `/heartbeat tick <dir>` | `bash <dir>/.hb/tick.sh` → act on `data.reason` |
| `/heartbeat schedule <dir>` | Emit a Claude Code `/schedule` routine (see below) |
| `/heartbeat help` | List commands |

### Scheduling on Claude Code

Drive ticks with a **`/schedule` routine** (cron). Routines run in Anthropic's
cloud and clone a GitHub repo, so this fits when the project is a git repo.
For local-only projects, use `/loop 20m /heartbeat tick <dir>` while a session is
open, or a system cron calling `claude -p`.

### HeartBeat Tick Protocol (Stage B — automatic runs)

**Never hand-edit `state.json`** — it is a projection of `events.jsonl`. Mutate
state only via the `hb` CLI (appends event + reprojects atomically):
`node .hb/hb.js start|done|fail <id>`, `node .hb/hb.js rebuild`, `node .hb/hb.js state`.
Long task? `node .hb/hb.js heartbeat <id>` every ≤`HEARTBEAT_STALE_S` (default 180s)
so a hung session's lease is reclaimed fast instead of after `LOCK_STALE_S`.

When woken by a tick (`data.reason` present in context):

| `data.reason` | Action |
|---|---|
| `next_task` | `hb start <id>` → do the work → `hb done <id>` (or `hb fail <id>`). |
| `gate_pending` | `bash .hb/gate.sh <data.next_task.gate>`. A pass advances the phase unless the gate has a `review` block (→ `review_pending`). |
| `review_pending` | Spawn a skeptical second agent to REFUTE completion, then `hb review <gate> pass\|fail "<findings>"`. Only a pass advances the phase. |
| `gate_blocked` | Fix the failing criteria/findings. Re-run the gate. |
| `at_capacity` | Nothing to do — max tasks in flight / only ready task is leased. |
| `state_corrupted` | `node .hb/hb.js rebuild` (tick self-heals; surfaces only if the log is unusable). |
| `dag_corrupted` | `git checkout HEAD -- .hb/dag.json` (structure is immutable). |
| `deadlock` | `active_orphan` → reclaimed automatically; if it persists `hb fail <id>`. `dag_invalid` → surface for human review. |
| `unsanctioned_drift` | Review the diff. If intended: `bash .hb/tick.sh --freeze`. |
| `build_stuck` | `signal: no_progress` = woken repeatedly without progress. Produce a blocker report. |
| `all_done` | Write the final project report. |

**Version control:** bootstrap runs `git init`; every gate pass commits + force-tags
the gate id → `git reset --hard GATE_PN` rolls a phase back. Disable via `HB_NO_GIT` /
`HB_GIT_AUTOCOMMIT=0`.

**End of session:** finish each task with `hb done`/`hb fail` (frees its lease).
The handout lock is released automatically; a crashed session's lease is reclaimed
after `LOCK_STALE_S`. Parallelism: `HB_MAX_CONCURRENCY > 1` (default 1 = serial).
