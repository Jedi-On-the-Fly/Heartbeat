# HeartBeat — verified autonomous agent runs

**HeartBeat is a proof-driven method for running autonomous agents: work is accepted only when its claims are backed by executable evidence that survives a deliberate attempt to refute it.** Lifecycle: **claim → build → prove it works → refute the proof → accept only if it holds.**

> Autonomous agents are driven by large language models, and every step an agent takes calls that model, which costs money. HeartBeat drives a run with a cheap check (**Stage A**, plain bash or Python) that reads the settled state of the work and wakes the expensive model (**Stage B**) only when there's real work to do. That check is the **pulse**. It runs whenever something asks for it (an executor loop, an MCP call, or a timer) and returns one decision: sleep, or wake the model with a reason and the exact next action. When the model returns, HeartBeat verifies the result at a gate instead of trusting it.

**Developer docs (source of truth):** [dev-plugin.md](docs/dev-plugin.md) · [dev-python.md](docs/dev-python.md) · [dev-tests.md](docs/dev-tests.md). Vocabulary: [vocabulary.md](docs/vocabulary.md). Concept: [heartbeat.md](docs/heartbeat.md) · [heartbeat-py.md](docs/heartbeat-py.md). Architecture: [adapters.md](docs/adapters.md) (making the method **code- and docs-aware**: two shipped domain adapters, in **both runtimes** (node ≡ python), without giving up its generality). How-to guides (runnable): [docs/howto/](docs/howto/).

HeartBeat lets an agent drive a long, multi-phase project autonomously without supervision, without losing the thread, and without burning tokens idling. The project is laid out as a map of work: phases break into tasks, each task points to what it depends on, and quality gates guard the steps between them. Developers know this structure as a **DAG** (directed acyclic graph): work that always flows forward, never in circles.

```
the pulse  (bash .hb/tick.sh · hb pulse)    ← Stage A: plain bash or Python, ~0 tokens
  │
  ├─ nothing to do → sleep
  └─ real work     → the model is invoked   ← Stage B: only when needed
```

Three things keep a multi-hour run honest. **State is computed, not remembered:** `events.jsonl` (the event log) is the append-only source of truth and the audit trail, and `state.json` is a projection of it, so a crashed session is rebuilt from the log and continues. **Progress is verified, not trusted:** a phase advances only when its *behavioral* gate passes (does the thing *work*, not does a file *exist*), and sensitive gates add a second agent told to *refute* completion rather than confirm it. And **behavior is a contract:** the same DAG and protocol run on two runtimes (a node+bash plugin and a pure-Python port) held to identical results.

## What it verifies — and where it stops

HeartBeat's guarantees are real but bounded, and it states the boundary at each one rather than
overclaiming:

- **Gates prove behavior, not correctness in the abstract.** A gate proves *the assertion you wrote*
  passes; write the wrong assertion and it proves the wrong thing. The auditor (`hb-audit`) and the
  refutation exist to attack that — but the ceiling is the criteria you author.
- **Grounding is not truth.** The research adapter's `ground-check` proves a quote is really in a stored
  source; whether the source is right, primary, or in context is the adversarial review's job, not the
  gate's — see [ground-research-claims.md](docs/howto/ground-research-claims.md).
- **The refuter is a dial, not a guarantee.** A "distinct actor" is enforced by identity; a distinct
  *capability* — a genuinely different model with different blind spots — is opt-in, see
  [cross-model-verification.md](docs/howto/cross-model-verification.md).
