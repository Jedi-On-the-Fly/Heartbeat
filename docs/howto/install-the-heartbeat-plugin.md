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

On a modern **externally-managed** Python (Debian/Ubuntu, PEP 668), that `pip install` is refused.
Install into an isolated venv and symlink `hb` onto your PATH — no `--break-system-packages`, nothing
touching system Python:

```bash
python3 -m venv ~/.heartbeat-venv
~/.heartbeat-venv/bin/pip install ./py
ln -sf ~/.heartbeat-venv/bin/hb ~/.local/bin/hb   # ~/.local/bin must be on PATH
```

(`pipx install ./py` does the same if you have pipx. Add a framework backend later with the extra,
e.g. `~/.heartbeat-venv/bin/pip install "./py[agno]"`.)

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
Prints `PLUGIN-MCP-OK`. A companion check
[`gate-examples/install-guide.sh`](gate-examples/install-guide.sh) verifies this guide's structural
claims (the `venv` fallback is available, `pip install ./py` yields the `hb` console, `hb mcp-serve`
is real, and the manifest registers `heartbeat`) — prints `INSTALL-GUIDE-OK`.

## Update an existing install

A local **directory** marketplace caches the plugin **per version**, so it does not auto-resync when
the repo changes — an old version keeps running until you refresh it. In Claude Code:

```
/plugin marketplace update heartbeat-marketplace
```

This re-reads the repo's `marketplace.json` (the marketplace source is the repo directory, so there's
nothing to pull). Then update `heartbeat` in the plugin manager (`/plugin`) and reload so the new
skills and templates load. Superseded versions sit under `~/.claude/plugins/cache/` and can be
deleted. For Codex, re-run `codex plugin marketplace add` / `codex plugin add`.

To update the `hb` console after a repo change (venv install above):

```bash
~/.heartbeat-venv/bin/pip install --force-reinstall ./py   # the ~/.local/bin/hb symlink stays valid
```

## What you get

Once installed, the agent drives HeartBeat: it asks `tick` what's next, does the work, and calls
`gate` to verify — acting on the deterministic answer. The trust model is unchanged: a gate is
behavioral and a review needs a distinct-actor artifact ([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md)).
See [drive-heartbeat-over-mcp.md](drive-heartbeat-over-mcp.md) for the tool surface and the remote
(`--http`) option.

Security note: the registered server's `gate` tool runs the DAG's gate criteria as shell commands,
so the server is as trusted as whoever can reach it — read
[secure-the-mcp-server.md](secure-the-mcp-server.md) before exposing it beyond local stdio.
