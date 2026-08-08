# Dev — Plugin (node + bash)

Backend reference for the Claude Code plugin implementation. Concept: [heartbeat.md](heartbeat.md). Python port: [dev-python.md](dev-python.md). Tests: [dev-tests.md](dev-tests.md).

Two stages. **Stage A** (`tick.sh`, bash) reads settled reality and decides whether to wake **Stage B** (a model/agent). State is an event-sourced projection. A project is a DAG. Runtime is bash + node; Python appears only inside the backend adapters (`executors/*_exec.py`).

## Layout

| Path | Role |
|---|---|
| `plugin/.claude-plugin/plugin.json` | Plugin manifest (name, version) |
| `.claude-plugin/marketplace.json` | Local marketplace descriptor (`source: ./plugin`) |
| `plugin/bootstrap.sh` | Scaffolds `<project>/.hb/`; git init + hooks |
| `plugin/skills/heartbeat/SKILL.md` | `/heartbeat` command surface + Tick Protocol |
| `plugin/hooks/hooks.json` + `heartbeat-detect.sh` | SessionStart pointer when a `.hb/` exists |
| `plugin/templates/*` | Per-project tooling, copied into `.hb/` at bootstrap |

Every project owns copies of the templates under `.hb/`. `HB_DIR` = the `.hb/` dir; `PROJECT_DIR` = its parent.

## Templates → responsibility

| File | Responsibility | Module exports |
|---|---|---|
| `tick.sh` | Stage A: priority checks → wake/sleep JSON | — |
| `gate.sh` | Run a gate's shell criteria; commit+tag on pass | — |
| `hb.js` | State CLI + projector + `PROTOCOL` + doctor/diagnose | `project, phaseByGateExit, initialState, PROTOCOL, renderProtocolMd` |
| `hb-next-task.js` | Gate-aware resolver | `resolve, readyTasks` |
| `hb-lint.js` | Structural DAG validation | `lint, extractPaths` |
| `hb-audit.js` | Gate-quality audit (adversarial plan review) | `audit, classify, isNondet` |
| `hb-report.js` | Progress report (`--json`) | — |
| `hb-viz.js` | Standalone `dag-view.html` | — |
| `hb-exec.js` | Executor driver (pluggable Stage B) | `run, config, assembleContext, nonBehavioral, strictBlock` |
| `executors/*` | Backend adapters (wire protocol) | — |
| `dag.json`, `state.json` | Default templates seeded into `.hb/` | — |

## Data model

**`dag.json`** (immutable at runtime; restore from git if corrupt):

| Level | Fields |
|---|---|
| root | `_meta?`, `gates{}`, `phases[]` |
| phase | `id`, `title`, `gate_entry` (gateId\|null), `gate_exit` (gateId), `tasks[]` |
| task | `id`, `title`, `description`, `requires[]` |
| gate | `desc`, `review?{prompt}`, `criteria[]{id, desc, cmd}` |

`criteria[].cmd` is a one-line shell command; exit 0 = pass. `$PROJECT_DIR`/`$HB_DIR` in env.

**`events.jsonl`** — append-only, authoritative. State-mutating events:

| event | fields | projection effect |
|---|---|---|
| `initialized` | — | reset all |
| `task_started` | `task` | → active (unless already completed) |
| `task_done` | `task` | → completed; `build_stuck_count = 0` |
| `task_failed` | `task`, `reason?` | drop active; `build_stuck_count += 1` |
| `lease_expired` | `task` | drop active (reclaim) |
| `gate_passed` | `gate` | gate `det = true`; clear errors |
| `gate_failed` | `gate` | gate `det = false`; `errors = 1`; stuck += 1 |
| `review_passed` | `gate` | gate `rev = true` |
| `review_failed` | `gate` | gate `det = rev = false`; `errors = 1`; stuck += 1 |

Audit-only events (ignored by projector): `wake`, `review_wake`, and `log_event` markers (`stale_lock_broken`, `architecture_frozen`, `circuit_breaker_tripped`, `project_complete`, `deadlock_detected`, `gate_rot_detected`, `review_stalled`, `state_reprojected`, `unsanctioned_drift`).

**`state.json`** — projection of the log (never hand-edit):

| Field | Meaning |
|---|---|
| `current_phase` | first phase not in `completed_phases` (else last) |
| `active_tasks`, `completed_tasks` | task sets |
| `completed_phases` | phase `det` AND (no review OR `rev`) |
| `pending_reviews` | gates with review, `det` true, `rev` false |
| `build_stuck_count` | consecutive failures; circuit-breaker at 5 |
| `gate.errors` | 1 after a failed gate/review, else 0 |
| `last_event`, `last_updated` | audit |

