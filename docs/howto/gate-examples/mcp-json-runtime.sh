#!/usr/bin/env bash
# Proof (C7,R9): the MCP entry is honest about its runtime, and the command-surface decision is realized.
# C7: .mcp.json declares the server AND a doc states it needs the Python `hb` (a node-only install can't
# run `hb mcp-serve`). R9: EITHER a plugin commands/ dir registers the verbs, OR the heartbeat skill
# documents that /heartbeat is a skill (not commands/) — so the absence is intentional. Prints
# MCP-JSON-RUNTIME-OK. Fails today. Deterministic.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fail(){ echo "FAIL: $1"; exit 1; }
MJ="$ROOT/plugin/.mcp.json"
[ -f "$MJ" ] || fail "no plugin/.mcp.json"
grep -q 'mcp-serve' "$MJ" || fail ".mcp.json does not declare the mcp server"
# C7: a doc must state — specifically — that a node-only install cannot run the MCP server (hb mcp-serve),
# so it requires the Python hb. A specific phrase (not a broad mcp+python co-occurrence) so the gate has teeth.
grep -rqiE --include='*.md' 'node-only.*(cannot|can.?t|can not) run.*mcp-serve' "$ROOT/docs" "$ROOT/INSTALL.md" \
  || fail "no doc states a node-only install cannot run the MCP server (hb mcp-serve) — requires the Python hb"
# R9: commands/ dir OR the skill documents the skill-not-commands design
if [ -d "$ROOT/plugin/commands" ]; then :; else
  grep -rqiE 'not a .?plugin/commands|provided by [*]{0,2}this skill|is a (claude code )?skill' "$ROOT/plugin/skills/heartbeat/SKILL.md" \
    || fail "no plugin/commands/ AND the heartbeat skill does not document the skill-not-commands design (R9 undecided)"
fi
echo "MCP-JSON-RUNTIME-OK"
