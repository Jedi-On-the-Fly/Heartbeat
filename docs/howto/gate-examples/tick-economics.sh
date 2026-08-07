#!/usr/bin/env bash
# Proof for "Spend the model only on work": the cheap deterministic tick decides when to wake
# the expensive worker. A tick wakes only when there is actionable work — and it CLAIMS that
# work as it wakes, so a subsequent tick will not wake a second agent for a task already in
# flight. Drive the real tick and prove:
#   1. a runnable task exists (hb ready, read-only) with nothing leased yet,
#   2. the tick wakes for it (wakeAgent=true, next_task) — and claims the lease,
#   3. a further tick does NOT wake (wakeAgent=false, at_capacity) — no duplicate agent,
#   4. freeing the lease makes the tick wake again — proving at_capacity was caused by the
#      in-flight lease, not a constant.
# Prints TICK-ECONOMICS-OK only when all hold.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

p="$(mktemp -d)"; trap 'rm -rf "$p"' EXIT
hb init "$p" >/dev/null 2>&1
python3 -c 'import json,sys;json.dump({"phases":[{"id":"A0","gate_entry":None,"gate_exit":"GA0","tasks":[{"id":"T1","title":"do"}]}],"gates":{"GA0":{"desc":"g","criteria":[{"id":"c","cmd":"true"}]}}},open(sys.argv[1],"w"))' "$p/.hb/dag.json"
hb rebuild --dir "$p" >/dev/null 2>&1
tickwr(){ hb tick --dir "$1" 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['wakeAgent'], d['data'].get('reason'))"; }

# 1. There is runnable work, and nothing is leased yet (read-only view).
hb ready 4 --dir "$p" 2>/dev/null | python3 -c "import sys,json;sys.exit(0 if any(t['id']=='T1' for t in json.load(sys.stdin)) else 1)" \
  || fail "hb ready did not show the runnable task T1"
[ -z "$(ls -A "$p/.hb/leases" 2>/dev/null)" ] || fail "a task was already leased before any tick"

# 2. The tick wakes for the work (and claims it).
read -r wake reason <<<"$(tickwr "$p")"
{ [ "$wake" = True ] && [ "$reason" = next_task ]; } || fail "a ready task did not wake the agent (wake=$wake reason=$reason)"

# 3. A further tick does NOT wake a second agent while T1 is in flight.
read -r wake reason <<<"$(tickwr "$p")"
{ [ "$wake" = False ] && [ "$reason" = at_capacity ]; } || fail "the tick woke again while a task was in flight (wake=$wake reason=$reason) — model spent for nothing"

# 4. Free the lease -> the tick wakes again. Proves at_capacity was caused by the in-flight
#    lease (not a constant): with the work no longer in flight, there is again work to hand out.
hb fail T1 --dir "$p" >/dev/null 2>&1
read -r wake reason <<<"$(tickwr "$p")"
{ [ "$wake" = True ] && [ "$reason" = next_task ]; } || fail "freeing the lease did not re-wake the tick (wake=$wake reason=$reason) — at_capacity was not lease-caused"

echo "TICK-ECONOMICS-OK: work wakes the agent (next_task); an in-flight task keeps it asleep (at_capacity); freeing the lease wakes it again."