Phase completion rule: a phase closes only when its `gate_exit` has `det` AND (the gate has no `review` OR `rev`). This is the projector invariant shared with the port ([parity-notes.md](../planning/parity-notes.md)).

## Stage A — `tick.sh`

Output contract (single JSON line): `{ "wakeAgent": bool, "data": { "reason": <string>, "action"?: <string>, ... } }`. On wake, `data.action` is injected from `hb.js` `PROTOCOL[reason]`. Invoke: `bash tick.sh` | `bash tick.sh --freeze` (re-baseline `WATCH_PATHS`).

Priority order (first match wins):

| # | Check | Wake reason (else) |
|---|---|---|
| 1 | Handout lock (`mkdir .lock`, stale > `LOCK_STALE_S`) | `already_running` (sleep) |
| 2 | `state.json` parseable (else reproject) | `state_corrupted` |
| 2 | `dag.json` parseable | `dag_corrupted` |
| 2.5 | Reclaim stale leases (`beat` > `HEARTBEAT_STALE_S`, else dir > `LOCK_STALE_S`) → `lease_expired` | (continues) |
| 2.6 | `HB_ROT_CHECK` → `hb.js doctor` rot | `gate_rot` (once), then `gate_rot_waiting` |
| 3 | `build_stuck_count >= 5` | `build_stuck` (once), then `stuck_waiting_human` |
| 4 | `WATCH_PATHS` sha changed | `unsanctioned_drift` |
| 5 | `gate.errors > 0` | `gate_blocked` |
| 6 | resolver (`hb-next-task.js`) | `next_task` / `gate_pending` / `review_pending` / `all_done` / `deadlock` / `at_capacity` (busy) / `no_pending_tasks` |

`next_task` path: enforce `HB_MAX_CONCURRENCY` (in-flight leases); no-progress guard (`STUCK_TICKS` consecutive `wake` events without a `task_*` → `build_stuck signal:no_progress`); else lease the task (`mkdir leases/<id>`), append `wake`, emit. `review_pending` appends `review_wake` and applies the same no-progress guard (→ `review_stuck`). "Once" reasons use flag files (`.stuck-alerted`, `.rot-alerted`, `.deadlock-alerted`, `.all-done-alerted`, `.noprogress-alerted`, `.review-stuck-alerted`, `.gate-notified`, `.drift-notified`) cleared on progress. `HB_NOTIFY_CMD` fires once per blockage on human-needed reasons.

## Gates — `gate.sh`

| Invocation | Effect | Exit |
|---|---|---|
| `gate.sh <GATE>` | eval criteria; on pass append `gate_passed`, reproject, git snapshot, announce review if any; on fail append `gate_failed` | pass 0 / blocked 1 / unknown 2 |
| `gate.sh --check <GATE>` | eval read-only, no state change | would-pass 0 / would-block 1 |
| `gate.sh --all` | eval every gate read-only | 0 / 1 |

Each criterion runs under `GATE_TIMEOUT_S` (timeout → fail). Git snapshot (unless `HB_NO_GIT` / `HB_GIT_AUTOCOMMIT=0`): `git add -A` → commit `--no-verify` (`heartbeat(<phase-id>): <title> [GATE]`) → force-tag the gate id. Restore a phase: `git reset --hard <GATE_ID>`.

## State CLI — `hb.js`

Mutation is `withWlock` (`.wlock` mkdir) → append event → reproject → atomic write.

| Command | Effect |
|---|---|
| `start <id>` | lease + `task_started` |
| `done <id>` | `task_done` + release lease |
| `fail <id> [reason]` | `task_failed` + release lease |
| `heartbeat`/`beat <id>` | refresh lease `beat` mtime |
| `review <gate> pass\|fail [note]` | `review_passed`/`review_failed` |
| `ready [N]` | JSON of `readyTasks` (concurrently-runnable set) |
| `doctor` | integrity: rot problems + notes; exit 1 on problems |
| `diagnose [reason]` | computed root-cause + recovery (read-only) |
| `protocol [reason] [--md] [--oneline]` | reason→action map / one action / `PROTOCOL.md` |
| `rebuild` | reproject from log |
| `state` | print projection |
| `import` | seed log from a legacy `state.json` |

`hb.js` is `require`-safe (CLI dispatch guarded by `require.main === module`); `tick.sh` requires it for `PROTOCOL`.

