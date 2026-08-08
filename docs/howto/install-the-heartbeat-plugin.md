# Install the HeartBeat plugin (one plugin, both hosts)

HeartBeat ships a plugin whose manifest (`.claude-plugin/marketplace.json` + `plugin/.mcp.json`)
is read by **both** Codex and Claude Code — the same format. Installing it registers the
`hb mcp-serve` MCP server, so the host can [drive HeartBeat over
MCP](drive-heartbeat-over-mcp.md) with no manual `mcp add` step.

## Prerequisite

The MCP server is Python-delivered (host-neutral). Install the `hb` console so the plugin's server
command resolves:

```bash
pip install ./py     # provides `hb` on PATH; `hb mcp-serve` is the server
```

## Codex

```bash
codex plugin marketplace add /path/to/heartbeat        # the repo root (a local marketplace)
codex plugin add heartbeat@heartbeat-marketplace       # installs the plugin
codex mcp list                                          # shows the `heartbeat` stdio server
```

Installing wires an MCP server `heartbeat` → `hb mcp-serve` (stdio). From then on Codex can call
HeartBeat's `tick` / `gate` / `state` tools mid-session.

## Claude Code

Add the same repo as a plugin marketplace in Claude Code's plugin manager (it reads the same
`.claude-plugin/marketplace.json`) and install the `heartbeat` plugin. The bundled `plugin/.mcp.json`
registers the identical `hb mcp-serve` server — one manifest, both hosts.

## Verify

Deterministic, offline proof (no network, no model): a stub-free check that the plugin actually
registers the server —
[`gate-examples/plugin-mcp.sh`](gate-examples/plugin-mcp.sh) validates the manifest and, where
`codex` is installed, adds the marketplace + installs the plugin in an isolated `CODEX_HOME` (never
touching your real `~/.codex`) and confirms `codex mcp list` shows `heartbeat` → `hb mcp-serve`.
Prints `PLUGIN-MCP-OK`.

## What you get

Once installed, the agent drives HeartBeat: it asks `tick` what's next, does the work, and calls
`gate` to verify — acting on the deterministic answer. The trust model is unchanged: a gate is
behavioral and a review needs a distinct-actor artifact ([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md)).
See [drive-heartbeat-over-mcp.md](drive-heartbeat-over-mcp.md) for the tool surface and the remote
(`--http`) option.
