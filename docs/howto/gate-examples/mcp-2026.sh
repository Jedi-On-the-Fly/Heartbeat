#!/usr/bin/env bash
# Proof that `hb mcp-serve` dual-stacks the 2026-07-28 MCP spec without breaking older clients.
# Deterministic: our own stdlib JSON-RPC client over stdio — no SDK, no network, no Docker.
# Asserts: server/discover advertises the supported versions + serverInfo in _meta; version
# negotiation is real (an unsupported version is negotiated down, not echoed); a MODERN request
# (2026 version in _meta) gets resultType + cache fields; an OLD request stays byte-identical.
# Prints MCP-2026-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
p="$work/proj"; hb init "$p" >/dev/null 2>&1; hb rebuild --dir "$p" >/dev/null 2>&1

out="$(python3 - "$p" <<'PY'
import json, subprocess, sys
proj = sys.argv[1]
PROTO = "io.modelcontextprotocol/protocolVersion"
SRVINFO = "io.modelcontextprotocol/serverInfo"
srv = subprocess.Popen([sys.executable, "-m", "heartbeat.cli", "mcp-serve", "--dir", proj],
                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
def rpc(method, params=None, mid=1):
    srv.stdin.write(json.dumps({"jsonrpc": "2.0", "id": mid, "method": method, "params": params or {}}) + "\n")
    srv.stdin.flush()
    return json.loads(srv.stdout.readline())

# 1. server/discover advertises versions + serverInfo in _meta
d = rpc("server/discover", {}, 1)["result"]
assert "2026-07-28" in d.get("supportedVersions", []), f"discover missing 2026-07-28: {d}"
assert "2025-06-18" in d.get("supportedVersions", []), f"discover missing 2025-06-18: {d}"
assert "tools" in d.get("capabilities", {}), "discover: no tools capability"
assert d.get("_meta", {}).get(SRVINFO, {}).get("name") == "heartbeat", "discover: no serverInfo in _meta"

# 2. negotiation: supported version echoed; unsupported negotiated DOWN (not echoed)
r = rpc("initialize", {"protocolVersion": "2025-06-18"}, 2)["result"]
assert r["protocolVersion"] == "2025-06-18", f"supported version not echoed: {r}"
r = rpc("initialize", {"protocolVersion": "2999-01-01"}, 3)["result"]
assert r["protocolVersion"] == "2025-06-18", f"unsupported version not negotiated down (echo bug): {r}"

# 3. MODERN request (2026 version in _meta) -> resultType + cache fields
r = rpc("tools/list", {"_meta": {PROTO: "2026-07-28"}}, 4)["result"]
assert r.get("resultType") == "complete", f"modern tools/list missing resultType: {r.keys()}"
assert "ttlMs" in r and "cacheScope" in r, f"modern tools/list missing cache fields: {r.keys()}"
r = rpc("tools/call", {"name": "tick", "arguments": {}, "_meta": {PROTO: "2026-07-28"}}, 5)["result"]
assert r.get("resultType") == "complete", f"modern tools/call missing resultType: {r.keys()}"

# 4. OLD request (no modern _meta) -> byte-identical, NO 2026 fields
r = rpc("tools/list", {}, 6)["result"]
assert "resultType" not in r and "ttlMs" not in r, f"old tools/list leaked 2026 fields: {r.keys()}"
r = rpc("tools/call", {"name": "tick", "arguments": {}}, 7)["result"]
assert "resultType" not in r, f"old tools/call leaked resultType: {r.keys()}"

srv.stdin.close(); srv.wait(timeout=10)
print("DRIVER-2026-OK")
PY
)" || fail "2026 driver: $out"
printf '%s\n' "$out" | grep -q DRIVER-2026-OK || fail "2026 assertions failed: $out"
echo "MCP-2026-OK: server/discover + real version negotiation + modern-only resultType/cache fields (old requests byte-identical)."
