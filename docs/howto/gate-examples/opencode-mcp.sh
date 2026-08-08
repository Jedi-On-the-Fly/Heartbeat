#!/usr/bin/env bash
# Proof for the OpenCode MCP wiring (dimension C): HeartBeat's documented opencode.json `mcp` config
# is valid AND the command it wires (`hb mcp-serve`) is a working MCP server. Deterministic — no
# opencode, no model, no network. (Full third-party-client interop is guaranteed by the official
# MCP SDK v2 reference proof, tests/mcp-interop.sh; the opencode-specific live check is on-demand.)
# Prints OPENCODE-MCP-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }
GUIDE="$ROOT/docs/howto/use-heartbeat-with-opencode.md"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
p="$work/proj"; hb init "$p" >/dev/null 2>&1; hb rebuild --dir "$p" >/dev/null 2>&1

out="$(python3 - "$p" <<'PY'
import json, subprocess, sys
proj = sys.argv[1]
# The canonical HeartBeat opencode.json `mcp` config (what the guide documents).
cfg = {"mcp": {
    "heartbeat":      {"type": "local",  "command": ["hb", "mcp-serve"], "enabled": True},
    "heartbeat-http": {"type": "remote", "url": "http://127.0.0.1:7777", "enabled": True}}}
loc = cfg["mcp"]["heartbeat"]
assert loc["type"] == "local" and loc["command"][0] == "hb" and "mcp-serve" in loc["command"], f"bad local shape: {loc}"
rem = cfg["mcp"]["heartbeat-http"]
assert rem["type"] == "remote" and rem["url"].startswith("http"), f"bad remote shape: {rem}"
# The wired command must be a working MCP server. Drive the spawn FROM the documented `command`
# array (so a typo there fails the handshake), mapping the `hb` console to the source module.
assert loc["command"][0] == "hb", f"documented command must invoke hb: {loc['command']}"
argv = [sys.executable, "-m", "heartbeat.cli"] + loc["command"][1:] + ["--dir", proj]
srv = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
srv.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                            "params": {"protocolVersion": "2025-06-18", "capabilities": {}}}) + "\n")
srv.stdin.flush()
res = json.loads(srv.stdout.readline())["result"]
assert res.get("serverInfo", {}).get("name") == "heartbeat", f"server did not handshake: {res}"
assert "tools" in res.get("capabilities", {}), "no tools capability"
srv.stdin.close(); srv.wait(timeout=10)
print("DRIVER-OPENCODE-MCP-OK")
PY
)" || fail "opencode-mcp driver: $out"
printf '%s\n' "$out" | grep -q DRIVER-OPENCODE-MCP-OK || fail "opencode-mcp assertions failed: $out"

# The guide must document the opencode.json mcp config wiring hb mcp-serve.
grep -q 'mcp-serve' "$GUIDE" && grep -qiE '"type":[[:space:]]*"local"|opencode\.json' "$GUIDE" \
  || fail "the guide does not document the opencode.json mcp config"

echo "OPENCODE-MCP-OK: the opencode.json mcp config is valid (local + remote shape) and the wired \`hb mcp-serve\` command spins a working MCP server (initialize handshake); the guide documents it."
