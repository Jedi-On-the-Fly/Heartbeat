# Scope — HeartBeat as an MCP server (the neutral core)

**Status: steps 1–4 BUILT** — stdio server + read *and* act tools (`hb mcp-serve`), the optional
streamable-HTTP transport (`--http`), and surface B (the plugin registers the server for both
hosts). Proven by `mcp-server.sh` / `mcp-http.sh` / `plugin-mcp.sh`; guides:
[drive-heartbeat-over-mcp.md](../docs/howto/drive-heartbeat-over-mcp.md),
[install-the-heartbeat-plugin.md](../docs/howto/install-the-heartbeat-plugin.md). This doc defines the rock: exposing
HeartBeat's deterministic verification surface over the Model Context Protocol so that *any*
MCP-capable agent — Codex, Claude Code, Cursor, and future hosts — drives the same tick / gate /
state operations through one integration, instead of a bespoke plugin per host.

## Why this is the strategic move

Codex (`codex mcp` / `codex mcp-server`) and Claude Code are both MCP clients. Today HeartBeat
integrates per-host: a Claude Code plugin, a `codex` backend, etc. An MCP server inverts that —
**one server, every client** — and is the "become the common boundary" play: HeartBeat becomes
the verification layer any coding agent can call. It also makes a Codex plugin (surface B) a thin
wrapper that just registers this server, rather than a separate build.

Two distinct relationships stay separate and both remain valid:
- **HeartBeat drives the agent** (Stage B backends: `codex`, `claude-code`, …) — already shipped.
- **The agent drives HeartBeat** (this MCP server) — the agent, mid-session, asks HeartBeat
  "what's next / did this phase pass / what's the state" and acts on the deterministic answer.

## Tool surface

Read/act tools mapping 1:1 to the `hb` CLI (the library is the single source of truth; see
[dev-python.md](../docs/dev-python.md)). **The mutate-only-through-the-log invariant is preserved
inside the server** — every state change goes through `state.mutate` / the CLI path, never a
direct write ([AGENTS.md](../AGENTS.md) rule 1).

| MCP tool | Maps to | Kind |
|---|---|---|
| `tick` | `tick.tick` | read → next action |
| `next` / `ready` | `resolver.resolve` / `ready_tasks` | read |
| `state` / `report` | `state.project` / `report` | read |
| `gate` | `gate.run_gate` (+ `--check`) | act (records `gate_passed`/`failed` via the log) |
| `start` / `done` / `fail` | `state.mutate` events | act (lease + event) |
| `review` | the validated review path | act (artifact-backed) |
| `diagnose` / `doctor` | `doctor` | read |

`audit` / `lint` are pure functions exposed read-only as well. Tool inputs/outputs are
JSON (the shapes the CLI already returns); a `--dir` equivalent selects the project.

## Transport & wiring

- **stdio** first (mirrors `codex mcp-server`): the server reads/writes JSON-RPC over stdio.
  Simplest, no ports, works for local agents.
- Codex wires it: `codex mcp add heartbeat -- hb mcp-serve --dir <project>` (stdio) — confirmed
  wire format (`codex mcp add <name> -- <command>` / `--url` for HTTP).
- Claude Code wires it via its MCP config (stdio command) — same server binary.
- The optional streamable-HTTP transport (`hb mcp-serve --http`, `--url` on the client) is built
  for remote/hosted use (Origin-validated, loopback-only without `--allow-remote`).

Delivery: a new `hb mcp-serve` subcommand (Python, stdlib + a small MCP layer) is the natural
home — one console, runs anywhere Python does, reuses the library. A Codex plugin (surface B)
then just ships a marketplace entry that runs `codex mcp add heartbeat -- hb mcp-serve`.

## Proof strategy (deterministic, suite-gateable — no model, no network)

