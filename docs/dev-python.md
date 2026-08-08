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
| `state.py` | `project(events, dag)`, `read_events/read_dag/read_state`, `reproject`, `append_event`, `mutate`, `with_wlock`, `acquire_lease/release_lease`, `now_iso` | projector = plugin parity |
| `resolver.py` | `resolve(state, dag, hbdir)`, `ready_tasks(...limit)` | same return shapes as `hb-next-task.js` |
| `lint.py` | `lint(dag)` → `{errors, warnings}`, `extract_paths(cmd)` | errors match plugin verbatim |
| `audit.py` | `audit(dag)` → `{findings, errors, warns}`, `classify(cmd)`, `is_nondet(cmd)` | ruleset = plugin verbatim |
| `review.py` | `build_prompt(dag, det)`, `run(hbdir, dag)` → `{det, refuted, concerns}` | agent DAG refutation via a backend |
| `gate.py` | `eval_gate(hbdir, gate, timeout)`, `run_gate(hbdir, gate, check)`, `run_all(hbdir)` | criteria via `subprocess(shell=True)` |
| `tick.py` | `tick(hbdir)` → `{wakeAgent, data}` | Stage A; priority order = plugin |
| `doctor.py` | `doctor(hbdir)`, `has_rot(hbdir)`, `diagnose(hbdir, reason)` | rot + computed root-cause |
| `report.py` | `build(hbdir)`, `render(hbdir)` | JSON shape differs from node (progress-only parity) |
| `scaffold.py` | `init(project_dir, force)` | `hb init`; `DEFAULT_DAG`, `DEFAULT_EXECUTOR` |
| `protocol.py` | `PROTOCOL`, `render_md()` | reason keys = plugin; action text cites `hb` console |
| `executor.py` | `run(hbdir)`, `config(hbdir)`, `dispatch(...)`, `assemble_context`, in-process + subprocess dispatch, worktree parallel | pluggable Stage B |
| `backends/` | in-process backend registry | see below |
| `mcp_server.py` | `serve(hbdir)`, `TOOLS` | `hb mcp-serve` — minimal stdlib-only MCP server over stdio; see below |
| `cli.py` | `main(argv=None)` → argparse dispatch | the `hb` entry |

State mutation path (`mutate`): `with_wlock` (`.wlock`) → `append_event` → `reproject` → atomic write. Constants read from env at import: `LOCK_STALE_S`, `HEARTBEAT_STALE_S`, `STUCK_TICKS`, `HB_MAX_CONCURRENCY`, `HB_ROT_CHECK`, `GATE_TIMEOUT_S`.

## CLI — `hb <cmd>`

Dir resolution (`_hbdir`): `--dir <d>` (its `.hb`) > `$HB_DIR` > `./.hb`.

| Command | Effect / output |
|---|---|
| `init <project_dir> [--force]` | scaffold `.hb/` (dag, state, events, `executor.json`, `PROTOCOL.md`); git unless `HB_NO_GIT` |
| `tick` | one Stage-A tick → `{wakeAgent, data}` |
| `next` | `resolve` result JSON |
| `ready [N]` | runnable set JSON |
| `gate <G> [--check] [--all]` | run/verify a gate; exit 1 if blocked |
| `lint [dagfile] [--json]` | structural validation |
| `audit [dagfile] [--json] [--agent]` | gate-quality audit; `--agent` adds backend refutation |
| `report [--json]` | progress |
| `doctor` | integrity/rot |
| `diagnose [reason]` | computed root-cause |
| `protocol [reason] [--md]` | reason→action map |
| `state` | print projection |
| `rebuild` | reproject from log |
| `start/done/fail/heartbeat <id>` | state mutations (+ lease) |
| `review <gate> pass\|fail [note]` | record adversarial verdict |
| `exec [run\|config] [--parallel N]` | `run` (default) drives the loop with a backend; `config` prints the resolved executor config |
| `mcp-serve [--http] [--host H] [--port P]` | run the MCP server so an MCP client drives HeartBeat; stdio by default, `--http` for a streamable-HTTP endpoint; see below |

## Executor

`config(hbdir)` keys (env > `executor.json` > default): `backend` (`HB_EXEC_BACKEND`, `claude-code`), `cmd` (`HB_EXEC_CMD`), `strict` (`HB_EXEC_STRICT`), `attempt_cap` (`HB_EXEC_ATTEMPT_CAP`, 3), `concurrency` (`HB_MAX_CONCURRENCY`, 1), `heartbeat_s`.

`run(hbdir)` loop mirrors the plugin: tick → route reason. `next_task` → `hb start` → `dispatch(execute)` (lease heartbeat pumped by a `_Pump` thread) → `done`/`fail` (+attempt cap). `gate_pending` → strict check → `gate.run_gate`. `review_pending` → `dispatch(refute)` → `review`. Escalate-only on any human-needed reason (`HB-EXEC STOP: <reason>`). Parallel (`concurrency > 1`) uses `ThreadPoolExecutor`, one git worktree per task (`.hb/wt/<id>`), serialized merge-back, in-place fallback without git. `HB_EXEC_MAX_ITERS` bounds the loop (0 = unbounded).

**`dispatch(cfg, mode, payload, hbdir, task_id, cwd=None)`**: if `cfg.cmd` set → subprocess wire protocol (`bash -c "<cmd> <mode>"`, payload on stdin, JSON on stdout); else in-process `backends.get(cfg.backend).execute|refute(payload)` with `payload["cwd"]` set.

## Backends

Registry `backends.get(name)` → module with `execute(payload) → {ok, summary}` and `refute(payload) → {refuted, findings}`. Known: `ollama`, `agno`, `crewai`, `claude` (`claude-code` alias), `codex`, `opencode`, and the framework backends. `payload` carries `context`, `cwd`, and `task`. In-process (no subprocess) for the bundled backends; arbitrary commands use the subprocess path via `HB_EXEC_CMD`.

## MCP server (`hb mcp-serve`)

The inverse of a backend: instead of HeartBeat driving an agent, an MCP-capable agent drives
HeartBeat. `mcp_server.serve(hbdir)` runs a minimal, **stdlib-only** JSON-RPC 2.0 server over the
MCP stdio transport (newline-delimited JSON) — no MCP SDK, so the core stays dependency-free.
`TOOLS` maps each tool to the same library function the CLI calls: read (`tick`, `next`, `ready`,
`state`, `report`, `diagnose`, `doctor`, `lint`, `audit`) and act (`gate`, `start`, `done`, `fail`,
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
| `codex` | subprocess `codex exec` (stdin closed) | `HB_EXEC_PROVIDER=oss` → keyless Ollama |

`HB_EXEC_MODEL` selects the model; `OLLAMA_HOST` the server. Backend degrade: missing lib/server → protocol-valid `{ok:false}` / `{refuted:false}`.

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
