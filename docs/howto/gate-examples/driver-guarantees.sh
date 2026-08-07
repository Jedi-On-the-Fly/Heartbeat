#!/usr/bin/env bash
# Proof for "Keep Stage B untrusted": the driver mediates every state transition and trusts
# the GATE, not the worker. Drive the real Python executor with stub backends and prove:
#   1. ESCALATE-ONLY — a compliant worker (ok:true) plus an unpassable gate does NOT complete
#      the phase; the executor escalates (non-zero) and dag.json is byte-unchanged (it never
#      weakens a gate). Control: a passable gate DOES complete (so guard 1 isn't vacuous).
#   2. MALFORMED OUTPUT — a backend emitting non-JSON never advances a task; it escalates.
#   3. HUNG GATE — a gate that sleeps is killed at GATE_TIMEOUT_S (blocked, not hung).
# Prints STAGE-B-UNTRUSTED-OK only when all hold.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
okstub="$work/ok.sh";   printf '#!/usr/bin/env bash\ncat >/dev/null\necho '\''{"ok":true,"summary":"did it"}'\''\n' > "$okstub";   chmod +x "$okstub"
junkstub="$work/junk.sh"; printf '#!/usr/bin/env bash\ncat >/dev/null\necho "this is not json at all"\n' > "$junkstub"; chmod +x "$junkstub"

mkproj(){ # $1 = gate cmd -> echoes project dir
  local p; p="$(mktemp -d)"
  hb init "$p" >/dev/null 2>&1
  cat > "$p/.hb/dag.json" <<JSON
{ "phases":[{"id":"A0","gate_entry":null,"gate_exit":"GA0","tasks":[{"id":"A0T1","title":"do it"}]}],
  "gates":{"GA0":{"desc":"g","criteria":[{"id":"c","cmd":"$1"}]}} }
JSON
  hb rebuild --dir "$p" >/dev/null 2>&1
  echo "$p"
}
completed(){ hb state --dir "$1" | python3 -c "import sys,json;sys.exit(0 if 'A0' in json.load(sys.stdin).get('completed_phases',[]) else 1)"; }

# 1. ESCALATE-ONLY + trust-the-gate: worker says ok, gate cannot pass.
p="$(mkproj false)"
before="$(md5sum "$p/.hb/dag.json" | cut -d' ' -f1)"
HB_EXEC_CMD="$okstub" HB_EXEC_MAX_ITERS=25 hb exec run --dir "$p" >/dev/null 2>&1; rc=$?
after="$(md5sum "$p/.hb/dag.json" | cut -d' ' -f1)"
[ "$rc" -ne 0 ]                || fail "G1: executor did not escalate on an unpassable gate"
grep -q '"task_done"' "$p/.hb/events.jsonl" || fail "G1: the worker's task_done was not even recorded"
completed "$p" && fail "G1: phase completed despite a failing gate (driver trusted the worker)"
[ "$before" = "$after" ]       || fail "G1: dag.json changed — the driver weakened the gate"
rm -rf "$p"

# 1b. Control: with a passable gate the same worker DOES complete the phase.
p="$(mkproj true)"
HB_EXEC_CMD="$okstub" HB_EXEC_MAX_ITERS=25 hb exec run --dir "$p" >/dev/null 2>&1
completed "$p" || fail "G1 control: a passable gate did not complete — guard 1 would be vacuous"
rm -rf "$p"

# 2. MALFORMED OUTPUT: gate is passable, but the backend emits junk -> never advances.
p="$(mkproj true)"
HB_EXEC_CMD="$junkstub" HB_EXEC_ATTEMPT_CAP=2 HB_EXEC_MAX_ITERS=25 hb exec run --dir "$p" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ]                              || fail "G2: malformed backend output did not escalate"
grep -q '"task_done"' "$p/.hb/events.jsonl" && fail "G2: a task advanced on malformed (non-JSON) output"
completed "$p" && fail "G2: phase completed on malformed output"
rm -rf "$p"

# 3. HUNG GATE: a sleeping gate is killed at GATE_TIMEOUT_S (blocked, not hung).
p="$(mkproj 'sleep 30')"
SECONDS=0
timeout 15 env GATE_TIMEOUT_S=2 python3 -m heartbeat.cli gate GA0 --dir "$p" >/dev/null 2>&1; rc=$?
dur=$SECONDS
[ "$rc" -ne 124 ] || fail "G3: gate hung — the outer timeout had to kill it (GATE_TIMEOUT_S not enforced)"
[ "$rc" -ne 0 ]   || fail "G3: a sleeping gate somehow passed"
[ "$dur" -lt 10 ] || fail "G3: gate not killed promptly (took ${dur}s)"
rm -rf "$p"

echo "STAGE-B-UNTRUSTED-OK: escalate-only (dag unchanged), malformed output rejected, hung gate killed at timeout."
