#!/usr/bin/env bash
# Proof (C8): a persistently blocked gate must not re-wake the agent EVERY tick forever — a circuit
# breaker must fire (like the build_stuck breaker) after a bounded number of no-progress ticks and stop
# re-alerting. Drives tick.sh repeatedly on a blocked gate and asserts gate_blocked is NOT emitted on
# every tick past a cap (a terminal/waiting signal appears). Prints GATE-BLOCKED-BREAKER-OK. Fails today
# (tick.sh §5 wakes gate_blocked unconditionally while gate.errors>0). Deterministic.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
fail(){ echo "FAIL: $1"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
p="$tmp/proj"; mkdir -p "$p"
HB_NO_GIT=1 bash "$ROOT/plugin/bootstrap.sh" "$p" >/dev/null 2>&1 || fail "bootstrap"
python3 - "$p/.hb/dag.json" <<'PY' 2>/dev/null || true
import json,sys
json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_P0","tasks":[{"id":"T1","title":"t"}]}],
"gates":{"GATE_P0":{"desc":"g","criteria":[{"id":"c","desc":"x","cmd":"false"}]}}},open(sys.argv[1],"w"))
PY
export HB_NO_GIT=1
( cd "$p" && node .hb/hb.js start T1 >/dev/null 2>&1; node .hb/hb.js done T1 >/dev/null 2>&1 )
( cd "$p" && bash .hb/gate.sh GATE_P0 >/dev/null 2>&1 )   # criterion false → gate_failed → gate.errors=1
# drive many ticks; a breaker must stop the endless gate_blocked wake
blocked=0; terminal=0
for i in $(seq 1 9); do
  rm -f "$p/.hb/.lock"
  r="$(cd "$p" && bash .hb/tick.sh 2>/dev/null | node -pe 'try{JSON.parse(require("fs").readFileSync(0,"utf8")).data.reason||""}catch(e){""}')"
  case "$r" in
    gate_blocked) blocked=$((blocked+1));;
    *waiting*|build_stuck|stuck*) terminal=$((terminal+1));;
  esac
done
[ "$terminal" -ge 1 ] || fail "no circuit breaker: gate_blocked re-woke $blocked/9 ticks with no terminal signal"
echo "GATE-BLOCKED-BREAKER-OK"