- **Doc-gating covers the how-tos, the adapter reference** ([adapters.md](docs/adapters.md)), **and the
  root claim-docs** (this file, SECURITY, INSTALL, …) — but not yet every reference-doc *list* (e.g. the
  dev-doc tables aren't verified against source).
- **A `dag.json` / executor is trusted input** — running one is equivalent to running a shell script.
  See [SECURITY.md](SECURITY.md).

## Install on Claude Code

HeartBeat installs as a **Claude Code plugin** (recommended) or via a **fallback
script**. Full details: [`INSTALL.md`](INSTALL.md).

```
# Plugin (nothing is published — local marketplace)
/plugin marketplace add <path-to-this-folder>
/plugin install heartbeat

# — or — fallback script
bash scripts/install.sh
```

Then `/heartbeat help`.



## Quick start

```
/heartbeat init <project-dir>      # scaffold .hb/ (+ git init, restore points)
/heartbeat plan <project-dir>      # convert a written plan into a lint-clean dag.json
/heartbeat lint <project-dir>      # validate the DAG
/heartbeat viz <project-dir>       # dag-view.html (add --serve for a live, always-current view)
/heartbeat pulse <project-dir>     # take one pulse: one decision, one action
/heartbeat run <project-dir>       # drive it: pulse → act → pulse, until done or a human is needed
/loop 15m /heartbeat pulse <dir>   # or drive it on a timer, unattended
```



## Layout after bootstrap

```
my-project/
└── .hb/
    ├── tick.sh            ← Stage A: priority checks, outputs { wakeAgent, data }
    ├── gate.sh            ← gate runner: bash gate.sh GATE_P0  (+ --check / --all)
    ├── hb.js              ← state CLI: start/done/fail/heartbeat/ready/review/doctor/rebuild/state/import
    ├── hb-next-task.js    ← gate-aware resolver (deadlock/rot diagnostics)
    ├── hb-lint.js         ← static DAG validation
    ├── hb-report.js       ← progress report (text / --json)
    ├── hb-viz.js          ← self-contained dag-view.html
    ├── dag.json           ← YOUR PROJECT: phases, tasks, dependencies, gate criteria
    ├── state.json         ← runtime state (a projection of events.jsonl)
    ├── events.jsonl       ← append-only event log (the source of truth)
    └── leases/            ← per-task session claims
```



## dag.json structure

```json
{
  "gates": {
    "GATE_P0": {
      "desc": "Human-readable description",
      "review": { "prompt": "Refute that this phase is done: …" },
      "criteria": [
        { "id": "G0_1", "desc": "What this criterion checks",
          "cmd": "one-line bash that exits 0 if OK" }
      ]
    }
  },
  "phases": [
    {
      "id": "P0", "title": "Phase name", "desc": "What this phase produces",
      "gate_entry": null, "gate_exit": "GATE_P0",
      "tasks": [
        { "id": "P0T1", "title": "Task", "description": "What the agent must do", "requires": [] },
        { "id": "P0T2", "title": "Second task", "description": "...", "requires": ["P0T1"] }
      ]
    }
  ]
}
```

**Rules:**
- Task IDs are unique across the whole DAG. `requires` = task IDs that must be
  `done` before this task is eligible. Keep it **sparse** (only real dependencies).
- **`gate_entry` is enforced by the resolver:** no task of a phase is served until
  the phase carrying the matching `gate_exit` is in `completed_phases`. Gates are
  not bypassable.
- Gate `cmd`s run under `timeout` with `$PROJECT_DIR` and `$HB_DIR` available. Keep
  them deterministic, one line, fast (<5s). **dag.json is trusted input** (criteria
  are eval'd).
- **Behavioral gates, not structural:** `test -f output.js` breaks on rename;
  `node -e "require('./output')"` survives. Assert behavior, not file layout.
- **`review` block (optional):** adds an adversarial second-agent gate — the phase
  advances only after the deterministic gate passes AND a skeptical agent fails to
  refute completion. See below.
- **Schema:** validate against [`plugin/dag.schema.json`](plugin/dag.schema.json).

Author a DAG from a written plan with `/heartbeat plan` — it enforces spec-first
tasks, behavioral gates, adversarial review on sensitive gates, and lints clean.



## Stage A — the pulse (`tick.sh`): priority checks

```
1. Handout lock     atomic mkdir; serializes concurrent pulses (released before Stage B)
2. Integrity        corrupt state.json → self-heal via rebuild; corrupt dag.json → wake dag_corrupted
2.5 Lease reclaim   a stale/hung lease (heartbeat gone) is reclaimed → task returns to pending
2.6 Rot             a COMPLETED phase's gate references a deleted file → wake gate_rot
3. Circuit breaker  build_stuck_count ≥ 5, or objective no-progress → wake build_stuck (single alert)
4. Drift            SHA256 of WATCH_PATHS; unsanctioned change → wake unsanctioned_drift
5. Gate errors      a previously failed gate → wake gate_blocked
6. Next task        eligible task → wake next_task; tasks done but gate unpassed → gate_pending;
                    deterministic gate passed, review owed → review_pending; project done → all_done;
                    nothing actionable on an unfinished project → deadlock (with diagnostic)
```

Output is always `{ "wakeAgent": true|false, "data": { "reason": "...", ... } }`.



## Stage B — the pulse protocol

When woken (`data.reason` present), the agent acts by reason. **Never hand-edit
`state.json`** — it is a projection of `events.jsonl`. Mutate state only through the
`hb` CLI:

```bash
node .hb/hb.js start <id>          # claim the task (lease) + mark active
node .hb/hb.js done  <id>          # completed → frees the lease, resets stuck count
node .hb/hb.js fail  <id>          # failed    → frees the lease, bumps stuck count
node .hb/hb.js keepalive <id>      # long task: refresh the lease so it isn't reclaimed (legacy: heartbeat)
node .hb/hb.js ready [N]           # the concurrently-runnable set (parallel drivers)
node .hb/hb.js review <gate> pass|fail [note]   # record the adversarial verdict
node .hb/hb.js doctor              # integrity check (rot / drift / stale leases)
node .hb/hb.js diagnose [reason]   # computed root-cause + recovery for a blocked state
node .hb/hb.js protocol [reason]   # the reason→action table (single source of truth)
node .hb/hb.js rebuild             # reproject state.json from the log (sync / recover)
node .hb/hb.js state               # print the projected state
```

**Self-describing pulses:** every wake carries the exact next action in
`data.action`, so any driver knows what to do from the JSON alone. The protocol is
one source of truth (`hb protocol`), rendered to `.hb/PROTOCOL.md` at bootstrap and
embedded in pulses. When blocked, `hb diagnose` computes the root cause (failing
criteria, the commit that deleted a gate's file, the deadlock cause) and recovery
steps — you are never left guessing.

| `data.reason` | Action |
|---|---|
| `next_task` | `hb start <id>` → do the work → `hb done <id>` (or `hb fail <id>`). |
| `gate_pending` | `bash .hb/gate.sh <gate>`. A pass advances the phase — unless the gate has a `review` block (→ `review_pending`). |
| `review_pending` | Spawn a skeptical second agent to **refute** completion, then `hb review <gate> pass\|fail`. Only a pass advances. |
| `gate_blocked` | Fix the failing criteria/findings, re-run the gate. |
| `at_capacity` | Nothing to do — max tasks in flight (or the only ready task is leased). |
| `state_corrupted` | `hb rebuild` (the pulse self-heals; surfaces only if the log is unusable). |
| `dag_corrupted` | Restore dag.json from git/backup (structure is immutable). |
| `deadlock` | `active_orphan` → reclaimed automatically. `dag_invalid` → surface for human review. |
| `unsanctioned_drift` | Review the diff. If intended: `bash .hb/tick.sh --freeze`. |
| `gate_rot` | A completed phase's gate references a deleted file — run `hb doctor`, fix or re-point the gate. |
| `build_stuck` | Woken repeatedly without progress. Produce a blocker report. |
| `review_stuck` | An adversarial review never resolved — run the refuter, then `hb review`. |
| `all_done` | Write the final project report. |

**End of session:** finish each claimed task with `hb done`/`hb fail`. The handout
lock releases automatically; a crashed session's lease is reclaimed after
`HEARTBEAT_STALE_S` (or `LOCK_STALE_S` if it never sent a keepalive).



## Adversarial gates (the second agent)

A gate can carry a `review` block. Then, after the deterministic gate passes, the
pulse emits `review_pending` and the phase does **not** advance until a second,
skeptical agent — told to *refute* completion, not confirm it — fails to find holes:

```json
"GATE_P3": {
  "desc": "...",
  "review": { "prompt": "Refute that P3 is done: hollow tests? criteria not really met? faked output?" },
  "criteria": [ … ]
}
```

Refutation beats confirmation: a confirmer looks for reasons to say yes (and an LLM
is very good at generating those); a refuter looks for the one reason to say no.
This is the primary defense against an agent grading its own homework. Combine it
with **spec-first** tasks (each phase's first task authors its gate's test spec from
the checklist, before the implementation tasks).



## Parallel execution

`hb ready N` returns the eligible, unleased, requires-independent tasks. A parallel
driver fans them out as **worktree-isolated** sub-agents so simultaneous writes
can't collide; each does `hb start`/`hb done` under its own lease (atomic — no task
is claimed twice). Parallelism only applies within a phase (gates serialize
phases), and works best on file-disjoint slices — foundation phases are usually
better serial. `HB_MAX_CONCURRENCY` caps the pulse's serial handout (default 1).



## Gate integrity & liveness

Gates have both **safety** (a phase can't advance until its criteria pass) and
**liveness** (no gate-related state silently persists as wrong):

- **`hb doctor`** — static integrity check. Headline: *rot detection* — a completed
  phase whose gate references a now-deleted file (that gate can no longer be
  reproduced). Also flags DAG errors, state/log drift, stale leases. Read-only.
- **Re-verifiable gates** — `bash .hb/gate.sh --check <GATE>` re-runs one gate's
  criteria read-only (no state change); `bash .hb/gate.sh --all` re-verifies every
  gate (a regression check). A passed gate keeps acting as a gate.
- **Automatic rot detection** — every pulse runs `doctor` and wakes
  `gate_rot` on rot; a **pre-commit hook** blocks a commit that deletes a file a
  completed gate depends on (bypass: `git commit --no-verify` / `HB_NO_HOOK=1`).
- **Review liveness** — an adversarial review that never resolves is caught by the
  no-progress breaker and escalated as `review_stuck`.



## Version control

Bootstrap runs `git init` (unless `--no-git` / `HB_NO_GIT=1`). Every gate pass
commits the working tree and force-tags the gate id, so each phase is a restore
point:

```bash
git reset --hard GATE_P3      # roll the project back to when P3's gate last passed
```

Commits use a fallback identity, so they work even if git user isn't configured.
Disable auto-commit with `HB_GIT_AUTOCOMMIT=0`.



## Config (environment variables)

| Variable | Default | Purpose |
|---|---|---|
| `LOCK_STALE_S` | 1800 | Handout lock / lease without keepalives / write-lock staleness |
| `HEARTBEAT_STALE_S` | 180 | Silence tolerated on a lease with keepalives before reclaim |
| `STUCK_TICKS` | 3 | No-progress wakes (task or review) before escalation |
| `HB_MAX_CONCURRENCY` | 1 | Tasks in flight at once (leases) |
| `GATE_TIMEOUT_S` | 5 | Per-criterion gate timeout |
| `HB_NOTIFY_CMD` | (empty) | Command run on human-needed wakes: `"<reason>" "<project>" "<detail>"` |
| `HB_ROT_CHECK` | 1 | Per-pulse rot detection (0 to disable) |
| `HB_NO_GIT` | (empty) | Disable git init + commit-on-gate-pass + hook |
| `HB_GIT_AUTOCOMMIT` | 1 | 0 disables the commit on gate pass |



## Driving it

A pulse runs whenever something asks for one. Three drivers, in order of preference:

1. **The executor** — `/heartbeat run <dir>`, `hb exec run`, or `node .hb/hb-exec.js run`:
   pulse → act → pulse, back to back, until the project is done or a human is needed. No timer.
2. **An MCP client** — an agent takes a pulse (the MCP `tick` tool) whenever it wants its next
   action; see [Drive HeartBeat over MCP](#drive-heartbeat-over-mcp).
3. **A timer**, for unattended runs while nothing else is driving:
   a **`/schedule` routine** (`/heartbeat schedule <dir>` — cron in the cloud, clones a GitHub repo,
   so it fits when the project is a git repo), **in-session** `/loop 20m /heartbeat pulse <dir>`, or
   **system cron** `*/20 * * * * cd <dir> && claude -p "run bash .hb/tick.sh and act on data.reason per the pulse protocol"`.



## Domain adapters

The method is domain-agnostic; a **domain adapter** makes it smart about *your* domain
without changing the core. An adapter plugs into two **seams** over one small `codemap`
contract (`{ edges, tasks }`): **plan authoring** — dep-lint a DAG's `requires` against a
real dependency graph (the hardest authoring problem) — and **context assembly** — feed
Stage B the exact slice a task needs, through the executor's generic `context_cmd` hook.

Two adapters ship, in **both runtimes** (node ≡ python: byte-equal dep-lint + context,
set-equal maps — so the capability is native to the Python/framework path and runs with
**zero Node**):

- **code** — a CodeGraph symbol graph → correct sparse `requires`, and a task's code subgraph as context.
- **docs/research** — a markdown citation graph → the same, for a docs-authoring DAG.

Adapters are **advisory** (report, never rewrite your DAG), live under `plugin/adapters/`
(+ `py/src/heartbeat/adapters/`), are **not** scaffolded into any `.hb/`, and import nothing
from core — the suites stay green without them. Each ships a skill so you never touch the raw
commands, enforced by a skill-integrity gate. Build one:
[build-a-domain-adapter.md](docs/howto/build-a-domain-adapter.md); architecture:
[adapters.md](docs/adapters.md).



## Drive HeartBeat over MCP

Besides driving agents, HeartBeat *is* an MCP server: `hb mcp-serve` (Python port)
exposes its pulse (`tick`) / gate / state tools over the Model Context Protocol — plus the code
adapter's `deplint`, `code_context`, and `code_discover` (change-impact) — so an MCP client — **Codex, Claude Code, or
OpenCode** — can drive HeartBeat mid-session (ask what's next, do the work, call the gate
to verify) and get code-aware planning/context in-session, node-free. It is stdlib-only and
dual-stacks the classic handshake and the 2026-07-28 revision. See
[drive-heartbeat-over-mcp.md](docs/howto/drive-heartbeat-over-mcp.md) and the
[security note](docs/howto/secure-the-mcp-server.md).



## Tests

```bash
bash tests/run-tests.sh      # full regression suite (all green)
```



## Version and changes

See [STATUS.md](STATUS.md) for the changelog. The version is single-sourced: the plugin's in `plugin/.claude-plugin/plugin.json` and the Python package's in `py/pyproject.toml`; `.claude-plugin/marketplace.json` mirrors the plugin version (marketplace format). The plugin and the Python package are versioned **independently** (distinct products, distinct cadence) — a plugin `1.27.x` alongside a package `0.17.x` is expected, not skew. No version number is restated in prose.
