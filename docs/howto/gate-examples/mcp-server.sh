#!/usr/bin/env bash
# Proof for "Drive HeartBeat over MCP": the real `hb mcp-serve` stdio server, driven by an actual
# JSON-RPC 2.0 client over stdin/stdout — no model, no network, no Docker. It asserts:
#   READ  — the handshake is valid, tools/list carries the read tools, and tools/call tick/next/
#           state return exactly what the CLI returns (proving the tools call the real library).
#   ACT   — a gate call records gate_passed VIA THE LOG (the event lands in events.jsonl) and the
#           phase advances; a failing gate does NOT advance; and after start/done, `hb rebuild`
#           reproduces the identical state (the server never side-writes state.json — the
#           mutate-only-through-the-log invariant).
# Prints MCP-READ-OK, then MCP-ACT-OK, then MCP-INVARIANT-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# ── READ ─────────────────────────────────────────────────────────────────────
p="$work/proj"; hb init "$p" >/dev/null 2>&1; hb rebuild --dir "$p" >/dev/null 2>&1

cat > "$work/read.py" <<'PY'
import json, subprocess, sys
proj = sys.argv[1]
srv = subprocess.Popen([sys.executable, "-m", "heartbeat.cli", "mcp-serve", "--dir", proj],
                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
def call(method, params=None, mid=1):
    srv.stdin.write(json.dumps({"jsonrpc": "2.0", "id": mid, "method": method, "params": params or {}}) + "\n")
    srv.stdin.flush()
    return json.loads(srv.stdout.readline())
def notify(method, params=None):
    srv.stdin.write(json.dumps({"jsonrpc": "2.0", "method": method, "params": params or {}}) + "\n")
    srv.stdin.flush()
def cli(*args):
    return subprocess.run([sys.executable, "-m", "heartbeat.cli", *args, "--dir", proj],
                          capture_output=True, text=True).stdout.strip()
def tool(name, args=None, mid=9):
    r = call("tools/call", {"name": name, "arguments": args or {}}, mid)
    return json.loads(r["result"]["content"][0]["text"])

# 1. handshake
res = call("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}}, 1).get("result", {})
assert res.get("serverInfo", {}).get("name") == "heartbeat", "handshake: no serverInfo"
assert "tools" in res.get("capabilities", {}), "handshake: no tools capability"
assert res.get("protocolVersion"), "handshake: no protocolVersion"
notify("notifications/initialized")
# 2. tools/list carries the read tools
names = {t["name"] for t in call("tools/list", {}, 2)["result"]["tools"]}
for n in ("tick", "next", "state", "report", "diagnose"):
    assert n in names, f"tools/list missing {n}"
# 3. read tools return exactly what the CLI returns (real library, not canned)
def nostamp(d): d.pop("last_updated", None); return d   # the one nondeterministic field
assert nostamp(tool("state")) == nostamp(json.loads(cli("state"))), "state tool != hb state"
assert tool("next") == json.loads(cli("next")), "next tool != hb next"
assert tool("tick").get("reason") == json.loads(cli("tick")).get("reason"), "tick reason != hb tick"
srv.stdin.close(); srv.wait(timeout=10)
print("DRIVER-READ-OK")
PY
out="$(python3 "$work/read.py" "$p" 2>&1)" || fail "read driver: $out"
printf '%s\n' "$out" | grep -q DRIVER-READ-OK || fail "read assertions failed: $out"
echo "MCP-READ-OK: hb mcp-serve completes the JSON-RPC handshake, lists tools, and answers tick/next/state matching the CLI."

# ── ACT ──────────────────────────────────────────────────────────────────────
# A project with one behavioral gate criterion (grep a file). `pass` writes the file; `fail` doesn't.
mkact(){ local d; d="$work/$1proj"; hb init "$d" >/dev/null 2>&1
  python3 - "$d" <<'PY'
import json, sys
d = sys.argv[1]
json.dump({"phases": [{"id": "P0", "gate_entry": None, "gate_exit": "GATE_P0",
                       "tasks": [{"id": "T1", "title": "produce out.txt"}]}],
           "gates": {"GATE_P0": {"desc": "g", "criteria": [{"id": "c", "cmd": "grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},
          open(d + "/.hb/dag.json", "w"))
PY
  hb rebuild --dir "$d" >/dev/null 2>&1
  [ "$1" = pass ] && echo ok > "$d/out.txt"
  echo "$d"; }
pp="$(mkact pass)"; np="$(mkact fail)"

cat > "$work/act.py" <<'PY'
import json, subprocess, sys, os
pp, np = sys.argv[1], sys.argv[2]
def server(proj):
    return subprocess.Popen([sys.executable, "-m", "heartbeat.cli", "mcp-serve", "--dir", proj],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
def rpc(s, method, params=None, mid=1):
    s.stdin.write(json.dumps({"jsonrpc": "2.0", "id": mid, "method": method, "params": params or {}}) + "\n"); s.stdin.flush()
    return json.loads(s.stdout.readline())
def init(s): rpc(s, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {}}, 1)
def tool(s, name, args=None, mid=9):
    return json.loads(rpc(s, "tools/call", {"name": name, "arguments": args or {}}, mid)["result"]["content"][0]["text"])
def events(proj):
    p = os.path.join(proj, ".hb", "events.jsonl"); return open(p).read() if os.path.exists(p) else ""
def cli(*a):
    return subprocess.run([sys.executable, "-m", "heartbeat.cli", *a], capture_output=True, text=True).stdout

# passing gate: the tool records gate_passed VIA THE LOG and the phase advances
s = server(pp); init(s)
g = tool(s, "gate", {"gate": "GATE_P0"})
st = tool(s, "state"); s.stdin.close(); s.wait(timeout=10)
assert g.get("status") == "passed", f"gate tool did not pass a passing gate: {g}"
assert "gate_passed" in events(pp), "gate tool did not append gate_passed to events.jsonl"
assert "P0" in st.get("completed_phases", []), "phase did not advance after a passing gate"

# negative control: a failing gate returns blocked and does NOT advance
s = server(np); init(s)
g = tool(s, "gate", {"gate": "GATE_P0"})
st = tool(s, "state"); s.stdin.close(); s.wait(timeout=10)
assert g.get("status") == "blocked", f"control: failing gate not blocked: {g}"
assert "P0" not in st.get("completed_phases", []), "control: phase advanced on a FAILING gate"
print("DRIVER-ACT-OK")

# invariant: start/done via the tools mutate the log; state.json on disk stays a pure projection
s = server(pp); init(s)
tool(s, "start", {"task": "T1"}); tool(s, "done", {"task": "T1"})
s.stdin.close(); s.wait(timeout=10)
assert "task_done" in events(pp), "done tool did not append task_done to events.jsonl"
st_disk = json.load(open(os.path.join(pp, ".hb", "state.json")))
st_proj = json.loads(cli("state", "--dir", pp))     # recomputed straight from the event log
st_disk.pop("last_updated", None); st_proj.pop("last_updated", None)   # the one nondeterministic field
assert st_disk == st_proj, "state.json on disk diverges from the event-log projection — the server side-wrote it"
print("DRIVER-INVARIANT-OK")
PY
out="$(python3 "$work/act.py" "$pp" "$np" 2>&1)" || fail "act driver: $out"
printf '%s\n' "$out" | grep -q DRIVER-ACT-OK || fail "act assertions failed: $out"
echo "MCP-ACT-OK: a gate tool records gate_passed via the log and advances the phase; a failing gate does not (negative control)."
printf '%s\n' "$out" | grep -q DRIVER-INVARIANT-OK || fail "invariant assertions failed: $out"
echo "MCP-INVARIANT-OK: act tools mutate only through the log — state.json stays a pure projection of events.jsonl."
