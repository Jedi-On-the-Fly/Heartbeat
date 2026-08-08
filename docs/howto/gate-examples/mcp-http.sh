#!/usr/bin/env bash
# Proof for the optional streamable-HTTP transport of `hb mcp-serve`: a REAL HTTP JSON-RPC client
# (urllib) drives the real `hb mcp-serve --http` over localhost — no model, no external network, no
# Docker. Asserts the handshake, tools/list, a read tool matching the CLI, and an act tool (gate)
# recording via the log over HTTP. Prints MCP-HTTP-OK. Uses --port 0 (ephemeral) and reads the
# bound port from the server's stderr readiness line, so there is no fixed-port flake.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# a project with one passing behavioral gate criterion (grep a file that exists)
p="$work/proj"; hb init "$p" >/dev/null 2>&1
python3 - "$p" <<'PY'
import json, sys
d = sys.argv[1]
json.dump({"phases": [{"id": "P0", "gate_entry": None, "gate_exit": "GATE_P0",
                       "tasks": [{"id": "T1", "title": "produce out.txt"}]}],
           "gates": {"GATE_P0": {"desc": "g", "criteria": [{"id": "c", "cmd": "grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},
          open(d + "/.hb/dag.json", "w"))
PY
hb rebuild --dir "$p" >/dev/null 2>&1; echo ok > "$p/out.txt"

out="$(python3 - "$p" <<'PY'
import json, os, re, subprocess, sys, urllib.request
proj = sys.argv[1]
srv = subprocess.Popen([sys.executable, "-m", "heartbeat.cli", "mcp-serve", "--http",
                        "--host", "127.0.0.1", "--port", "0", "--dir", proj],
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
line = srv.stderr.readline()                       # readiness signal (printed AFTER bind)
m = re.search(r"listening on (\S+):(\d+)", line)
assert m, f"no readiness line: {line!r}"
base = f"http://{m.group(1)}:{m.group(2)}"

def rpc(method, params=None, mid=1):
    req = urllib.request.Request(base, data=json.dumps(
        {"jsonrpc": "2.0", "id": mid, "method": method, "params": params or {}}).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode())
def tool(name, args=None, mid=9):
    return json.loads(rpc("tools/call", {"name": name, "arguments": args or {}}, mid)["result"]["content"][0]["text"])
def cli(*a):
    return subprocess.run([sys.executable, "-m", "heartbeat.cli", *a, "--dir", proj], capture_output=True, text=True).stdout
def nostamp(d): d.pop("last_updated", None); return d

try:
    res = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}}, 1)["result"]
    assert res.get("serverInfo", {}).get("name") == "heartbeat", "handshake: no serverInfo"
    assert "tools" in res.get("capabilities", {}), "handshake: no tools capability"
    names = {t["name"] for t in rpc("tools/list", {}, 2)["result"]["tools"]}
    for n in ("tick", "state", "gate"):
        assert n in names, f"tools/list missing {n}"
    assert nostamp(tool("state")) == nostamp(json.loads(cli("state"))), "state tool != hb state (HTTP)"
    g = tool("gate", {"gate": "GATE_P0"})
    assert g.get("status") == "passed", f"gate over HTTP did not pass: {g}"
    assert "gate_passed" in open(os.path.join(proj, ".hb", "events.jsonl")).read(), "no gate_passed in events.jsonl"
    assert "P0" in json.loads(cli("state")).get("completed_phases", []), "phase did not advance over HTTP"
    print("DRIVER-HTTP-OK")
finally:
    srv.terminate(); srv.wait(timeout=10)
PY
)" || fail "http driver: $out"
printf '%s\n' "$out" | grep -q DRIVER-HTTP-OK || fail "http assertions failed: $out"
echo "MCP-HTTP-OK: a real urllib HTTP client drove hb mcp-serve --http (handshake + tools/list + state matching the CLI + a gate recorded via the log)."
