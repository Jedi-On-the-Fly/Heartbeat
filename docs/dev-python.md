# Dev — Python port (`py/`)

Backend reference for the pure-Python implementation. Narrative: [heartbeat-py.md](heartbeat-py.md). Plugin (node+bash): [dev-plugin.md](dev-plugin.md). Tests: [dev-tests.md](dev-tests.md).

Visual overview: [dev-python-poster.png](dev-python-poster.png).

Same DAG / event / gate model as the plugin, reimplemented as a pip-installable package with a single `hb` console. Stdlib-only core; the agent-framework backends are optional extras. Scope of "zero node/bash": HeartBeat's own tooling is Python — gate `cmd`s remain user-authored shell (the DAG contract), run via the system shell.

## Package

| Item | Value |
|---|---|
| distribution | `heartbeat-hb` (`py/pyproject.toml`) |
| import package | `heartbeat` (`py/src/heartbeat/`) |
| console script | `hb = heartbeat.cli:main` |
| extras | one per framework backend: `[agno]` `[crewai]` `[langgraph]` `[openai-agents]` `[autogen]` `[smolagents]` `[pydantic-ai]` |
| requires | Python ≥ 3.9; git optional |

Data model (`dag.json` / `events.jsonl` / `state.json`), event types, phase-completion rule, and `PROTOCOL` reason set are identical to the plugin — see [dev-plugin.md](dev-plugin.md#data-model). This doc covers the Python surface only.

## Modules

| Module | Key API | Notes |
|---|---|---|
| `state.py` | `project(events, dag)`, `read_events/read_dag/read_state`, `reproject`, `append_event`, `mutate`, `with_wlock`, `acquire_lease/release_lease`, `now_iso`, `drifted_gates` | projector = plugin parity; `drifted_gates` = the drift-tripwire walk (criteria-pinned pass history + current dag, canonical `(id, cmd)` identity, regate-window sanction, completed-cycle absolution — twin of hb.js `driftedGates`, parity case `drift:cross`); `project` folds `horizon_closed` events into a sparse, insertion-ordered `horizon_closed` (absent until a close; `initialized` resets it); `dag_shape_problems(hbdir)` — the structure errors of `dag.json` read through the checked file read (never `read_dag`'s empty-plan fallback), the one seam every plan-interpreting entry point consults (T186) |
| `resolver.py` | `resolve(state, dag, hbdir)`, `ready_tasks(...limit)` | same return shapes as `hb-next-task.js`, incl. `{type: replan_pending, phase}` when the flagged LAST live phase completes unclosed (an empty live list is `all_done`); a structure-invalid dag → `{type: deadlock, cause: dag_invalid, detail: {errors}}`, never a raise |
| `lint.py` | `lint(dag)` → `{errors, warnings}`, `extract_paths(cmd)` | errors match plugin verbatim (incl. `_check_constraints` — plan-time review constraints; T168; and the non-boolean `horizon` marker error); the shape contract (T186): `read_dag_file` (fixed-bytes unreadable classes; strict UTF-8, `NaN`/`Infinity` rejected, giant integer literals read as floats like JS, nesting bounded at 256 over the text), `shape_errors` (one path-named error per `x-hb-structure` violation), `structure_view` (the rules' view; gates in JS object key order) — mirrored with hb-lint.js; lint and audit read through it with or without a file argument |
| `audit.py` | `audit(dag)` → `{findings, errors, warns}`, `classify(cmd)`, `is_nondet(cmd)` | ruleset = plugin verbatim (incl. the `unconstrained_review` warning and the `speculative_tail` warning — `_speculative_tail`; hostile gate shapes read as empty via `_gate_obj`/`_gate_id`); the `dag_shape` error finding on a structure-invalid or unreadable plan (`--questions` refuses with exit 1) |
| `review.py` | `build_prompt(dag, det)`, `run(hbdir, dag)` → `{det, refuted, concerns}` | agent DAG refutation via a backend |
| `gate.py` | `eval_gate(hbdir, gate, timeout)`, `run_gate(hbdir, gate, check)`, `run_all(hbdir)` | criteria via `subprocess(shell=True)` |
| `tick.py` | `tick(hbdir)` → `{wakeAgent, data}` | Stage A; priority order = plugin (criteria drift outranks rot and wakes `criteria_drift` EVERY tick until cured — reason keys identical to tick.sh); `replan_pending` wakes once per horizon phase via the shared `.replan-alerted` flag (holds the phase id; cleared on the task and `all_done` branches), then sleeps `replan_waiting` — no event appended; the structure check runs FIRST (before the state self-heal) and wakes `dag_corrupted` with the errors every tick, one event per blockage; a raising resolver or an unusable answer → `deadlock` cause `resolver_error`, every tick, never arming `.deadlock-alerted` |
| `doctor.py` | `doctor(hbdir)`, `has_rot(hbdir)`, `diagnose(hbdir, reason)` | rot + computed root-cause (a gate blocked by a failed review: `Cause: review_failed` + findings; `hb exec` names the same cause on its `gate_blocked` stop); once `_start` exists, accepted gates missing their acceptance anchor or (recorded autocommit-on) their tag — lines identical to node (T167); a structure-invalid plan → only its structure errors plus `plan checks skipped: dag.json invalid`; `diagnose` names `dag_corrupted`, and a raising resolver is `Cause: resolver_error` |
| `report.py` | `build(hbdir)`, `render(hbdir)`, `refuter_impact(events, dag)` | JSON shape differs from node (progress-only parity); the refuter-impact summary (catches/clears per gate + `review.profile` lens, from the event log) is a node≡python shared surface (T152); `render` marks a pending-regate phase line `⛔ revised — rearm pending (by <actor>: <reason>)` (cleared by a valid rearm; `--json`/`build` untouched; == node, T181); `_horizon_line` prints the horizon line (planned / REACHED / closed by) when the last live phase is flagged |
| `scaffold.py` | `init(project_dir, force)` | `hb init`; `DEFAULT_DAG`, `DEFAULT_EXECUTOR` |
| `protocol.py` | `PROTOCOL`, `render_md()` | reason keys = plugin; action text cites `hb` console |
| `executor.py` | `run(hbdir)`, `config(hbdir)`, `dispatch(...)`, `assemble_context`, `_constrained_review`, in-process + subprocess dispatch, worktree parallel | pluggable Stage B; a CONSTRAINED gate runs the constraint-first pipeline (twin of `constrainedReview`, T172); in-process dispatch handles `execute` / `refute` / `author` (the backend's review call → `_fileblocks.author_reply`) and refuses any other mode; `replan_pending` and every later `replan_waiting` run stop `HB-EXEC STOP: replan_pending — <phase>` (exit 1); stops on `dag_corrupted` and on every `deadlock` (incl. `resolver_error`) |
| `backends/` | in-process backend registry | see below |
| `adapters/code/` | `deplint`, `codegraph_map` (+ `resolve_task_symbols`), `codegraph_context`, `codegraph_discover`, `deplint_accept`, `codegraph_exclude_hb`, `codegraph_coverage` | domain adapter — a parity surface with `plugin/adapters/code/*.js` (node ≡ python; T94/T98/T100/T106). `python3 -m heartbeat.adapters.code.deplint …` |
| `adapters/docs/` | `docs_map`, `docs_context` (`js_trim`) | docs domain adapter — parity with `plugin/adapters/docs/*.js` (T95). Node-free; usable as a `context_cmd` with zero Node (T96) |
| `adapters/research/` | `ground_check` (the gate), `stamp_evidence`, `research_context` | research domain adapter — parity with `plugin/adapters/research/*.js` (node ≡ python; T110–T115). Grounding, not truth; the fetch is on-demand/non-gated. `python3 -m heartbeat.adapters.research.ground_check …` |
| `mcp_server.py` | `serve(hbdir)`, `TOOLS` | `hb mcp-serve` — minimal stdlib-only MCP server over stdio; see below; on a structure-invalid plan `tick` wakes `dag_corrupted`, `next` answers `dag_invalid`, lint/audit/doctor/diagnose report, `code_context`/`code_discover`/`deplint` are dag-independent, and every other tool returns an error result (`_SHAPE_FREE`) |
| `bench.py` | `score(hbdir)`, `run(source, specs)`, `reward_records(events, dag)`, `rewards(hbdir)`, `regressions(cards, baseline)`, `render`, `build` | `hb bench` (+`--baseline` regression verdict), `hb reward` — score N backends, extract the verifiable-reward stream, flag model-regression; all pure over the event log |
| `review_policy.py` | `accept_review(hbdir, gate, verdict, artifact=None, note=None)` → `(rc, out, err)` | the single source of the review-acceptance rules (substantive artifact, phase citation, distinct actor, commit+tag on pass — via `gate._git_snapshot`, whose failed steps are reported + recorded as `restore_point_failed`; `review_passed` carries `git:{autocommit}` from `gate.git_policy`); `cli.py`, `executor.py`, and `mcp_server.py` all call it directly — no re-entering `cli.main` and scraping stdout |
| `refuter_profiles.py` | `resolve(hbdir, name=None)` → `{persona, questions[], model, provider, verdict, author_model, free_review, free_model}` (`free_review` via `_to_bool` — twin of `toBool`), `compose_prompt(hbdir, dag, gate, free=False)` (constrained block / free variant — T170), `DEFAULT_PERSONA` | resolve a refuter-profile NAME to a normalized dict — a parity surface with `plugin/templates/refuter_profiles.js` (node ≡ python; T145). See "Refuter profiles" below |
| `anchors.py` | `list_project_files`, `write_anchor`, `try_anchor`, `read_anchor`, `is_first_start`, `changed(hbdir, gate)` | twin of the hb.js anchor section (node ≡ python on manifest + change list; T166). `_start` is taken by `state.mutate` on the first live `task_started` (decided under the write lock by `is_first_start`, hashed after release) — the one layer the CLI, MCP `start` and the executor share; acceptance anchors by `gate.run_gate` (review-less pass) and `review_policy.accept_review`, after the restore point |
| `constraints.py` | `plan_constraints`, `review_cycle`, `compose_author_prompt`, `record`, `doctor_problems` | gate-time constraint author — twin of the hb.js constraint section (prompt bytes + record verdicts node ≡ python; T169). Validation reuses `lint.constraint_errors(list, "G")` |
| `cli.py` | `main(argv=None)` → argparse dispatch | the `hb` entry |

State mutation path (`mutate`): `with_wlock` (`.wlock`) → `append_event` → `reproject` → atomic write. The verbs that rewrite `dag.json` (`park`, `unpark`, `regate`, `detach`, `reattach`) do so under the lock through `state.write_dag` — tmp + rename, never in place (T188). The lock guards exactly this state.json read-modify-write; append-only informational events (`wake`, `lease_expired`, …) are written lock-free by design (atomic O_APPEND + reproject is a full re-fold — see [parity-notes.md](../planning/parity-notes.md) "Write-lock scope"). Constants read from env at import: `LOCK_STALE_S`, `HEARTBEAT_STALE_S`, `STUCK_TICKS`, `HB_MAX_CONCURRENCY`, `HB_ROT_CHECK`, `GATE_TIMEOUT_S` (default 60; a criterion's own `timeout_s` in dag.json wins), `GATE_OUT_LINES` (failing-criterion output tail, default 20 — matches the node runner). Gate criteria run with `stdin=DEVNULL` (mirrors gate.sh's `</dev/null` on both branches): a criterion sees EOF, never the caller's stdin (T165).

## CLI — `hb <cmd>`

Dir resolution (`_hbdir`): `--dir <d>` (its `.hb`) > `$HB_DIR` > `./.hb`.

| Command | Effect / output |
|---|---|
| `init <project_dir> [--force]` | scaffold `.hb/` (dag, state, events, `executor.json`, `PROTOCOL.md`); git unless `HB_NO_GIT` |
| `tick` | one Stage-A tick → `{wakeAgent, data}` |
| `next` | `resolve` result JSON |
| `ready [N]` | runnable set JSON |
| `gate <G> [--check] [--all]` | run/verify a gate; exit 1 if blocked. Result lines carry durations and stream as produced (TTY adds a transient ⏳ "running now" line); `--all` sweeps only ever-passed gates (planned ones skipped, reported), announces its scope up front, dedupes byte-identical (cmd, effective-timeout) criteria within the sweep (reuses reported, counted), re-runs a failure once to label it FLAKY vs reproduced (verdict never changes — fail-closed), EXCLUDES a drifted gate from re-evaluation and counts it FAILING annotated (`st.drifted_gates`; a pending regate likewise counts, parked or not — parked silences nothing), and reports the elapsed total; exit 4 when `dag.json` is unreadable or structurally malformed, checked before every mode, no event; `--all` lists, counts and skips `"sweep": false` criteria (gate-time only — `eval_gate`'s sweep mode) and names a gate with nothing left to re-verify |
| `lint [dagfile] [--json]` | structural validation |
| `audit [dagfile] [--json] [--agent]` | gate-quality audit; `--agent` adds backend refutation |
| `report [--json]` | progress |
| `doctor` | integrity/rot + criteria drift (an unsanctioned edit of a pinned gate's criteria is a PROBLEM, bytes identical to node — `st.drifted_gates`, T184) |
| `diagnose [reason]` | computed root-cause |
| `protocol [reason] [--md]` | reason→action map |
| `state` | print projection |
| `rebuild` | reproject from log |
| `park <PHASE\|GATE> [--reason …]` / `unpark <PHASE\|GATE>` | retire a phase without deleting it (sets `parked` in dag.json; resolver/audit/report skip it and the sweep retires it from EVALUATION, loudly; parked silences neither a pending regate nor criteria drift — both stay in the `--all` failing count; reversible; read-modify-write under the write lock) |
| `regate <PHASE\|GATE> --reason <why>` | sanctioned gate revision — declare half (node twin: `hb regate <id> <reason…>`, the park arg-style divergence): reason + `HB_ACTOR` required, criteria snapshotted to `gates.<G>.regate` under `st.with_wlock`, audit-only `gate_regated`; while pending the CHOKEPOINTS refuse — `gate.eval_gate` itself (so `hb gate` run/check/all AND `diagnose` never execute revised criteria; the CLI maps the status to exit 3 ≡ gate.sh), `review_policy.accept_review` (all verdicts — the CLI, the MCP `review` tool and the executor all route through it; phase ids resolved), `constraints.record`, the tick (`regate_pending_waiting` sleep, both states), and the executor's writers |
| `detach <PHASE\|GATE> --reason <why>` / `reattach <PHASE\|GATE>` | retract/restore a dependency claim (node twin: trailing-words reason — the park/regate precedent): `gate_entry` → null + the four `detached_*` fields + audit-only `phase_detached`/`phase_reattached` under `st.with_wlock`; the per-channel weasel warning (`cli._detach_warn` ≡ hb.js `detachWarn`); the stamped detach anchor via `anchors.write_anchor(…, extra=…)`; `anchors.changed()` resolves the base `gate_entry \|\| _detach_<PHASE> \|\| _start` with the stamp check; reattach refuses a `detached_from` that is not a defined gate AND some phase's `gate_exit`; `lint._check_detach` twins the shape rules incl. the reserved `_start`/`_detach_*` gate names (exact equality + prefix — NOT a regex: `re.match`'s `$` matches before a trailing newline and JS's does not, a refuter fuzz catch); `report.render` marks `⟂ detached from <gate>` (text only); doctor NOTES the live detach and both divergence directions |
| `horizon close --reason <why>` | the recorded end of a knowledge horizon (node twin: `hb horizon close --reason <why…>`, trailing words): appends `horizon_closed {phase, reason}` and reprojects under `st.with_wlock`; refused (exit 1, no event) on an empty reason, an all-parked plan, an unflagged last live phase, an incomplete live phase, an already-closed horizon (the projection's `horizon_closed`), or an open revision on any live gate (`regate_blocks` / `unanswered_regate` / `stale_rearm`) |
| `regate <PHASE\|GATE> --rearm --artifact <f> [--model M]` | the evidence bar (different actor, ≥ 40 code-point artifact citing a phase anchor — `state.substantive_len`, explicit ASCII trim ≡ node; audit re-run INSIDE the lock), sha256 pinned on the stored `reviews/<G>.regate.md` + `gate_rearmed` + the dag record; acceptance then owes a FRESH provenanced pass (`state.stale_rearm`), the log outranks a hand-edited marker (`state.unanswered_regate`), and the review cycle restarts at the rearm (`constraints._cycle_start` — the ONE start computation `review_cycle` and `review_cycle_full` share) |
| `start/done/fail/heartbeat <id>` | state mutations (+ lease) |
| `review <gate> pass\|fail\|free [note]` | record adversarial verdict — enforcement lives in `review_policy.accept_review`: the answers on a constrained gate (`check_answers`), the `HOLES: none` line on an unconstrained pass and a free review (`check_holes`; `doctor` re-checks a pass's stored artifact), so the CLI, the MCP `review` tool (verdict `free` in its schema) and the executor all enforce it |
| `constraints <gate> --prompt [--json] \| --record <file.json> [--model M]` | gate-time constraint author; see `constraints.py` (`record` refuses a constraint that names no file the phase changed — `grounding_errors` / `_subject_path`, existence when there is no change list; == node) |
| `changed <gate> [--json]` | what the phase exiting `<gate>` changed (entry anchor vs the gate's own anchor once accepted, else the live tree); see `anchors.py` |
| `exec [run\|config] [--parallel N]` | `run` (default) drives the loop with a backend; `config` prints the resolved executor config |
| `mcp-serve [--http] [--host H] [--port P]` | run the MCP server so an MCP client drives HeartBeat; stdio by default, `--http` for a streamable-HTTP endpoint; see below |
| `bench --backend <spec>… [--baseline L] [--json]` | run the source DAG under each backend (a registered name, or `label=command`) on isolated copies and print a behavioral scorecard (`bench.py`); `--baseline L` adds a model-regression verdict vs card `L`; Python-delivered analytical tooling |
| `reward [--json]` | extract the verifiable-reward stream from the event log — one `{gate, phase, passed, actor, ts}` record per gate evaluation, `passed` = the deterministic log verdict (`bench.py`); Python-delivered analytical tooling |

On a structure-invalid or unreadable `dag.json` every plan-interpreting verb (`_shape_checked` in cli.py: start, done, fail, heartbeat, review, regate, detach, reattach, horizon, park, unpark, constraints, state, ready, rebuild, changed, evidence, refute-prompt, report, reward, bench) refuses before reading or writing: exit 1, ONE stderr line naming the first error and `hb lint` (T186). `next` answers `deadlock` / `dag_invalid`; `doctor`/`diagnose` report; `init`, `protocol`, `refuters`, `lint`, `audit`, `mcp-serve` and `exec` (it stops on the tick's wake) are outside the class.

## Executor

`config(hbdir)` keys (env > `executor.json` > default): `backend` (`HB_EXEC_BACKEND`, `claude-code`), `cmd` (`HB_EXEC_CMD`), `strict` (`HB_EXEC_STRICT`), `attempt_cap` (`HB_EXEC_ATTEMPT_CAP`, 3), `concurrency` (`HB_MAX_CONCURRENCY`, 1), `heartbeat_s`. **Cross-model refuter:** `refute_backend`/`refute_cmd`/`refute_model`/`refute_provider` (`HB_REFUTE_BACKEND`/`HB_REFUTE_CMD`/`HB_REFUTE_MODEL`/`HB_REFUTE_PROVIDER` or `executor.json refute_*`) each fall back to the doer's, so the `refute` call can run on a distinct backend/model — `dispatch(..., model=, provider=)` sets `HB_EXEC_MODEL`/`PROVIDER` around the call (try/finally). See [cross-model-verification.md](../docs/howto/cross-model-verification.md).

`run(hbdir)` loop mirrors the plugin: tick → route reason. `next_task` → `hb start` → `dispatch(execute)` (lease heartbeat pumped by a `_Pump` thread) → `done`/`fail` (+attempt cap). `gate_pending` → strict check → `gate.run_gate`. `review_pending` → `dispatch(refute)` → `review_policy.accept_review` (the shared policy — a degraded refute routes to `review_error`, never a fail-open pass). Escalate-only on any human-needed reason (`HB-EXEC STOP: <reason>`) — including `replan_pending`, which also stops every later run whose tick sleeps `replan_waiting`. Parallel (`concurrency > 1`) uses `ThreadPoolExecutor`, one git worktree per task (`.hb/wt/<id>`), serialized merge-back, in-place fallback without git. `HB_EXEC_MAX_ITERS` bounds the loop (0 = unbounded).

**`dispatch(cfg, mode, payload, hbdir, task_id, cwd=None)`**: if `cfg.cmd` set → subprocess wire protocol (`bash -c "<cmd> <mode>"`, payload on stdin, JSON on stdout); else in-process `backends.get(cfg.backend).execute|refute(payload)` with `payload["cwd"]` set.

## Refuter profiles

`refuter_profiles.resolve(hbdir, name=None)` turns a profile NAME into a normalized bundle
`{persona, questions[], model, provider, verdict}` — a named adversarial-review persona a gate or
project selects instead of re-writing free-text prompts. Pure resolution; composition of the actual
refute prompt from a resolved profile lives at the dispatch site.

- **Schema** — a profile file `.hb/refuters/<name>.json` (or an `executor.json` `{"refuters": {…}}`
  inline entry) with any of: `persona` (str), `questions` (str[], a domain falsification lens folded
  *additively* into the gate's `review_questions`), `model`/`provider` (route through the cross-model
  `refute_*` path), `verdict` (`{panel:N, refute_if:"majority"|"any"|"all"}`; under `hb exec` a panel's pass artifact is its CLEAR panelists' findings, the outvoted panelists' findings ride as the pass note — == node). Missing fields
  normalize to `""`/`[]`/`null` so every profile — and both runtimes — return the same keys.
- **Built-in default** — a `default` profile (generic-skeptic `DEFAULT_PERSONA`, no extra questions)
  is *always* resolvable, so refutation can never fail-open for want of a profile. It is **opt-in**
  (name it, or `HB_REFUTER=default`); the no-profile automated path is byte-unchanged.
- **Precedence** — which name: explicit `name` (a gate's `review.profile`) > `HB_REFUTER` env >
  `default`. Where a name resolves: project files (`search_dirs`, project shadows shipped) >
  `executor.json` inline > built-in `default`. An unknown **explicit** name raises — never a silent
  no-review. Node twin + parity: `plugin/templates/refuter_profiles.js`, T145.
- **Compose** — `compose_prompt(hbdir, dag, gate)` (and `hb refute-prompt <gate>`) is the ONE compose
  every refute surface uses (the executor's `review_pending`, and the interactive skill). No profile
  selected ⇒ the gate's `review.prompt`; else persona + the gate's BASE `review_questions` + the
  profile's EXTRA questions (**appended**, never replacing) + `review.prompt`. An unconstrained gate then
  gets the HOLES block (`HOLES_BLOCK`); a constrained gate gets the change list, every id, the answer
  format, the claims rule (`CLAIMS_RULE`) and the triage rule (== node).
  `hb refute-prompt <gate> --json` adds the machine-readable binding for an interactive host —
  `{prompt, model, provider, panel, refute_if}` with `prompt` byte-identical to the text compose and
  all fields null when no profile (never fabricated) — so a spawner routes the refuter (and records
  `--model`) without parsing prose (T163, `parity.sh refute-prompt:json`). The review-event model
  field: `accept_review(model=…)` records it on both verdicts (null when unknown — honest, never
  fabricated), the executor auto-stamps the resolved profile model, the MCP review tool passes
  `model` through, and `report.refuter_impact` breaks caught/cleared down per model (T164).
  A profile's `model`/`provider` route through the existing cross-model `refute_*` path
  (`gate_profile`). Unknown profile ⇒ raises ⇒ the executor fails **closed** (`review_error`). Shipped
  `hb refuters` lists profiles; both node ≡ python (T146/T147). Shared `tick.py` untouched.

## Backends

Registry `backends.get(name)` → module with `execute(payload) → {ok, summary}` and `refute(payload) → {refuted, findings}`. Known: `ollama`, `agno`, `crewai`, `claude` (`claude-code` alias), `codex`, `opencode`, and the framework backends. `payload` carries `context`, `cwd`, and `task`. In-process (no subprocess) for the bundled backends; arbitrary commands use the subprocess path via `HB_EXEC_CMD`.

## MCP server (`hb mcp-serve`)

The inverse of a backend: instead of HeartBeat driving an agent, an MCP-capable agent drives
HeartBeat. `mcp_server.serve(hbdir)` runs a minimal, **stdlib-only** JSON-RPC 2.0 server over the
MCP stdio transport (newline-delimited JSON) — no MCP SDK, so the core stays dependency-free.
`TOOLS` maps each tool to the same library function the CLI calls: read (`tick`, `next`, `ready`,
`state`, `report`, `diagnose`, `doctor`, `lint`, `audit`, plus the node-free domain-adapter tools
`deplint`, `code_context`, and `code_discover` — they call `heartbeat.adapters.code.*`, proven `== ` the adapters by
T97/T99) and act (`gate`, `start`, `done`, `fail`,
`review`). Act tools route every state change through `state.mutate` / the validated review path —
the mutate-only-through-the-log invariant holds exactly as in the CLI. Proof:
`docs/howto/gate-examples/mcp-server.sh`; guide: `docs/howto/drive-heartbeat-over-mcp.md`.

Versions (dual-stack, negotiated per request): older clients use the `initialize` handshake
(negotiated among `HANDSHAKE_VERSIONS`, never blind-echoed); 2026 clients probe **`server/discover`**
(advertises `DISCOVER_VERSIONS` = `2026-07-28` + `2025-06-18`, capabilities, serverInfo in `_meta`)
and are detected per-request via `_meta` protocol version (`_is_modern`), which adds `resultType` +
cacheable-list hints — old responses stay byte-identical. Verified against the official MCP SDK v2
client (`tests/mcp-interop.sh`, on-demand). Out of scope: sampling/logging/roots/tasks (deprecated
in 2026).

Transports: **stdio** by default; `serve_http(hbdir, host, port, allow_remote)` adds an optional
streamable-HTTP endpoint (stdlib `http.server`, `--http`/`--host`/`--port`; `--port 0` binds an
ephemeral port and prints it) sharing the same `_handle` dispatch. It validates the `Origin` header
(DNS-rebinding) and refuses a non-loopback bind without `--allow-remote`. The HeartBeat **plugin** also
registers the server: `plugin/.mcp.json` declares `heartbeat → hb mcp-serve`, so installing the
plugin in Codex or Claude Code wires it with no manual `mcp add` (proof:
`docs/howto/gate-examples/plugin-mcp.sh`; guide: `docs/howto/install-the-heartbeat-plugin.md`).

| Backend | Worker | Provider |
|---|---|---|
| `ollama` | stdlib `urllib` → local model; FILE-block writer (`backends/_fileblocks.py`) | — |
| `agno` | Agno agent + `FileTools` | `HB_EXEC_PROVIDER=anthropic\|ollama` |
| `crewai` | CrewAI Agent+Task+Crew; FILE-block writer | `HB_EXEC_PROVIDER` |
| `langgraph` | LangGraph ReAct agent + `save_file` tool | `HB_EXEC_PROVIDER=anthropic\|ollama\|openai` |
| `openai-agents` | OpenAI Agents SDK Agent + function tool | `HB_EXEC_PROVIDER=openai\|ollama` |
| `autogen` | AutoGen AssistantAgent; FILE-block writer | `HB_EXEC_PROVIDER=openai\|ollama` |
| `smolagents` | smolagents ToolCallingAgent + `save_file` tool | `HB_EXEC_PROVIDER=openai\|ollama` |
| `pydantic-ai` | pydantic-ai Agent + `save_file` tool | `HB_EXEC_PROVIDER=openai\|ollama` |
| `claude` | subprocess `claude -p` | — |
| `codex` | subprocess `codex exec` (stdin closed); `author()` runs read-only | `HB_EXEC_PROVIDER=oss` → keyless Ollama; `HB_CODEX_NETWORK=1` → `-c sandbox_workspace_write.network_access=true` on execute/refute (== codex-exec.sh) |
| `opencode` | subprocess `opencode run --format json` | `HB_EXEC_MODEL=provider/model` (e.g. `ollama/…`) |

`HB_EXEC_MODEL` selects the model; `OLLAMA_HOST` the server; `HB_OLLAMA_NUM_CTX` (default 16384) the context the ollama backend requests — a prompt that fills it is refused. Backend degrade: missing lib/server → protocol-valid `{ok:false}` for execute and `{error}` for refute; `refute_result()` returns a verdict only when the reply's last non-empty line is only the verdict (optional markup, an optional `Verdict:` label, the upper-case token, optional `.`/`!`) and the line before it neither begins with a verdict token nor ends with one after a separator — the contract is `py/tests/verdict_cases.json`; anything else (a same-line `… CLEAR`, `NOT yet CLEAR`, `REFUTED | CLEAR`, a list of both) is no verdict. A last line that is only a verdict is read at face value, whatever the reply argued before it (a hard-wrapped "…is not⏎CLEAR" included) — the answer-format check of a constraint-first review is the backstop there (`verdict_of`; opencode reads only the text parts of its JSON stream), else `{error}` (fail-closed). The executor's author fallback (a backend without `author()`) sets `HB_REFUTE_RAW=1` so the raw reply reaches `author_reply`.

## Audit

Same rules/severities as the plugin ([dev-plugin.md](dev-plugin.md#audit)). `hb audit --agent` runs the deterministic audit then `review.run` — builds a refutation prompt (DAG + deterministic findings), dispatches via the configured backend's `refute`, and exits non-zero if the reviewer refutes (`refuted` true). Verdict reported as SOUND/UNSOUND.

## Runtime differences from the plugin (intentional)

| Surface | Same | Runtime-specific |
|---|---|---|
| projector / resolver / lint / audit / diagnose-reason | identical output | — |
| `PROTOCOL` | reason keys | action text (`hb` vs `.hb/hb.js`/`gate.sh`) |
| report JSON | progress numbers | field names, extra node fields |
| gate cmds | shell contract | run via `subprocess(shell=True)` |
| backends | wire contract | in-process (py) vs subprocess (node) |

Parity is asserted by [dev-tests.md](dev-tests.md#parity) / [parity-notes.md](../planning/parity-notes.md); keep these columns honest when editing either side.

## Invariants

- Projector, resolver, lint, audit outputs must equal the plugin's (T43 parity). `PROTOCOL` reason keys must match; action wording may differ.
- `state.json` is a projection; mutate only via the CLI/`state.mutate`.
- Backends never touch `state.json`/`gate.sh`; only the driver mediates state.
- Core imports stay stdlib-only; framework imports live inside `backends/*` behind try/except degrade.
