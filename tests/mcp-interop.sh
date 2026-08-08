#!/usr/bin/env bash
# ON-DEMAND real-client interop proof: the OFFICIAL MCP Python SDK v2 client drives `hb mcp-serve`
# over stdio and negotiates 2026-07-28 with it. This tier needs a venv + `pip install mcp>=2`
# (network), so — like the framework Docker tier — it is NOT a core-suite gate: it self-skips
# cleanly (INTEROP-SKIPPED, exit 0) when the SDK can't be installed. The server stays stdlib-only;
# the SDK lives only in this throwaway venv. Prints MCP-INTEROP-OK on a real-client success.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skip(){ echo "INTEROP-SKIPPED: $1"; exit 0; }
fail(){ echo "FAIL: $1"; exit 1; }
command -v python3 >/dev/null 2>&1 || skip "python3 absent"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
python3 -m venv "$tmp/venv" >/dev/null 2>&1 || skip "python venv unavailable"
"$tmp/venv/bin/pip" install -q "mcp>=2" >/dev/null 2>&1 || skip "mcp SDK not installable (offline?)"

proj="$tmp/proj"
PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 python3 -m heartbeat.cli init "$proj" >/dev/null 2>&1

out="$(ROOT="$ROOT" "$tmp/venv/bin/python" - "$proj" <<'PY'
import asyncio, json, os, subprocess, sys
proj = sys.argv[1]; root = os.environ["ROOT"]
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
env = dict(os.environ, PYTHONPATH=os.path.join(root, "py", "src"), HB_NO_GIT="1")

async def main():
    # the server runs stdlib-only under this same python; the SDK is only imported by the CLIENT
    params = StdioServerParameters(command=sys.executable,
                                   args=["-m", "heartbeat.cli", "mcp-serve", "--dir", proj], env=env)
    async with stdio_client(params) as (r, w):
        async with ClientSession(r, w) as session:
            disc = await session.discover()
            assert "2026-07-28" in disc.supported_versions, f"discover: {disc.supported_versions}"
            assert session.protocol_version == "2026-07-28", f"client did not negotiate 2026: {session.protocol_version}"
            names = {t.name for t in (await session.list_tools()).tools}
            assert {"tick", "gate", "state"} <= names, f"tools: {names}"
            got = json.loads((await session.call_tool("state", {})).content[0].text)
            ref = json.loads(subprocess.run([sys.executable, "-m", "heartbeat.cli", "state", "--dir", proj],
                                            env=env, capture_output=True, text=True).stdout)
            got.pop("last_updated", None); ref.pop("last_updated", None)
            assert got == ref, "state tool != hb state"
    print("DRIVER-INTEROP-OK")

asyncio.run(main())
PY
)" || fail "interop driver: $out"
printf '%s\n' "$out" | grep -q DRIVER-INTEROP-OK || fail "interop assertions failed: $out"
echo "MCP-INTEROP-OK: the official MCP SDK v2 client negotiated 2026-07-28 with hb mcp-serve over stdio (discover + list_tools + call_tool matching the CLI)."
