# STATUS — HeartBeat

**Version:** v1.5 (gate integrity over v1.4)
**Regression suite:** `bash tests/run-tests.sh`

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
