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

The `/heartbeat …` verbs below are provided by **this skill** (a Claude Code skill), not a `plugin/commands/` directory — invoking `/heartbeat` loads these instructions; the sub-verbs are interpreted from here.

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
Then tell the user to co-write the DAG with `/heartbeat plan`, then schedule/run.

### `/heartbeat plan <project-dir>`

Convert a written plan (in the conversation, or a file the user names) into a
**lint-clean, audit-clean, review-ready** `<project-dir>/.hb/dag.json`. Apply every rule
below, then gate on `hb-lint` + `hb-audit` + a refutation before proposing.

**Continuation vs fresh.** Read `<project-dir>/.hb/state.json`: if it has completed
phases, **append** new phases with fresh IDs and set the first new phase's
`gate_entry` to the last completed phase's `gate_exit` (never touch/renumber done
phases). Otherwise write a fresh DAG.

**The horizon rule (WHEN to stop planning; continuation above is HOW to resume).**
When the work is discovery — later phases depend on what earlier phases will *learn* —
plan ONLY the phases whose spec is known now, and mark the final planned phase
`"horizon": true`. That marker IS the replan point: when the horizon phase completes, the
tick wakes `replan_pending` instead of `all_done`, and exactly two moves are sanctioned —
replan by append-continuation (above; plan only the NEXT horizon), or end the project as a
recorded decision with `node .hb/hb.js horizon close --reason <why>`. A final task that
records the learning (a findings file a criterion can test) is the recommended
content of the horizon phase. Fabricating detailed phases beyond the horizon is the
planning analogue of a hollow gate — unfalsifiable structure that reads as rigor; `hb-audit`
flags the shape as `speculative_tail` (a warning: ≥ 2 trailing unverified LIVE phases behind
a verified head, naming the cut point), and the refuter should too. Below the horizon the plan stays freely editable (edit or drop
never-started phases; `dag.json` is a hypothesis there); ABOVE it, accepted work changes
only through its own rigor — `regate` for criteria, `detach` for dependency claims — and
an unsanctioned hand-edit of a completed gate's criteria trips the drift tripwire
(doctor problem, failing sweep, `criteria_drift` tick) until a full regate cycle cures
it. Method and proof: [plan-to-the-horizon.md](../../../docs/howto/plan-to-the-horizon.md).

**Rules:**
- Unique task/phase IDs DAG-wide. `requires` sparse (only real deps). **≤ 8 tasks/phase.**
- **Spec-first** — each phase's *first* task authors that phase's gate test spec from
  the gate's checklist, before the implementation tasks. Every file a gate `cmd`
  references must be produced by some task's description (⇒ no dangling-artifact warnings).
- **Behavioral gates** — `criteria[].cmd`: one-line bash, exit 0 = pass, `$PROJECT_DIR`
  available, deterministic, within the gate timeout (60s default; a slow criterion sets its
  own `timeout_s`). Assert behavior (returns 200, row persisted, invariant
  holds), not `test -f`. Prefer running code over grepping a source string: a gate that
  greps `def foo` passes on a hollow stub — instead **import and assert callable/shape**
  (`python3 -c "import m; assert callable(m.foo)"`) or exercise the entrypoint and check
  its output. For depth (a catalogue of gate weaknesses, each a runnable proof), see
  [writing-behavioral-gates.md](../../../docs/howto/writing-behavioral-gates.md).
- **Coverage gates assert the OUTCOME, not a name.** A gate that pipes a test suite to
  `grep Tnn` passes even on a *red* suite (the header prints before the run fails, and the
  pipe hides the exit code). Instead assert the group actually PASSED: `tests/run-tests.sh`
  emits a machine-checkable `GROUPS-PASSED: …` line listing only groups with zero failing
  checks, so gate on `grep -q 'GROUPS-PASSED:.* Tnn '` (trailing space) — or run just that
  test and check its real result.
- **Adversarial review** on sensitive gates — add `"review": { "prompt": "Refute that
  this phase is done: …" }` so a second agent must fail to refute before it advances.
