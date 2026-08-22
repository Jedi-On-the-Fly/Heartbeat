# Drive HeartBeat over MCP

> **Runtime note.** The MCP server (`hb mcp-serve`, declared in `plugin/.mcp.json`) requires the **Python** `hb` (`pip install -e py` / heartbeat-hb) — a node-only plugin install cannot run `hb mcp-serve`. Install the Python package to use it.
Two relationships, kept separate:

- **HeartBeat drives the agent** — a Stage B backend (`codex`, `claude-code`, a framework, …)
  does the work; HeartBeat schedules and verifies it. See
  [choose-a-backend.md](choose-a-backend.md).
- **The agent drives HeartBeat** — *this* guide. An MCP-capable agent (Codex, Claude Code,
  Cursor, …), mid-session, asks HeartBeat "what's next / did this phase pass / what's the
  state" and acts on the **deterministic** answer.

`hb mcp-serve` exposes HeartBeat's operations as [MCP](https://modelcontextprotocol.io) tools over
stdio, so any MCP client calls the same tick / gate / state surface through one integration —
instead of a bespoke plugin per host.

## The tool surface

Every tool calls the same library function the CLI calls, so a tool answer equals the matching
`hb` command:

- **Read:** `tick`, `next`, `ready`, `state`, `report`, `diagnose`, `doctor`, `lint`, `audit`, and the
  domain-adapter tools `deplint` (code-aware dep-lint of a dag against a codemap → missing / redundant
  / collision), `code_context` (render a task's code subgraph as context), and `code_discover` (from
  entry symbols, the transitively-affected set — change impact). The adapter tools are
  **node-free** — they call the Python adapters (a parity surface; see [adapters.md](../adapters.md)),
  so an MCP client gets code-aware planning + context with zero Node. Proven by
  [gate-examples/mcp-adapters.sh](gate-examples/mcp-adapters.sh) (they return exactly what the Python
  adapter returns).
- **Act:** `gate` (runs the behavioral gate; a pass records `gate_passed` and advances the phase),
  `start` / `done` / `fail` (lease + event), `review` (the artifact-backed adversarial verdict).

Act tools route every state change through the event log — the same mutate path the CLI uses, so
`state.json` stays a projection and can never be side-written. That invariant is proven, not
asserted (below).

## Wire it up

The server speaks newline-delimited JSON-RPC 2.0 over stdio (the MCP stdio transport). Point a
client at `hb mcp-serve --dir <project>`:

```bash
# Codex
codex mcp add heartbeat -- hb mcp-serve --dir /path/to/project

# Claude Code
claude mcp add heartbeat -- hb mcp-serve --dir /path/to/project
```

Both hosts run the same binary — the server is Python-delivered and host-neutral (an intentional
non-parity, noted in [parity-notes.md](../../planning/parity-notes.md)). Once registered, the
agent can call `tick` to get the next action, do the work, then `gate` to verify it.

Or skip the manual wiring: install the HeartBeat plugin and it registers the server for you, on
either host — see [install-the-heartbeat-plugin.md](install-the-heartbeat-plugin.md).

### Remote (HTTP)

For a remote/hosted client, `hb mcp-serve --http --host <h> --port <p>` serves the same tools over
a minimal streamable-HTTP endpoint (stdlib-only; stdio stays the default). Point a client at the
URL — e.g. `codex mcp add heartbeat --url http://<h>:<p>`.

The HTTP endpoint is unauthenticated and can run gate shell-commands, so it is hardened: it
validates the `Origin` header (rejecting cross-origin browser requests — the DNS-rebinding
defence) and **refuses to bind a non-loopback `--host` unless you pass `--allow-remote`**. Keep it
on loopback unless you know what you're exposing — see
[secure-the-mcp-server.md](secure-the-mcp-server.md) for the full threat model.

## Protocol versions (dual-stack)

The server speaks both the classic handshake and the 2026 spec, negotiated per client:

- **Older clients** (today's Codex, Claude Code) open with `initialize`; the server negotiates the
  version it implements (never blind-echoes) and answers exactly as before.
- **2026 clients** probe **`server/discover`** first (it advertises the supported versions —
  `2026-07-28` and `2025-06-18` — plus capabilities and identity), then get 2026 result semantics
  (`resultType`, cacheable list hints). The official MCP Python SDK v2 client negotiates
  `2026-07-28` with the server this way; see the on-demand
  [`tests/mcp-interop.sh`](../../tests/mcp-interop.sh) and its
  [results](../../tests/MCP-INTEROP-RESULTS.md).

Deprecated 2026 features (sampling, logging, roots, tasks) are intentionally out of scope — the
tool surface is the durable core.

## Trust doesn't change

An agent calling `gate` or `done` still can't fabricate a pass: the gate is behavioral and the
review path requires a distinct-actor artifact ([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md),
[add-refutation-to-a-sensitive-gate.md](add-refutation-to-a-sensitive-gate.md)). MCP changes *who
calls*, not *what's trusted*.

## Proof

Deterministic, model-free, network-free —
[`gate-examples/mcp-server.sh`](gate-examples/mcp-server.sh) spins the real `hb mcp-serve` and
drives it with an actual JSON-RPC client over stdio:

- **`MCP-READ-OK`** — the `initialize` handshake is valid, `tools/list` carries the read tools, and
  `tick` / `next` / `state` return exactly what the CLI returns (the tools call the real library,
  not canned output).
- **`MCP-ACT-OK`** — a `gate` call records `gate_passed` in `events.jsonl` and advances the phase; a
  failing gate does not (a load-bearing negative control).
- **`MCP-INVARIANT-OK`** — after `start` / `done`, `state.json` on disk equals the event-log
  projection, so the server never side-writes state.

## Scope

stdlib-only (no MCP SDK — the core stays dependency-free). Both transports ship: stdio (default)
and the minimal streamable-HTTP endpoint above (`--http`, single JSON response per POST, no SSE
server-push). The full design is in [mcp-server-scope.md](../../planning/mcp-server-scope.md).
