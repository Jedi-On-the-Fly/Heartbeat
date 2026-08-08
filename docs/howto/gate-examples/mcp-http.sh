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
def wait_port(proc):                               # skip any stray stderr noise until readiness
    for _ in range(30):
        line = proc.stderr.readline()
        if not line:
            break
        m = re.search(r"listening on (\S+):(\d+)", line)
        if m:
            return m.group(1), m.group(2)
    raise AssertionError("no readiness line")
srv = subprocess.Popen([sys.executable, "-m", "heartbeat.cli", "mcp-serve", "--http",
                        "--host", "127.0.0.1", "--port", "0", "--dir", proj],
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
h, pt = wait_port(srv)                              # readiness signal (printed AFTER bind)
base = f"http://{h}:{pt}"

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

# ── SECURITY ─────────────────────────────────────────────────────────────────
sec="$(python3 - "$p" <<'PY'
import json, re, subprocess, sys, urllib.request, urllib.error
proj = sys.argv[1]
def wait_port(proc):                               # skip any stray stderr noise until readiness
    for _ in range(30):
        line = proc.stderr.readline()
        if not line:
            break
        m = re.search(r"listening on (\S+):(\d+)", line)
        if m:
            return m.group(1), m.group(2)
    raise AssertionError("no readiness line")
srv = subprocess.Popen([sys.executable, "-m", "heartbeat.cli", "mcp-serve", "--http",
                        "--host", "127.0.0.1", "--port", "0", "--dir", proj],
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
h, pt = wait_port(srv)
base = f"http://{h}:{pt}"
def post(headers):
    req = urllib.request.Request(base, data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": "server/discover", "params": {}}).encode(),
                                 headers={"Content-Type": "application/json", **headers}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
try:
    # 1. cross-origin POST -> 403 (DNS-rebinding defence)
    code, _ = post({"Origin": "http://evil.example"})
    assert code == 403, f"cross-origin not rejected: {code}"
    # 2. no-Origin (non-browser) and loopback Origin -> accepted
    code, _ = post({})
    assert code == 200, f"no-Origin rejected: {code}"
    code, _ = post({"Origin": f"http://localhost"})
    assert code == 200, f"loopback Origin rejected: {code}"
    # allowlist must be an exact host match, not a prefix — these attacker domains must be rejected
    for bad in ("http://127.0.0.1.evil.com", "http://localhost.evil.com"):
        code, _ = post({"Origin": bad})
        assert code == 403, f"origin allowlist bypass accepted ({bad}): {code}"
    # 3. modern header -> a modern result over HTTP (resultType present)
    req = urllib.request.Request(base, data=json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                                                        "params": {"name": "tick", "arguments": {}}}).encode(),
                                 headers={"Content-Type": "application/json", "mcp-protocol-version": "2026-07-28",
                                          "mcp-method": "tools/call", "mcp-name": "tick"}, method="POST")
    with urllib.request.urlopen(req, timeout=10) as r:
        assert json.loads(r.read().decode())["result"].get("resultType") == "complete", "modern HTTP header did not yield resultType"
finally:
    srv.terminate(); srv.wait(timeout=10)

# 4. non-loopback bind WITHOUT --allow-remote refuses to start
r = subprocess.run([sys.executable, "-m", "heartbeat.cli", "mcp-serve", "--http", "--host", "0.0.0.0",
                    "--port", "0", "--dir", proj], capture_output=True, text=True, timeout=10)
assert r.returncode != 0, "non-loopback bind without --allow-remote did NOT refuse"
assert "allow-remote" in r.stderr, f"refusal message missing: {r.stderr!r}"
print("DRIVER-HTTP-SECURE-OK")
PY
)" || fail "http security driver: $sec"
printf '%s\n' "$sec" | grep -q DRIVER-HTTP-SECURE-OK || fail "http security assertions failed: $sec"
echo "MCP-HTTP-SECURE-OK: cross-origin POST rejected (403); no-Origin/loopback accepted; modern header yields resultType; non-loopback bind refused without --allow-remote."