- **Plan-time constraints on every review gate** — give the review explicit targets:
  `"review": { …, "constraints": [{ "id": "P1", "claim": "…", "subjects": ["src/…"],
  "violation": "…" }] }`. Each is requirement-level and falsifiable: `claim` is the property
  the phase promises, `subjects` the files/areas it covers, `violation` the concrete
  observation that would break it. Ids are `P1…Pn` (`G…` is reserved for constraints written
  at review time). They are the review's anchor: written before the work exists, they cannot copy
  a defect from the implementation — the gate-time author, who may have read the code, can. So
  write them on every gate whose review matters. `hb-lint` rejects malformed ones; `hb-audit`
  warns `unconstrained_review` on a review gate without any. The review of such a gate is constraint-first — see
  [constraint-first-review.md](../../../docs/howto/constraint-first-review.md).
- **No hardcoded values/counts** — derive from source/registry. Validate the shape
  against the plugin's `${CLAUDE_PLUGIN_ROOT}/dag.schema.json` (bootstrap does not copy it into `.hb/`).

**Acceptance (run and show before proposing):**
```bash
node <project-dir>/.hb/hb-lint.js  <project-dir>/.hb/dag.json   # structure: 0 errors (0 NEW dangling)
node <project-dir>/.hb/hb-audit.js <project-dir>/.hb/dag.json   # gate quality: 0 hollow gates
node <project-dir>/.hb/hb-viz.js   <project-dir>/.hb            # renders the cascade → dag-view.html
```
Then **refute the plan** before proposing: spawn a skeptical reviewer (Agent tool) — or,
in the Python port, `hb audit --agent` — told to prove the DAG *won't* truly verify the
work (gates that assert the wrong behaviour, phases with no real coverage, missing
`requires`). Fold its concerns back into the DAG. **The plan refutation itself stays on
the strong (session) model — it is critical design reading.**

**Replan is a refutation outcome.** When an UNSOUND's findings refute the **plan** (a
premise died, a dependency claim is false, the next phases were fabricated beyond the
horizon) rather than a phase's execution, the resolution is to REPLAN through sanctioned
surface: append or edit **unstarted** phases freely, `detach` the falsified dependency
claim, `regate` a gate whose premises died — and NEVER weaken a gate, constraint, or
review to fit the old plan (strengthening is also a revision: it goes through the same
regate cycle). See [plan-to-the-horizon.md](../../../docs/howto/plan-to-the-horizon.md).

Then **propose the refuter tiering** for the run ahead — the economics are declared once,
per lens, at plan time: list the profiles the gates' `review.profile`s name
(`node .hb/hb.js refuters` / `ls .hb/refuters/`), and for gate-checklist lenses
(correctness/security-style reviews of built work) propose binding a **cheaper model** —
`"model": "<a cheaper model your harness understands>"` in `.hb/refuters/<name>.json` — while
leaving `default` unbound so plan-level and whole-feature reviews inherit the session model. For
constraint-first gates, also propose `author_model` (the strongest model available — the author's
constraints are what the review is held to), and for security gates `"free_review": true` with a
`free_model` different from the refuter's. Model names are free-form strings passed through
verbatim; an unset field means the session's / backend's default. Write the agreed bindings
into the profile files as part of sign-off; the `review_pending` flow then routes and
records automatically (`refute-prompt --json` → spawn → `review … --model`). Never propose
a downgrade to make passes cheaper to obtain, and point the user at the per-model impact in
`hb report` as the check that the cheap lens still catches — the full argument and honest
limits are in [tier-the-refuter.md](../../../docs/howto/tier-the-refuter.md).

Only propose once **lint + audit are clean AND the refuter comes back SOUND**. Present the
phases/gates + the lint/audit/viz results + the refutation verdict + the proposed refuter
tiering, then get sign-off before running.

### `/heartbeat status <project-dir>`
```bash
node <project-dir>/.hb/hb-report.js <project-dir>/.hb
```
Also read `<project-dir>/.hb/state.json` for current phase and task counts. The report ends with a
**Refuter impact** section — what refutation actually caught this run (catches vs clears per gate, with
the `review.profile` lens), so you can tell whether refutation earned its keep or found nothing.

