#!/usr/bin/env bash
# The MCP `tick` tool is the always-on channel for an interactive MCP client (OpenCode, or any
# MCP-capable agent driving `hb mcp-serve`). Like the SessionStart hook (T143), it must teach the
# client to DRIVE the loop, not react to one tick. Driving the REAL server over JSON-RPC, this
# asserts: (A) the `tick` tool's DESCRIPTION carries a coherent drive-loop instruction — call `tick`
# again after acting, framed as a loop, until all_done or a human-needed reason
# (gate_blocked/build_stuck/deadlock/review_stuck); (B) a tools/call `tick` on a project with pending
# work returns data.next (a call-again nudge); (C) on an all_done project it returns NO next (don't
# tell it to loop when it must stop). Prints MCP-DRIVES-LOOP-OK. `--selftest` proves each check is
# individually load-bearing (a near-miss failing exactly one is rejected; a good shape passes) →
# SELFTEST-OK.
#
# SCOPE (honest): anti-DRIFT presence-of-instruction on the tick tool's first-party metadata — it
# defends against the tool regressing to react-only. It does not adjudicate whether the LLM obeys
# (that is the on-demand live tier), and a deterministic grep cannot judge semantic contradiction.
# MCP is Python-only (no node MCP server) → this surface has no parity twin.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail(){ echo "FAIL: $1"; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# Shared assertion logic — used by BOTH the live run and the selftest, so the teeth exercise the
# exact predicates the live run trusts.
cat > "$work/asserts.py" <<'PY'
import re

def desc_fail(text):
    """Return the set of drive-loop checks a tick-tool DESCRIPTION fails (empty = passes)."""
    t = re.sub(r"\s+", " ", text).lower()
    bad = set()
    # B1: a re-invoke instruction — a call/run/invoke verb next to the tick tool
    if not re.search(r"(call|run|invoke).{0,25}tick", t):            bad.add("B1")
    # B2: framed as a loop
    if not re.search(r"(again|loop|repeat|keep (going|looping))", t): bad.add("B2")
    # B3: success stop
    if "all_done" not in t:                                          bad.add("B3")
    # B4: a human-needed stop reason
    if not re.search(r"gate_blocked|build_stuck|deadlock|review_stuck", t): bad.add("B4")
    return bad

def payload_ok(r):
    """A tick RESULT must nudge (data.next → call tick again) on work-advancing reasons, and must
    NOT nudge on terminal ones (all_done / not-woken)."""
    d = r.get("data", {}) or {}
    reason = d.get("reason")
    if r.get("wakeAgent") and reason in ("next_task", "gate_pending", "review_pending"):
        nx = str(d.get("next", "")).lower()
        return bool(nx) and "tick" in nx and ("again" in nx or "loop" in nx)
    if reason in ("all_done", "project_complete") or not r.get("wakeAgent"):
        return "next" not in d
    return True
PY

if [ "${1:-}" = "--selftest" ]; then
  python3 - "$work" <<'PY' || fail "selftest"
import sys; sys.path.insert(0, sys.argv[1])
from asserts import desc_fail, payload_ok

good = ("Run one Stage-A tick and return the next action. To run a project, call `tick` again after "
        "acting and keep looping until all_done or a human-needed reason "
        "(gate_blocked / build_stuck / deadlock / review_stuck).")
# each near-miss fails EXACTLY one description check
misses = {
    "B1": "Keep looping until all_done or gate_blocked; the tick is over there.",       # no call/run near tick
    "B2": "Call `tick` after each action until all_done or gate_blocked.",              # no loop word
    "B3": "Call `tick` again in a loop; stop for gate_blocked or build_stuck.",         # no all_done
    "B4": "Call `tick` again in a loop until all_done.",                                # no human reason
}
assert desc_fail(good) == set(), f"good description wrongly rejected: {desc_fail(good)}"
for k, text in misses.items():
    assert desc_fail(text) == {k}, f"near-miss {k} should fail exactly {{{k}}}, got {desc_fail(text)}"

