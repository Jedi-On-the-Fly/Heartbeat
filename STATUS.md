# STATUS — HeartBeat

**Version:** v1.9 (adversarial DAG review, over v1.8)
**Regression suite:** `bash tests/run-tests.sh`

## v1.9 — adversarial DAG review (gate quality)

- **`hb-audit.js` + `/heartbeat audit`.** Where `lint` checks structure, `audit` checks
  **gate quality** — the thing that actually bounds HeartBeat's value. It applies
  refute-don't-confirm to the *plan* before you run it, flagging **hollow_gate** (a phase
  whose gate has no behavioral criterion), **ungated**, **unguarded_phase**,
  existence-only / vacuous criteria, **nondeterministic** gates, and **gate_offphase**.
  Exit 1 on any hollow gate. The agent-refutation layer (a skeptical second read of the
  whole DAG) sits on top, documented in the skill.
- **Ported to both runtimes** — `hb-audit.js` (node) and `heartbeat.audit` (`hb audit`,
  Python) share one ruleset and are checked for **parity** on shared fixtures
  (`planning/audit-fixtures/`, see `planning/parity-notes.md`).

## v1.8 — pluggable Stage B

- **`hb-exec.js` executor driver + `/heartbeat exec`.** Stage B is now pluggable. The
  driver runs the same serial loop as `/heartbeat run` but dispatches each task to a
  **backend agent** (`claude-code`, `agno`, `crewai`, or a raw `script`) over a tiny
  JSON wire protocol — so an unattended process can do the work. HeartBeat stays the
  deterministic brain: the tick decides what/when, the gates verify, and the driver
  mediates **every** state transition (the backend never touches `state.json`/`gate.sh`).
- **Wire protocol.** `driver → backend`: `argv[last]=execute|refute`, stdin = payload
  JSON. `backend → driver`: `execute → {ok,summary}`, `refute → {refuted,findings}`.
  A backend is ~two methods; shipped adapters live in `.hb/executors/`.
- **Driver owns the hard parts** (framework-blind): the lease **heartbeat pump** during
  a task, **context assembly** from settled reality (dag + state + git log + gate
  criteria), **escalate-only** on a blocked gate (never auto-fixes), a per-task
  **attempt cap** (`HB_EXEC_ATTEMPT_CAP`, default 3), and **strict mode**
  (`HB_EXEC_STRICT=1`) that refuses non-behavioral gates / lint-warning DAGs.
- **Parallel fan-out** (`HB_MAX_CONCURRENCY > 1` / `run --parallel N`): the runnable
  set (`hb ready N`) runs concurrently, **each task in its own git worktree** so writes
  can't collide; the **merge-back is serialized** and a failed task's worktree is
  discarded. Falls back to concurrent in-place without git.
- **Backends**: `claude-code` (default), `agno`, `crewai`, `ollama` (local models,
  stdlib-only), or a raw `script`. Each degrades to protocol-valid JSON when its
  runtime is absent. `tests/real-backend.sh` drives a live end-to-end run against a
  local model (verified with `qwen2.5:7b-instruct`: the model writes code, a
  behavioral gate compiles and runs it).

## v1.7 — never left guessing

- **Self-describing ticks.** Every wake embeds the exact next action in
  `data.action`, so any driver (cron, headless, another harness) knows what to do
  from the JSON alone.
- **One-source protocol.** A single `reason → action` map in `hb.js` drives
  `data.action`, `hb protocol`, and `.hb/PROTOCOL.md` (written at bootstrap, versioned
  with the project) — no more drift across skill / README / snippet.
- **`hb diagnose`.** For a blocked state, computes the root cause where the substrate
  can — which criteria fail, the commit that deleted a gate's file (git backward-trace),
  the deadlock cause — plus ordered recovery steps. Read-only.
- **SessionStart hook.** Detects a `.hb/` project and injects a tiny pointer, so a
  Claude Code session is always current regardless of installed skill version.
- Fixed a latent bug: `hb.js` is now safely `require`-able (CLI guarded).

## v1.6 — gate liveness

- **`review_stuck`** — an adversarial review that never resolves (agent doesn't run
  it / session died) is now caught by the objective no-progress breaker and escalated
  instead of silently stalling.
- **Automatic rot detection** — the tick runs `doctor` each tick and wakes `gate_rot`
  on rot; a **pre-commit hook** blocks a commit that deletes a file a completed gate
  depends on (bypass: `git commit --no-verify` / `HB_NO_HOOK=1`).

## v1.5 — gate integrity