**`doctor`** — rot = a completed phase whose gate `cmd` references a now-missing path (via `extractPaths`); also DAG lint errors, state/log drift, stale leases. **`diagnose`** — infers the blocker (`gate_blocked` / `gate_rot` / `review_stuck` / `build_stuck` / `deadlock`) and prints failing criteria, git backward-trace of a deleted gate file (`git log --diff-filter=D`), or the deadlock cause.

**`PROTOCOL`** (single source of truth; drives `data.action`, `hb protocol`, `.hb/PROTOCOL.md`) reasons: `next_task, gate_pending, review_pending, gate_blocked, at_capacity, state_corrupted, dag_corrupted, deadlock, unsanctioned_drift, gate_rot, build_stuck, review_stuck, all_done`.

## Resolver — `hb-next-task.js`

`resolve(state, dag, hbDir)` returns a task view `{id, phase, title, description, requires}` or `{type}` where type ∈ `gate_pending` (`+gate`), `review_pending` (`+gate`), `all_done`, `busy` (`+in_flight`), `deadlock` (`+cause: active_orphan|dag_invalid|unsatisfiable`). Eligibility: task pending + all `requires` done; phase reachable only if `gate_entry` passed. Leased tasks (`leases/<id>`) are excluded. `readyTasks(state, dag, hbDir, limit)` → all currently-runnable, unleased tasks.

## Lint — `hb-lint.js`

Errors (exit 1): duplicate task ID; `requires` non-existent; dependency cycle; undefined gate; `gate_entry` that is no phase's `gate_exit`. Warnings (exit 0): phase > 8 tasks; gate defined-but-unreferenced; skeleton/placeholder text; gate cmd referencing a path no task produces (`extractPaths` heuristic). `extractPaths(cmd)` strips `$PROJECT_DIR`/`$HB_DIR` and state files.

## Audit

`hb-audit.js`. `classify(cmd)` → `vacuous` (trivially true) | `existence` (`test -f/-e/-d/-s`, `[`, `ls`) | `behavioral`. `isNondet(cmd)` → network/time (`curl|wget|nc|ping|sleep|$RANDOM|date|http(s) non-localhost`).

| Rule | Severity | Condition |
|---|---|---|
| `hollow_gate` | error | phase gate has criteria but none behavioral |
| `ungated` | error | gate has zero criteria |
| `unguarded_phase` | warn | phase has tasks, no `gate_exit` |
| `nondeterministic` | warn | a criterion touches network/time |
| `gate_offphase` | warn | gate references files no task in the phase mentions |
| `vacuous` / `existence` | info | per-criterion, when not the sole behavioral one |