# payload nudge rules — each near-miss rejected, each good accepted
assert payload_ok({"wakeAgent": True,  "data": {"reason": "next_task", "next": "call tick again after you act"}})
assert not payload_ok({"wakeAgent": True, "data": {"reason": "next_task"}}), "advancing reason with no next wrongly accepted"
assert not payload_ok({"wakeAgent": True, "data": {"reason": "all_done", "next": "call tick again"}}), "all_done WITH a nudge wrongly accepted"
assert payload_ok({"wakeAgent": True,  "data": {"reason": "all_done"}})
print("TEETH-OK")
PY
  echo "SELFTEST-OK: each of A(desc B1–B4)/B/C is individually load-bearing; a real drive-shape passes."
  exit 0
fi

# ── LIVE: drive the real hb mcp-serve ─────────────────────────────────────────
hb(){ python3 -m heartbeat.cli "$@"; }
# a project with pending work (fresh init → template DAG's first tick is next_task)
pend="$work/pend"; hb init "$pend" >/dev/null 2>&1; hb rebuild --dir "$pend" >/dev/null 2>&1
# a project we can drive to all_done (one phase, one task, a file-grep gate)
done="$work/done"; hb init "$done" >/dev/null 2>&1
python3 - "$done" <<'PY'
import json, sys
d = sys.argv[1]
json.dump({"phases": [{"id": "P0", "gate_entry": None, "gate_exit": "GATE_P0",
                       "tasks": [{"id": "T1", "title": "produce out.txt"}]}],
           "gates": {"GATE_P0": {"desc": "g", "criteria": [{"id": "c", "cmd": "grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},
          open(d + "/.hb/dag.json", "w"))
PY
echo ok > "$done/out.txt"; hb rebuild --dir "$done" >/dev/null 2>&1

cat > "$work/live.py" <<'PY'
import json, os, subprocess, sys
sys.path.insert(0, sys.argv[1]); from asserts import desc_fail, payload_ok
pend, done = sys.argv[2], sys.argv[3]

def server(proj):
    return subprocess.Popen([sys.executable, "-m", "heartbeat.cli", "mcp-serve", "--dir", proj],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
def rpc(s, method, params=None, mid=1):
    s.stdin.write(json.dumps({"jsonrpc": "2.0", "id": mid, "method": method, "params": params or {}}) + "\n"); s.stdin.flush()
    return json.loads(s.stdout.readline())
def init(s): rpc(s, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {}}, 1)
def tool(s, name, args=None, mid=9):
    return json.loads(rpc(s, "tools/call", {"name": name, "arguments": args or {}}, mid)["result"]["content"][0]["text"])

# (A) the tick tool DESCRIPTION teaches driving
s = server(pend); init(s)
desc = next(t["description"] for t in rpc(s, "tools/list", {}, 2)["result"]["tools"] if t["name"] == "tick")
missing = desc_fail(desc)
assert not missing, f"tick tool description does not teach driving (fails {sorted(missing)}): {desc!r}"

# (B) a tick on pending work carries the call-again nudge
r = tool(s, "tick"); s.stdin.close(); s.wait(timeout=10)
assert r.get("data", {}).get("reason") in ("next_task", "gate_pending", "review_pending"), f"expected work-advancing reason, got {r}"
assert payload_ok(r), f"pending tick lacks a valid data.next nudge: {r}"

# (C) drive the second project to all_done → the tick must NOT nudge
s = server(done); init(s)
tool(s, "start", {"task": "T1"}); tool(s, "done", {"task": "T1"}); tool(s, "gate", {"gate": "GATE_P0"})
r = tool(s, "tick"); s.stdin.close(); s.wait(timeout=10)
assert r.get("data", {}).get("reason") in ("all_done", "project_complete"), f"project did not reach all_done: {r}"
assert payload_ok(r), f"a done project was wrongly nudged to keep looping: {r}"
print("LIVE-OK")
PY
out="$(python3 "$work/live.py" "$work" "$pend" "$done" 2>&1)" || fail "live driver: $out"
printf '%s\n' "$out" | grep -q LIVE-OK || fail "live assertions failed: $out"
echo "MCP-DRIVES-LOOP-OK"