### `/heartbeat doctor <project-dir>`
Static integrity check — the key one is **rot detection**: a *completed* phase whose
gate references a file that no longer exists (that gate can't be reproduced). Also
flags DAG errors, state/log drift, and stale leases. Read-only.
```bash
node <project-dir>/.hb/hb.js doctor
```
To behaviourally **re-verify** that gates still pass (read-only, no state change):
```bash
bash <project-dir>/.hb/gate.sh --check <GATE>   # one gate
bash <project-dir>/.hb/gate.sh --all            # every ever-passed gate (regression check; planned gates skipped, reported)
```

### `/heartbeat lint <project-dir>`
```bash
node <project-dir>/.hb/hb-lint.js <project-dir>/.hb/dag.json
```
Reports duplicate IDs (tasks and phases), cycles, broken `requires`, undefined gates,
phases > 8 tasks, and malformed criteria (every entry must be an object with a string `cmd`).

### `/heartbeat audit <project-dir>` — adversarial DAG review

Where `lint` checks **structure**, `audit` checks **gate quality** — the thing that
actually bounds HeartBeat's value. It applies refute-don't-confirm to the *plan* before
you spend a token running it: a hollow gate (`test -f`, `true`) makes the whole
verification apparatus theatre.
```bash
node <project-dir>/.hb/hb-audit.js <project-dir>/.hb/dag.json    # exit 1 if any hollow gate
```
Flags: **hollow_gate** (a phase whose gate has no behavioral criterion), **ungated**,
**unguarded_phase**, existence-only / vacuous criteria, **nondeterministic** gates
(network/time → flaky), **side_effecting** (a gate that writes/creates files can fabricate
its own evidence — observe, don't produce), **gate_offphase** (the gate tests nothing
the phase produces), **unconstrained_review** (a review gate without plan-time
`review.constraints`), **control_char** (a `\x1e`/`\x1f` byte that would corrupt the gate
runner's transport), and **speculative_tail** (a warning: two or more trailing unverified LIVE phases, parked ones
excluded, behind a verified head — planned past the knowledge horizon; it names where to cut and mark
`"horizon": true`).

**Adversarial layer (agent).** The static rules catch *structural* weakness; a second
*read* catches semantic gaps — a gate that asserts the **wrong** behaviour, a phase whose
gate doesn't exercise the task's real requirement. After the deterministic audit, spawn a
skeptical reviewer (Agent tool) with a prompt like:

> You are refuting a HeartBeat DAG. For each phase, decide whether its gate would truly
> prove the task's real requirement — or whether the phase could pass with the work still
> broken. Flag: gates that test the wrong behaviour, phases with no real coverage, missing
> `requires`, criteria that pass trivially. End with SOUND or UNSOUND.

Fix what it raises before running. The **Python port automates this**: `hb audit --agent`
runs the deterministic audit and then dispatches the refutation to a configured backend
(`hb audit --agent --dir <project>`), exiting non-zero if the reviewer refutes the plan.

### `/heartbeat viz <project-dir>`
```bash
node <project-dir>/.hb/hb-viz.js <project-dir>/.hb              # snapshot → dag-view.html
node <project-dir>/.hb/hb-viz.js <project-dir>/.hb --serve [--port N]   # live dashboard
```
Two modes. **Snapshot** (default) writes `<project-dir>/.hb/dag-view.html` — self-contained,
no external deps, but a point-in-time view (regenerate to refresh). **Live** (`--serve`) runs a
loopback-only HTTP server that re-reads `dag.json`+`state.json` fresh on every request, so the
view always reflects current execution state with no regenerate — prints the URL (`--port 0`
for an ephemeral port). It binds `127.0.0.1` only and validates the `Origin` header
(DNS-rebinding); a non-loopback bind is refused unless you pass `--allow-remote`.

### `/heartbeat tick <project-dir>`
Run a manual Stage A tick:
```bash
bash <project-dir>/.hb/tick.sh
```
Returns `{ wakeAgent, data }`. If `wakeAgent: true`, act on `data.reason` per the
Tick Protocol below.

### `/heartbeat run <project-dir>` — drive the loop

**Serial (default):** repeatedly `bash .hb/tick.sh` → act on `data.reason` → repeat,
stopping only at a wake that needs a human (`gate_blocked`, `build_stuck`, `deadlock`,
`review_stuck`, `unsanctioned_drift`, `criteria_drift`, `gate_rot`, `replan_pending`, or a
`review_pending` you can't clear) or `all_done`. Equivalent to `/loop 15m /heartbeat tick <dir>`
but self-paced.

**Parallel (independent branches):** ask HeartBeat for the concurrently-runnable set
and fan it out as **worktree-isolated** sub-agents so file writes never collide:
```bash
node <project-dir>/.hb/hb.js ready 4        # up to 4 eligible, unleased, independent tasks
```
For each returned task, spawn a sub-agent (Agent tool, `isolation:"worktree"`) that
does the task and calls `hb start`/`hb done` under its own lease. The atomic lease
guarantees no task is claimed twice. Repeat `hb ready` until empty, then gate.
**Conflict rule:** `ready` only knows `requires` — if two ready tasks touch the same
files, either run them worktree-isolated (recommended) or add a `requires` edge.

### `/heartbeat exec <project-dir>` — drive the loop with a pluggable backend

Same serial loop as `/heartbeat run`, but Stage B is a **pluggable backend** instead
of this session — so an unattended process can do the work. HeartBeat stays the
deterministic brain (the tick decides what/when, the gates verify); the driver
dispatches each task to a backend agent over a tiny JSON wire protocol and mediates
every state transition itself.

```bash
node <project-dir>/.hb/hb-exec.js run       # loop until all_done or a human is needed
node <project-dir>/.hb/hb-exec.js config    # show the resolved backend config
```

**Backends** (`.hb/executor.json` `{ "backend": … }`, or `HB_EXEC_BACKEND`):
`claude-code` (headless `claude -p`, default), `agno`, `crewai`, `langgraph`,
`openai-agents`, `autogen`, `smolagents`, `pydantic-ai`, `ollama` (local models —
`HB_EXEC_MODEL`, stdlib-only), or a raw `script` (`HB_EXEC_CMD="<cmd>"`). Each backend
is a small adapter under `.hb/executors/` speaking the same protocol:
```
driver → backend:  argv[last] = execute|refute, stdin = payload JSON
backend → driver:  execute → {"ok":bool,"summary":str}   refute → {"refuted":bool,"findings":str}
```
`agno`/`crewai` wrap a real tool-using agent (they write files with native tools);
set `HB_EXEC_PROVIDER=ollama` to drive them with **local models, no API key**, or
`=anthropic` (needs `ANTHROPIC_API_KEY`). All three model backends are proven
end-to-end against local Ollama (`tests/real-backend.sh <backend>`).

The backend never touches `state.json` or `gate.sh`. The driver runs the gate,
pumps the task's lease heartbeat while the backend works, and — by policy —
**escalates (never auto-fixes) when a gate blocks**. In **strict** mode
(`HB_EXEC_STRICT=1`) it refuses to run a phase whose gate is non-behavioral (e.g.
`test -f`) or whose DAG still has `hb-lint` warnings — because autonomy makes weak
gates dangerous. Serial (one task at a time); `HB_EXEC_ATTEMPT_CAP` (default 3)
bounds retries per task. Write a real backend by implementing those two modes; the
shipped adapters (`.hb/executors/agno_exec.py`, `crewai_exec.py`, `claude-exec.sh`)
are the templates.

### `/heartbeat schedule <project-dir>`
Drive ticks autonomously on Claude Code using a **`/schedule` routine** (cron).
Present this ready-to-use routine to the user (replacing `<project-dir>`, `<slug>`,
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
  review_pending, gate_blocked, at_capacity, state_corrupted, dag_corrupted,
  deadlock, unsanctioned_drift, criteria_drift, gate_rot, build_stuck,
  review_stuck, replan_pending, all_done). Update .hb/state.json atomically (tmp + rename) and
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
*HeartBeat — commands:*
• /heartbeat init <dir>     — bootstrap a new project
• /heartbeat plan <dir>     — convert a plan into a lint-clean dag.json
• /heartbeat status <dir>   — progress report
• /heartbeat lint <dir>     — validate the DAG (structure)
• /heartbeat audit <dir>    — adversarial gate-quality review (hollow gates)
• /heartbeat doctor <dir>   — integrity check (rot: gates referencing deleted files)
• /heartbeat viz <dir>      — generate dag-view.html
• /heartbeat tick <dir>     — manual tick (one task)
• /heartbeat run <dir>      — drive the loop (serial, or parallel via hb ready)
• /heartbeat exec <dir>     — drive the loop with a pluggable backend (agno/crewai/claude-code)
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
node .hb/hb.js ready [N]           # the concurrently-runnable set (parallel drivers)
node .hb/hb.js review <gate> pass|fail [note]   # record the adversarial verdict
node .hb/hb.js doctor              # integrity check (deleted gate files, drift, stale leases)
node .hb/hb.js diagnose [reason]   # computed root-cause + recovery steps for a blocked state
node .hb/hb.js protocol [reason]   # the reason→action table (single source of truth)
node .hb/hb.js rebuild             # reproject state.json from the log (sync / recover)
node .hb/hb.js state               # print current projected state
```

**Self-describing ticks (v1.7).** Every wake already carries the exact next action
in `data.action` — you rarely need this table; act on what the tick tells you. When
blocked, `node .hb/hb.js diagnose` computes the root cause (which criteria fail, which
commit deleted a gate's file, the deadlock cause) and the recovery steps. The full
protocol also lives in `.hb/PROTOCOL.md`, versioned with the project.

**Long-running tasks:** call `node .hb/hb.js heartbeat <id>` at least every
`HEARTBEAT_STALE_S` (default 180s) — e.g. between sub-steps. A heartbeated lease
that goes silent is reclaimed fast (hung agent); a lease that never heartbeats
falls back to the slower `LOCK_STALE_S` deadline.

When woken by a tick (`data.reason` present), act by reason:

| `data.reason` | Action |
|---|---|
| `next_task` | `node .hb/hb.js start <id>` → do the work → `node .hb/hb.js done <id>` (or `fail <id>` if you couldn't complete it). No hand-edited JSON. |
| `gate_pending` | `bash .hb/gate.sh <data.next_task.gate>`. A pass advances the phase — UNLESS the gate has a `review` block, in which case an adversarial review is owed (next). |
| `review_pending` | The deterministic gate passed. **Constraint-first gate** (its review has plan-time `constraints`): first get the gate-time constraints — `node .hb/hb.js constraints <gate> --prompt` (its `--json` `.model` is the profile's `author_model`), hand it to an agent that did NOT do the phase's work, save its JSON array (each constraint must name at least one file this phase changed — from the change list in the prompt — or a directory holding one, or the record is refused) and `HB_ACTOR=<author> node .hb/hb.js constraints <gate> --record <file.json>`; the refute prompt then lists every id and the answer format, and the refuter must answer each id on its own line (`<ID>: VIOLATED \| NOT-REPRODUCED \| N/A — <evidence or reason>`); when the profile sets `free_review`, also run `refute-prompt <gate> --free` with another agent (its `free_model`) and record `node .hb/hb.js review <gate> free --artifact <file>` under that agent's identity — see [constraint-first-review.md](../../../docs/howto/constraint-first-review.md). For every gate: now **spawn a second, skeptical agent** (your harness's sub-agent tool — the Agent tool in Claude Code) told to *refute* that the phase is truly complete — hollow tests, criteria not really met, faked outputs. **Seed that agent with `node .hb/hb.js refute-prompt <gate>`** — the SAME compose the automated path uses, so an interactive refutation honors the gate's `review.profile` (persona + the falsification checklist + the profile's extra questions); with no profile it is the gate's own prompt plus the HOLES line it asks for. **Spawn the refuter ON the profile's model**: read `node .hb/hb.js refute-prompt <gate> --json` and pass its `.model` to your harness's sub-agent model setting (the Agent tool's model parameter in Claude Code) (inherit the session model only when null) — a checklist refutation rarely needs the most expensive model, and the profile is where that economy is declared. **Write its attempt to a findings file**, then `node .hb/hb.js review <gate> fail "<holes>" --model <that model>` (found holes → `gate_blocked`) or `node .hb/hb.js review <gate> pass --artifact <file> --model <that model>` (couldn't refute) — **record `--model` with the verdict** so the log carries what actually reviewed and the per-model impact report has truth to count. A pass **requires** a substantive artifact that cites the phase and comes from a different actor than the doer — no rubber-stamps. Without per-id answers (an unconstrained gate, or the free review) the artifact must also carry a line `HOLES: none`; a HOLES line that lists anything is refused — a hole is a finding, recorded with `review <gate> fail`. |
| `gate_blocked` | `node .hb/hb.js diagnose` → shows which criteria fail + attempts; fix the ROOT cause (never weaken the gate), re-run `bash .hb/gate.sh <gate>`. |
| `at_capacity` | Nothing to do — max tasks already in flight (or the only ready task is leased). The tick handled it; no wake. |
| `state_corrupted` | `node .hb/hb.js rebuild` (replays events.jsonl). The tick self-heals this; only surfaces if the log itself is unusable. |
| `dag_corrupted` | Restore dag.json from git/backup (structure is immutable). |
| `deadlock` | `active_orphan` → the stale-lease reclaim frees it automatically; if it persists, `hb fail <id>`. `dag_invalid` → surface errors for human review. |
| `unsanctioned_drift` | Review the diff. If intended: `bash .hb/tick.sh --freeze`. |
| `criteria_drift` | A completed gate's criteria changed without sanction — `node .hb/hb.js doctor` names the gate. HUMAN NEEDED; never freeze or edit past it. The cure is a full regate cycle: git-restore dag.json to retract the content, or declare the revision (`node .hb/hb.js regate <gate> <reason>`), a DIFFERENT actor rearms with evidence (`node .hb/hb.js regate <gate> --rearm --artifact <file>`), then a fresh pass (`bash .hb/gate.sh <gate>`). |
| `gate_rot` | `node .hb/hb.js diagnose` names the missing file AND the commit that deleted it — restore it or re-point the gate. |
| `build_stuck` | `signal: no_progress` means the agent was woken repeatedly without progressing. Produce a blocker report for human review. |
| `review_stuck` | An adversarial review never resolved — spawn the refuter and record `hb review <gate> pass\|fail`, or surface for human review. |
| `replan_pending` | The plan reached its knowledge horizon — its flagged last phase is complete. HUMAN NEEDED: a replan decision is owed, never a silent finish. Exactly two sanctioned moves: replan by append-continuation (append the NEXT horizon's phases to dag.json with fresh ids, the first new `gate_entry` = the completed horizon phase's `gate_exit`, plan only what is now known and flag the new last phase `horizon: true`; lint + audit + refute, then tick), or end the project as a recorded decision: `node .hb/hb.js horizon close --reason <why>`. |
| `all_done` | Write the final project report. |

**End of session:** finish each claimed task with `hb done`/`hb fail` — that frees
its lease. The tick's handout lock is released automatically (no more `rm -rf .lock`).
A crashed session's lease is reclaimed after `LOCK_STALE_S`.

**Parallelism:** set `HB_MAX_CONCURRENCY > 1` (env) to run independent DAG branches
concurrently — overlapping ticks hand out distinct ready tasks up to the cap.
Default `1` keeps the classic one-task-at-a-time behavior. For explicit fan-out use
`node .hb/hb.js ready N` and spawn worktree-isolated sub-agents.

**Adversarial gates & spec-first.** Gates are only as honest as the tests the
implementer wrote — the same agent can grade its own homework. Two mitigations:
- **Spec-first**: make each phase's *first* task author its gate's test spec from
  the success checklist, *before* the implementation tasks.
- **Adversarial review**: add a `review` block to a gate in `dag.json`:
  ```json
  "GATE_P3": { "desc": "...", "review": { "prompt": "Refute that P3 is done: hollow tests? criteria not really met? faked output?" }, "criteria": [ … ] }
  ```
  A review-gated phase advances only after BOTH the deterministic gate passes AND a
  **second agent** (spawned on `review_pending`) fails to refute it (`hb review pass`).

**Version control (automatic).** Bootstrap runs `git init` (unless `--no-git` /
`HB_NO_GIT=1`) and every gate pass commits the working tree and force-tags the gate
id — so each phase is a restore point:
```bash
git reset --hard GATE_P3      # roll the project back to when P3's gate last passed
```
Disable auto-commit with `HB_GIT_AUTOCOMMIT=0`. Commits use a fallback identity, so
they work even if git user isn't configured.

---

## Reference
- Bootstrap: `${CLAUDE_PLUGIN_ROOT}/bootstrap.sh`
- Templates: `${CLAUDE_PLUGIN_ROOT}/templates/`
- Full guide, install docs, and the regression suite live in the HeartBeat
  repository (README.md, INSTALL.md, tests/run-tests.sh).
