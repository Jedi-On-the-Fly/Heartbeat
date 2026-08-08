# Drive HeartBeat over MCP

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

- **Read:** `tick`, `next`, `ready`, `state`, `report`, `diagnose`, `doctor`, `lint`, `audit`.
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

stdio + tools, stdlib-only (no MCP SDK — the core stays dependency-free). A streamable-HTTP
transport for remote/hosted clients is deferred; the design is in
[mcp-server-scope.md](../../planning/mcp-server-scope.md).