Exit 1 on any error. Ruleset is byte-identical to the port ([dev-python.md](dev-python.md#audit)); parity-locked.

## Executor — `hb-exec.js`

Pluggable Stage B. `run` drives the same loop as a manual session but dispatches each task to a backend and mediates every state transition. `config` (env > `.hb/executor.json` > default):

| Key | Env | Default |
|---|---|---|
| `backend` | `HB_EXEC_BACKEND` | `claude-code` |
| `cmd` | `HB_EXEC_CMD` | `defaultCmd(backend)` |
| `strict` | `HB_EXEC_STRICT` | false |
| `attemptCap` | `HB_EXEC_ATTEMPT_CAP` | 3 |
| `concurrency` | `HB_MAX_CONCURRENCY` | 1 |
| `heartbeatMs` | `HB_EXEC_HEARTBEAT_MS` | `HEARTBEAT_STALE_S*1000/2` |

Loop: run `tick.sh` → route `data.reason`. `next_task` → `hb start` → dispatch execute (lease heartbeat pumped) → `hb done`/`hb fail` (+attempt cap → escalate). `gate_pending` → strict check (`strictBlock`: non-behavioral or lint-warning → escalate) → `gate.sh`. `review_pending` → dispatch refute → `hb review pass|fail`. `all_done` → report + stop. Any human-needed reason → escalate (`HB-EXEC STOP: <reason>`); escalate-only, never auto-fixes a blocked gate.

Parallel (`concurrency > 1`): free the tick's lease, fan out `hb ready N` concurrently; each task in its own git worktree (`.hb/wt/<id>`), merge-back serialized, worktree discarded on failure; in-place fallback without git.

## Backends — `executors/`

Wire protocol — driver spawns `bash -c "<cmd> <mode>"`, mode ∈ `execute|refute`, payload JSON on stdin, ONE JSON line on stdout:

| Mode | stdout |
|---|---|
| `execute` | `{"ok": bool, "summary": str}` |
| `refute` | `{"refuted": bool, "findings": str}` |

`defaultCmd`: `claude-code`→`claude-exec.sh`; each framework/local backend → its `<name>_exec.py` under `executors/` (`agno` `crewai` `ollama` `langgraph` `openai_agents` `autogen` `smolagents` `pydanticai`); else the string is the command. Backends never touch `state.json`/`gate.sh`.

| Backend | Worker mechanism | Notes |
|---|---|---|
| `claude-code` | headless `claude -p` | default |
| `agno` | Agno agent + `FileTools` | `HB_EXEC_PROVIDER=anthropic\|ollama` |
| `crewai` | CrewAI Agent+Task+Crew | `HB_EXEC_PROVIDER`; FILE-block writer |
| `langgraph` | LangGraph ReAct agent + `save_file` | `HB_EXEC_PROVIDER=anthropic\|ollama\|openai` |
| `openai-agents` | OpenAI Agents SDK + function tool | `HB_EXEC_PROVIDER=openai\|ollama` |
| `autogen` | AutoGen AssistantAgent | `HB_EXEC_PROVIDER=openai\|ollama`; FILE-block writer |
| `smolagents` | smolagents ToolCallingAgent + `save_file` | `HB_EXEC_PROVIDER=openai\|ollama` |
| `pydantic-ai` | pydantic-ai Agent + `save_file` | `HB_EXEC_PROVIDER=openai\|ollama` |
| `ollama` | stdlib `urllib` → local model | FILE-block mini-agent |
| `script` | arbitrary `HB_EXEC_CMD` | subprocess, any language |

Python backends redirect fd 1 → stderr so only the protocol JSON reaches stdout. `_fileblocks.py` parses `===FILE: path=== … ===END===` blocks (normalizes absolute/`$PROJECT_DIR` paths, concatenates split files, refuses `.hb/` and tree escapes).

## Bootstrap — `bootstrap.sh <dir> [--force] [--no-git]`

Copies templates into `.hb/` (incl. `executors/`), lints the seeded DAG, seeds `state.json`/`events.jsonl`, writes `PROTOCOL.md`, `chmod +x`. Unless `--no-git`/`HB_NO_GIT`: `git init`, `.gitignore` for ephemeral `.hb/` runtime, a pre-commit rot hook (blocks a commit deleting a file a completed gate needs; bypass `--no-verify`/`HB_NO_HOOK`), initial commit.

## Skill + hooks

`SKILL.md` commands: `init, plan, status, lint, audit, doctor, viz, tick, run, exec, schedule, help`. `/heartbeat plan` acceptance gate: lint clean + audit clean (0 hollow) + a refutation returning SOUND before proposing. `hooks.json` registers a SessionStart command (`heartbeat-detect.sh`) that prints a pointer when `$CLAUDE_PROJECT_DIR/.hb/hb.js` exists, silent otherwise.

## Environment variables

| Var | Default | Consumer |
|---|---|---|
| `LOCK_STALE_S` | 1800 | tick, hb.js |
| `HEARTBEAT_STALE_S` | 180 | tick, hb-exec |
| `STUCK_TICKS` | 3 | tick |
| `HB_MAX_CONCURRENCY` | 1 | tick, hb-exec |
| `GATE_TIMEOUT_S` | 5 | gate.sh |
| `HB_ROT_CHECK` | 1 | tick |
| `WATCH_PATHS` | (unset) | tick drift |
| `HB_NOTIFY_CMD` | (unset) | tick |
| `HB_NO_GIT` / `HB_GIT_AUTOCOMMIT` / `HB_NO_HOOK` | unset / 1 / unset | gate.sh, bootstrap |
| `HB_EXEC_BACKEND` / `HB_EXEC_CMD` / `HB_EXEC_STRICT` / `HB_EXEC_ATTEMPT_CAP` / `HB_EXEC_MAX_ITERS` / `HB_EXEC_MODEL` / `HB_EXEC_PROVIDER` | see config | hb-exec, backends |
| `OLLAMA_HOST` | `http://localhost:11434` | ollama backend |
| `HB_DIR` | script dir | all |
| `CLAUDE_PLUGIN_ROOT` / `CLAUDE_PROJECT_DIR` | Claude Code | skill, hooks |

## Invariants

- `events.jsonl` is authoritative; `state.json` is a pure projection — mutate only via `hb.js`. Reproduce with `hb rebuild`.
- Phase-completion and projection semantics must stay identical to the port (T43 parity).
- `hb.js` must remain `require`-safe (tick depends on it).
- `PROTOCOL` is the sole reason→action source; keep reason keys in sync with the port (action text may differ per runtime).
- Gate criteria must be behavioral, deterministic, < `GATE_TIMEOUT_S`; keep the seeded template audit-clean.