- **`hb doctor`** — static integrity check. Headline: *rot detection* — a completed
  phase whose gate references a now-deleted file (that gate can no longer be
  reproduced). Also flags DAG errors, state/log drift, stale leases. Read-only.
- **Re-verifiable gates** — `gate.sh --check <GATE>` re-evaluates a gate read-only
  (no state change); `gate.sh --all` re-evaluates every gate (regression check). A
  passed gate keeps acting as a gate instead of a one-shot checkpoint.

## v1.4 — quality & throughput

- **Adversarial gates (second agent).** A gate may carry a `review` block; after the
  deterministic gate passes, the tick emits `review_pending` — a skeptical second
  agent must fail to *refute* completion (`hb review <gate> pass|fail`) before the
  phase advances. Closes the "grade-your-own-homework" hole. Review-less gates behave
  as before.
- **Parallel-when-no-conflict.** `hb ready [N]` surfaces the concurrently-runnable
  (eligible, unleased, requires-independent) set; fan it out as worktree-isolated
  sub-agents. `/heartbeat run` drives serial or parallel.
- **hb-lint advisory warnings.** Flags leftover template/placeholder text and gate
  criteria that reference files no task produces.
- **Notify hook.** `HB_NOTIFY_CMD` fires once on human-needed wakes (build_stuck,
  gate_blocked, deadlock, unsanctioned_drift, all_done). Timeout-bounded, fail-safe.
- **dag.schema.json** for editor validation; **per-task durations** in the report.
- **Git-aware.** Bootstrap runs `git init`; every gate pass commits and force-tags
  the gate id, so each phase is a restore point (`git reset --hard GATE_PN`). Opt out
  with `--no-git` / `HB_NO_GIT` / `HB_GIT_AUTOCOMMIT=0`.

## v1.3 — reliability hardening

- **Event-sourced state (`hb.js`).** `events.jsonl` is authoritative; `state.json`
  is a deterministic projection. Agents mutate state only via the `hb` CLI
  (`start`/`done`/`fail`/`rebuild`/`state`/`import`) — never by hand-editing JSON.
- **Objective no-progress detection.** The tick flags an agent that is woken
  repeatedly without progressing (`build_stuck`, `signal: no_progress`), independent
  of the agent's self-report.
- **Gate criterion timeout.** Each gate criterion runs under `GATE_TIMEOUT_S` (5s
  default) — a hanging criterion blocks the gate instead of hanging the tick.
- **Per-task leases + bounded concurrency.** `HB_MAX_CONCURRENCY` (default 1 =
  serial) lets independent DAG branches run in parallel; stale leases from crashed
  sessions are reclaimed automatically.
- **Mid-session heartbeat.** `hb heartbeat <id>` refreshes a lease during long
  work; a heartbeated lease that goes silent is reclaimed after `HEARTBEAT_STALE_S`
  (default 180s) instead of the slow `LOCK_STALE_S` — hung agents are caught in
  minutes. Leases that never heartbeat keep the slow fallback (no false reclaims).

## Stage A — tick.sh priority checks (order matches tick.sh)

1. **Lock** — atomic `mkdir` lock; guards concurrent ticks and the agent
   session. Stale locks (> `LOCK_STALE_S`, default 1800s) are auto-broken.
2. **Integrity** — corrupt `state.json` → wake `state_corrupted`; corrupt
   `dag.json` → wake `dag_corrupted`.
3. **Circuit breaker** — `build_stuck_count >= 5` → single wake `build_stuck`,
   then silence until human reset.
4. **Drift detection** — SHA256 of `WATCH_PATHS`; baseline auto-frozen on first
   run; unsanctioned change → wake `unsanctioned_drift`.
5. **Gate errors** — a previously failed gate (`gate.errors > 0`) → wake
   `gate_blocked`.
6. **Next task** — eligible pending task → wake; all tasks done but gate unpassed
   → `gate_pending`; project finished → single `all_done`; nothing actionable on
   an unfinished project → single `deadlock` with diagnostic.

Output is always `{ "wakeAgent": true|false, "data": { "reason": "...", ... } }`.

## Tooling (v1.2)

- `hb-next-task.js` — gate-aware resolver with deadlock diagnostics.
- `hb-lint.js` — static DAG validation (dup IDs, cycles, broken `requires`,
  undefined/unreachable gates, oversized phases).
- `hb-report.js` — progress report (text / `--json`).
- `hb-viz.js` — standalone `dag-view.html`.
- `gate.sh` — behavioural gate runner.

## Packaging

Distributed as a Claude Code plugin (local marketplace) and a fallback
`scripts/install.sh`. See `INSTALL.md`.
