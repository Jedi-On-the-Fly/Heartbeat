# PLAN — Reliability hardening (issues #1–#5)

Solve the five structural weaknesses:
1. Correctness delegated to a stochastic agent hand-editing JSON.
2. `state.json` not derived from `events.jsonl` (no single source of truth).
3. Circuit breaker trusts agent self-report of stuckness.
4. Gate criteria `eval` arbitrary bash with no timeout.
5. Single global lock ⇒ no parallelism across independent DAG branches.

**Governing design:** `events.jsonl` becomes authoritative. `state.json` is a pure
**projection** of the event log with the **same shape as today** (so `tick.sh`,
`hb-next-task.js`, `hb-report.js`, `hb-viz.js` keep working). A small `hb` CLI owns
every mutation (atomic append + reproject). This collapses #1, #2, and most of #3.
Per-task **leases** + bounded concurrency replace the single lock for #5.

**Config knobs (all overridable via env, safe defaults):**
- `GATE_TIMEOUT_S=5` — per-criterion timeout (#4)
- `STUCK_TICKS=3` — consecutive no-progress wakes before "stuck" (#3)
- `HB_MAX_CONCURRENCY=1` — in-flight task cap (#5); **1 = today's serial behavior**
- `LOCK_STALE_S=1800` — reused for lease + write-lock staleness

**Back-compat:** state.json shape unchanged. New bootstraps are event-sourced from
`initialized`. Legacy projects migrate via `hb import` (synthesizes events from an
existing state.json). Concurrency defaults to 1 → serial guarantee preserved.

**Ratchet:** `bash tests/run-tests.sh` stays green after every phase.

**Cascade:** P1 → P2 → P3 → P4 → P5  (P3, P4 both depend on P2; P4 last = riskiest).

---

## Phase 1 — Gate criterion timeout (#4)
**Cascade:** entry (independent)
**Tasks**
- 1.1 `gate.sh`: run each criterion through `timeout ${GATE_TIMEOUT_S}s` when a
  `timeout`/`gtimeout` binary exists; fall back cleanly if absent. A hanging or
  slow criterion → ✗ (not a hung tick).
- 1.2 Document `GATE_TIMEOUT_S` and the "dag.json is trusted input" note.
**Tests**
- Slow criterion (`sleep 10`) with `GATE_TIMEOUT_S=1` → gate exit 1, wall < 5s.
- Existing fast gates still pass (T2 unaffected).
**Gate G1 (checklist)**
- [ ] Slow criterion times out → gate blocked, returns quickly
- [ ] `timeout` absent → still runs (documented fallback), no crash
- [ ] Full suite green
**Report:** elapsed on the slow-criterion test; suite count.

---

## Phase 2 — Event-sourced state + `hb` CLI (#1, #2)
**Cascade:** after P1
**Tasks**
- 2.1 `templates/hb.js`: projector + CLI.
  - Projector `project(events, dag)` → state (same shape). State-mutating events:
    `initialized`, `task_started`, `task_done`, `task_failed`, `gate_passed`,
    `gate_failed`. `build_stuck_count` derived (reset on done/gate_passed, ++ on
    failed). `current_phase`/`completed_phases` derived from `gate_passed`.
  - Commands: `hb start|done|fail <id>`, `hb rebuild`, `hb state`, `hb import`.
  - Every mutation: acquire write-lock → append event → reproject → atomic write
    (tmp+rename) → release. `done`/`fail` also free the task's lease (P4 no-op now).
- 2.2 `bootstrap.sh`: copy `hb.js` into `.hb/`, `chmod +x`.
- 2.3 `gate.sh`: unchanged event format (`gate_passed`/`gate_failed`) — projector
  maps gate→phase via `dag.json`.
**Tests**
- `hb start/done/fail` produce expected projected state; lease/event side effects.
- Corrupt `state.json` → `hb rebuild` restores; rebuild is idempotent (twice = same).
- `gate.sh` pass → after reproject, phase advanced in state.
- `hb import` from a legacy state.json → rebuild matches the original state.
**Gate G2 (checklist)**
- [ ] state.json is reproducible from events.jsonl (`hb rebuild` deterministic)
- [ ] CLI mutations are atomic and match hand-edited semantics exactly
- [ ] gate pass advances the phase via projection (no manual edit)
- [ ] Legacy migration path (`hb import`) verified
- [ ] Full suite green (existing tests unchanged)
**Report:** command surface; projection determinism proof.

---

## Phase 3 — Objective no-progress detection (#3)
**Cascade:** after P2
**Tasks**
- 3.1 `tick.sh`: append a `wake` event (with target task id) each time it wakes an
  agent for a task.
- 3.2 Compute `no_progress = consecutive wake events for the in-flight task since
  its last task_started/done/failed`. `>= STUCK_TICKS` → `build_stuck` (single
  alert, reusing the existing one-shot flag), then silence.
- 3.3 Keep the derived `build_stuck_count >= 5` path too; both converge to
  `build_stuck`.
**Tests**
- Drive N wakes for the same task with no terminal event → tick wakes `build_stuck`
  once, then silent.
- A `task_done`/`task_failed` between wakes resets the no-progress counter.
**Gate G3 (checklist)**
- [ ] Agent looping WITHOUT reporting failure is caught objectively
- [ ] Single alert then silence (no wake storm)
- [ ] Progress resets the counter
- [ ] Full suite green
**Report:** threshold behavior; which signal fired.

---

## Phase 4 — Per-task leases + bounded concurrency (#5)
**Cascade:** after P2 (riskiest — last)
**Tasks**
- 4.1 Leases: `mkdir .hb/leases/<id>` atomic claim on `hb start`; removed on
  `hb done/fail`. Stale lease (> `LOCK_STALE_S`) auto-expired by tick →
  `lease_expired` event → task freed.
- 4.2 `tick.sh`: replace the single session lock with (a) a short **write-lock**
  around handout, (b) capacity check against `HB_MAX_CONCURRENCY`. In-flight =
  active leases. At capacity → `at_capacity` (sleep). The tick claims the lease
  before waking, so overlapping ticks hand out **distinct** ready tasks.
- 4.3 `HB_MAX_CONCURRENCY=1` reproduces today's "one task in flight" semantics.
**Tests**
- Concurrency 1: one lease at a time; second handout → `at_capacity` (parity with
  old `already_running`).
- Stale lease expired → task re-servable.
- Concurrency 2: two independent ready tasks → two distinct leases, capped at 2.
- `hb done` frees the lease.
- T5 rewritten to the lease model.
**Gate G4 (checklist)**
- [ ] Default (cap 1) behaves like the pre-change serial system
- [ ] Independent branches run concurrently up to the cap
- [ ] No task handed to two agents (atomic mkdir lease)
- [ ] Stale lease recovery works
- [ ] Full suite green
**Report:** serial-parity evidence; parallel handout evidence.

---

## Phase 5 — Protocol docs + final verification
**Cascade:** after P1–P4
**Tasks**
- 5.1 Update `skills/heartbeat/SKILL.md` + `CLAUDE-MD-SNIPPET.md`: agent uses
  `hb done/fail`, not hand-edited JSON; document `at_capacity`, leases, `hb rebuild`.
- 5.2 Update `README.md`: event model, CLI, leases, gate timeout, config knobs.
- 5.3 Add regression groups T16 (CLI/projector), T17 (no-progress), T18 (gate
  timeout), T19 (leases/concurrency).
- 5.4 Full run + end-to-end: bootstrap → start → fail → done → gate pass → rebuild.
**Gate G5 (checklist)**
- [ ] All tests green including new T16–T19
- [ ] Protocol docs describe the CLI-driven flow (no hand-edited state)
- [ ] End-to-end lifecycle passes on a fresh project
- [ ] Version strings consistent
**Report:** final pass count; before/after responsibility surface; file inventory.

---

## Success (overall)
- state.json is a deterministic projection of events.jsonl; agents mutate state
  only through `hb` (no hand-edited JSON).
- Stuckness is detected objectively, not on the agent's word.
- Gate criteria cannot hang the tick.
- Independent DAG branches can run in parallel (opt-in via `HB_MAX_CONCURRENCY`),
  with the default preserving today's serial reliability.
- Full regression suite green.
