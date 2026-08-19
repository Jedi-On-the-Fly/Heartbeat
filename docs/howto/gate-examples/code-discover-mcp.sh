#!/usr/bin/env bash
# Proof: the MCP server exposes the `code_discover` tool, and its answer EQUALS the discovery
# function — the expected value is DERIVED in-process by importing the real adapter (not hardcoded),
# proving the tool calls the real library. Drives the REAL `hb mcp-serve` JSON-RPC server. Prints
# MCP-DISCOVER-OK. Fails before the tool is registered.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
python3 -m heartbeat.cli init "$work/p" >/dev/null 2>&1

python3 - "$ROOT" "$work/p" <<'PY'
import json, os, subprocess, sys
root, proj = sys.argv[1], sys.argv[2]
FX = os.path.join(root, "plugin/adapters/code/fixtures")
codemap = json.load(open(os.path.join(FX, "discover-codemap.json")))
entries, direction = ["repo"], "dependents"
from heartbeat.adapters.code.codegraph_discover import discover
exp = discover(codemap, entries, direction)        # DERIVED from the real adapter, not hardcoded

srv = subprocess.Popen([sys.executable, "-m", "heartbeat.cli", "mcp-serve", "--dir", proj],
                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
_id = [0]
def call(method, params=None):
    _id[0] += 1
    srv.stdin.write(json.dumps({"jsonrpc": "2.0", "id": _id[0], "method": method, "params": params or {}}) + "\n")
    srv.stdin.flush()
    return json.loads(srv.stdout.readline())
def fail(m):
    srv.terminate(); print("FAIL:", m); sys.exit(1)

call("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "t", "version": "0"}})
names = {t["name"] for t in call("tools/list").get("result", {}).get("tools", [])}
if "code_discover" not in names:
    fail(("tools/list lacks code_discover", sorted(names)))

r = call("tools/call", {"name": "code_discover",
                        "arguments": {"codemap": codemap, "entries": entries, "direction": direction}})
try: got = json.loads(r["result"]["content"][0]["text"])
except Exception: fail(("code_discover bad envelope", r))
if got != exp: fail(("code_discover tool != adapter", got, exp))

srv.terminate()
print("driver-ok")
PY
[ $? -eq 0 ] || { echo "FAIL: MCP code_discover tool absent or mismatched"; exit 1; }
echo "MCP-DISCOVER-OK"
