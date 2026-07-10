# PLAN — Plugin improvements (issues #1–#5)

Solve the five improvements surfaced by real use (MeetOS run):
1. **hb-lint advisory warnings** — placeholder/template content + dangling gate artifacts.
2. **Notify hook** — `HB_NOTIFY_CMD` fired on human-needed wakes (unattended runs stop being blind).
3. **Adversarial gate (second agent)** + spec-first convention — close the "grade own homework" hole.
4. **Parallel-when-no-conflict** — `hb ready [N]` surfaces the concurrently-runnable set; `/heartbeat run` + honest driving docs.
5. **dag.json JSON Schema + per-task timing** in the report.

**Governing designs**
- Adversarial gate: HeartBeat owns the *state machine* (per-gate `review` block →
  `review_pending` signal → `hb review pass|fail` event → projector blocks advance
  until review passes). The *second agent* is spawned by the driver (Agent tool,
  refutation prompt). Gates without `review` behave exactly as today (back-compat).
- Parallel: `hb ready [N]` returns eligible, unleased, requires-independent tasks
  (≤ `HB_MAX_CONCURRENCY − in_flight`). Driver fans out worktree-isolated subagents.
- Warnings are advisory (exit 0). Notify is timeout-wrapped + `||true` + fire-once.

**Ratchet:** `bash tests/run-tests.sh` stays green after every phase (currently 69).
**Cascade:** P1 → P2 → P3 → P4 → P5 (P4 riskiest = projector rework; P5 = polish+docs+verify).

---

## Phase 1 — hb-lint advisory warnings (#1)
**Cascade:** entry
**Tasks**
- 1.1 `hb-lint.js` `checkPlaceholders(dag)` — warn on exact template markers
  (`project:"my-project"`, `"Implement feature A/B"`, `"Description of what this task
  produces."`, `output/result.json`, default gate descs).
- 1.2 `hb-lint.js` `checkGateArtifacts(dag)` — extract file/dir paths from each gate
  `cmd`; warn per path not mentioned by any task title/description (skip `$HB_DIR`/.hb).
**Tests** fixtures: placeholder DAG, dangling-artifact DAG, clean DAG.
**Gate G1 (checklist)**
- [ ] template markers → warning; clean DAG → none
- [ ] gate referencing an unproduced file → warning; referenced → none
- [ ] warnings keep exit 0; structural errors still exit 1
- [ ] full suite green
**Report:** warnings added; fixtures.

---

## Phase 2 — Notify hook (#2)
**Cascade:** after P1
**Tasks**
- 2.1 `tick.sh` `notify()` (timeout-wrapped, `||true`) + `HB_NOTIFY_CMD` config; call
  on `build_stuck`/`deadlock`/`all_done` (reuse alert flags = fire once), `gate_blocked`
  and `unsanctioned_drift` (new fire-once flags, cleared on recovery).
**Tests** notify cmd writes to a file; build_stuck → notified once; 2nd tick → not
re-notified; unset → no-op; slow/failing cmd → tick unaffected.
**Gate G2 (checklist)**
- [ ] human-needed wake fires `HB_NOTIFY_CMD` once (not per tick)
- [ ] unset → tick behaves as before
- [ ] failing/slow notify never breaks the tick
- [ ] full suite green
**Report.**

---

## Phase 3 — Parallel-ready surfacing + run docs (#4)
**Cascade:** after P2
**Tasks**
- 3.1 Refactor `hb-next-task.js` → export `resolve()` + `readyTasks(state,dag,hbDir,limit)`.
- 3.2 `hb.js` `ready [N]` → JSON array of eligible unleased tasks (≤ N, ≤ cap−in_flight).
- 3.3 SKILL/README: `/heartbeat run` (serial + parallel-with-worktree), honest cron
  permissions + when parallelism actually applies.
**Tests** 3-independent-task DAG → `ready 3`=3; one leased → 2; dependent task excluded
until dep done; gate-locked phase excluded.
**Gate G3 (checklist)**
- [ ] `ready N` returns ≤N independent ready tasks, excludes leased
- [ ] respects `requires` + gate locks + concurrency cap
- [ ] docs cover serial + parallel(worktree) + cron perms
- [ ] full suite green
**Report.**

---

## Phase 4 — Adversarial gate / second agent (#3)  ★ marquee
**Cascade:** after P3 (riskiest — projector rework)
**Tasks**
- 4.1 DAG: optional per-gate `review` block (`{prompt}`), back-compat.
- 4.2 `hb.js` projector: track per-gate `{det, rev}`; derive `completed_phases`
  requiring review-pass when a gate has `review`; emit `state.pending_reviews`.
  Add `review` command → `review_passed`/`review_failed` events (`review_failed`
  sets `gate.errors=1` and clears det so the gate re-runs).
- 4.3 `hb-next-task.js`: emit `{type:"review_pending",gate}` when tasks done + det
  passed + review required + not yet reviewed.
- 4.4 `tick.sh`: reason `review_pending` (wake). `gate.sh`: on det-pass with a
  `review` block, tell the agent to run the adversarial review.
- 4.5 SKILL/CLAUDE-MD: on `review_pending`, spawn a skeptical sub-agent to REFUTE
  completion, then `hb review <gate> pass|fail`. Document spec-first convention.
**Tests** review-gated phase: done→`gate_pending`→gate.sh(det)→`review_pending`→
`hb review fail`→`gate_blocked`→gate.sh→`review_pending`→`hb review pass`→advanced.
Back-compat: review-less gate advances on deterministic pass (all existing gate tests green).
**Gate G4 (checklist)**
- [ ] review-gated phase does NOT advance on deterministic pass alone
- [ ] `review_pending` surfaced after the deterministic gate passes
- [ ] `hb review fail` → blocked/re-gate; `hb review pass` → advance
- [ ] review-less gates behave exactly as before
- [ ] full suite green
**Report.**

---

## Phase 5 — Schema, report timing, docs, final verify (#5 + close-out)
**Cascade:** after P1–P4
**Tasks**
- 5.1 `plugin/dag.schema.json` + how-to-reference docs.
- 5.2 `hb-report.js`: per-task durations (slowest tasks from events).
- 5.3 Version bump **v1.4.0** (plugin+marketplace), changelog, STATUS.
- 5.4 Regression groups T21–T25; full run + end-to-end.
**Gate G5 (checklist)**
- [ ] schema is valid JSON; template dag conforms (structural check)
- [ ] report shows per-task timing
- [ ] all tests green incl new groups; versions consistent
**Report:** final counts; file inventory; how-to.

---

## Success (overall)
Adversarial second-agent gates and parallel-when-no-conflict are first-class; lint
catches placeholder/dangling-artifact plans; unattended runs notify; DAG has a schema
and richer timing. All back-compat; full regression green.
