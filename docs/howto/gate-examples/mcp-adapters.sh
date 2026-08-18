#!/usr/bin/env bash
# Proof: the MCP server exposes the domain-adapter tools `deplint` and `code_context`, and their
# answers EQUAL the Python adapter functions — the expected values are DERIVED in-process by
# importing the real adapters (not hardcoded), proving the tools call the real library. Drives the
# REAL `hb mcp-serve` JSON-RPC server (one server process). Fails before the tools are registered.
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
dag     = json.load(open(os.path.join(FX, "missing.dag.json")))
codemap = json.load(open(os.path.join(FX, "missing.codemap.json")))
ctxmap  = json.load(open(os.path.join(FX, "context.codemap.json")))
from heartbeat.adapters.code.deplint import deplint as dl
from heartbeat.adapters.code.codegraph_context import context_for
exp_deplint = dl(dag, codemap)                 # DERIVED from the real adapter, not hardcoded
exp_ctx     = context_for(ctxmap, "TA")

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
if not ({"deplint", "code_context"} <= names):
    fail(("tools/list lacks deplint/code_context", sorted(names)))

r = call("tools/call", {"name": "deplint", "arguments": {"dag": dag, "codemap": codemap}})
try: got = json.loads(r["result"]["content"][0]["text"])
except Exception: fail(("deplint bad envelope", r))
if got != exp_deplint: fail(("deplint tool != adapter", got, exp_deplint))

r = call("tools/call", {"name": "code_context", "arguments": {"codemap": ctxmap, "task": "TA"}})
try: got = json.loads(r["result"]["content"][0]["text"])
except Exception: fail(("code_context bad envelope", r))
if got != exp_ctx: fail(("code_context tool != adapter", got, exp_ctx))

srv.terminate()
print("driver-ok")
PY
[ $? -eq 0 ] || { echo "FAIL: MCP adapter tools absent or mismatched"; exit 1; }
echo "MCP-ADAPTERS-OK"
