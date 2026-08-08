#!/usr/bin/env bash
# Proof for surface B: installing the HeartBeat plugin registers the `hb mcp-serve` MCP server, for
# both hosts. Two tiers:
#   STATIC (always) — plugin/.mcp.json declares an mcpServers.heartbeat wiring `hb mcp-serve`, and
#     .claude-plugin/marketplace.json lists the `heartbeat` plugin (source ./plugin).
#   CODEX-LIVE (only if `codex` is on PATH) — in an ISOLATED CODEX_HOME (a mktemp dir, so the user's
#     ~/.codex is never touched), fully OFFLINE: add the repo as a local marketplace, install the
#     plugin, and assert `codex mcp list` shows a `heartbeat` stdio server (command hb, args
#     mcp-serve) — i.e. the install actually WIRED the server, not just discovered the plugin.
# Prints PLUGIN-MCP-OK, noting whether the codex-live tier ran or was skipped.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail(){ echo "FAIL: $1"; exit 1; }

# ── STATIC ───────────────────────────────────────────────────────────────────
python3 - "$ROOT" <<'PY' || exit 1
import json, sys
root = sys.argv[1]
s = json.load(open(root + "/plugin/.mcp.json"))["mcpServers"]["heartbeat"]
assert s["command"] == "hb" and "mcp-serve" in s["args"], f".mcp.json does not wire hb mcp-serve: {s}"
mk = json.load(open(root + "/.claude-plugin/marketplace.json"))
names = {p.get("name") for p in mk.get("plugins", [])}
assert "heartbeat" in names, f"marketplace.json does not list the heartbeat plugin: {names}"
PY
echo "  static: .mcp.json wires hb mcp-serve; marketplace lists heartbeat"

# ── CODEX-LIVE (conditional, isolated, offline) ──────────────────────────────
if command -v codex >/dev/null 2>&1; then
  ch="$(mktemp -d)"; trap 'rm -rf "$ch"' EXIT
  CODEX_HOME="$ch" timeout 40 codex plugin marketplace add "$ROOT" --json >/dev/null 2>&1 \
    || fail "codex plugin marketplace add (isolated) failed"
  CODEX_HOME="$ch" timeout 60 codex plugin add heartbeat@heartbeat-marketplace --json >/dev/null 2>&1 \
    || fail "codex plugin add heartbeat (isolated) failed"
  mcps="$(CODEX_HOME="$ch" timeout 30 codex mcp list --json 2>/dev/null)"
  printf '%s' "$mcps" | python3 -c "
import json, sys
servers = json.load(sys.stdin)
hb = [s for s in servers if s.get('name') == 'heartbeat']
assert hb, 'codex mcp list has no heartbeat server after install'
t = hb[0].get('transport', {})
assert t.get('command') == 'hb' and 'mcp-serve' in (t.get('args') or []), f'heartbeat server not wired to hb mcp-serve: {t}'
" || fail "codex install did not register the heartbeat MCP server (command hb / args mcp-serve)"
  echo "  codex-live: install registered the heartbeat stdio server (hb mcp-serve) in an isolated CODEX_HOME"
  echo "PLUGIN-MCP-OK: the plugin registers hb mcp-serve (static + codex-live)."
else
  echo "  codex-live: skipped (codex not on PATH)"
  echo "PLUGIN-MCP-OK: the plugin registers hb mcp-serve (static; codex-live skipped)."
fi