The whole point of HeartBeat is that verification is deterministic, and the MCP server inherits
that: spin the server as a subprocess, speak JSON-RPC over stdio, call a tool, assert the
response — the same discipline as every how-to proof. Concretely, a `mcp-serve` proof:
1. `initialize` handshake returns the tool list (contains `tick`, `gate`, `state`, …).
2. `tick` on a fresh project returns `next_task` (matches `hb tick`).
3. `gate` on a passing project records `gate_passed` and advances the phase — and the same
   event appears in `events.jsonl` (the server used the real mutate path, not a side write).
4. Negative control: a `gate` call on an unpassable project returns blocked and does NOT advance.
5. Parity-ish: a tool's result equals the corresponding `hb <cmd>` result for the same project.

This is Docker-free and model-free — a genuine suite gate (a new Tnn group), unlike the live
agent tiers.

## Reused vs new

- **Reused:** the entire `heartbeat` library (state/resolver/gate/tick/doctor/audit/report) — the
  server is a thin JSON-RPC adapter over it. No re-implementation; parity with the CLI is free
  because both call the same functions.
- **New:** the `hb mcp-serve` subcommand + a minimal MCP/JSON-RPC handler (tool registration,
  stdio loop, input schemas), a proof script, and docs (a `docs/howto/drive-heartbeat-over-mcp.md`
  plus wiring notes for Codex and Claude Code).

## Sequencing

1. `hb mcp-serve` with the read tools (`tick`/`next`/`state`/`report`/`diagnose`) + the stdio
   handshake — smallest useful server; deterministic proof of the handshake + one read tool.
2. Add the act tools (`gate`/`start`/`done`/`fail`/`review`) through the real mutate path; extend
   the proof to the record-and-advance + negative control cases.
3. Docs + wiring: Codex (`codex mcp add`) and Claude Code; then surface B (a thin Codex plugin
   that registers the server). **BUILT** — `plugin/.mcp.json` registers `hb mcp-serve` for both
   hosts (proof: `docs/howto/gate-examples/plugin-mcp.sh`; guide:
   `docs/howto/install-the-heartbeat-plugin.md`).
4. **Step 4 BUILT** — an optional streamable-HTTP transport (`hb mcp-serve --http`) for
   remote/hosted clients (stdlib `http.server`; proof: `docs/howto/gate-examples/mcp-http.sh`).
5. **2026-07-28 dual-stack BUILT** — the server negotiates the classic handshake for older hosts
   and the **`2026-07-28`** spec (via `server/discover` + per-request `_meta` version → `resultType`
   / cacheable-list hints) for modern clients, without breaking today's Codex/Claude Code. HTTP is
   hardened (Origin validation, `--allow-remote` gate). Proven deterministically
   (`docs/howto/gate-examples/mcp-2026.sh`) and against the official MCP SDK v2 client
   (`tests/mcp-interop.sh`). Out of scope (deprecated/optional in 2026): sampling, logging, roots,
   tasks/MRTR, subscriptions.

## Risks & non-goals

- **Risk — an MCP dependency in the core.** Keep the JSON-RPC handler minimal/stdlib where
  feasible, or isolate any MCP SDK behind an optional extra so the stdlib-only core stays intact.
- **Risk — the invariant.** The server must mutate state ONLY through the log/CLI path; a direct
  write would break event-sourcing. The proof's "same event appears in events.jsonl" check guards
  this.
- **Risk — auth/trust.** An act tool (`gate`, `done`) run by an agent still can't fabricate a
  pass — the gate is behavioral and the review path requires a distinct-actor artifact. The MCP
  server changes *who calls*, not *what's trusted*.
- **Non-goal (now):** remote/hosted multi-tenant serving, and a rich resource/prompt surface —
  stdio + tools first.

## Status

All of the above is built: `hb mcp-serve` (read + act tools), the HTTP transport, surface B (the
plugin registers the server on both hosts), and the 2026-07-28 dual-stack — see the numbered
status list above and the proofs under `docs/howto/gate-examples/` + `tests/mcp-interop.sh`.
