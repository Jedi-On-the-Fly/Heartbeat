#!/usr/bin/env bash
# Parity of the Stage-A TICK: both runtimes must emit the same data.reason for the same state.
# The tick's decision was never cross-checked (parity compares the projector/resolver/etc. and
# the protocol reason KEYS, never the two ticks' output) — which is how tick.py came to lack the
# review_stuck escalation that tick.sh has. The review-stall fixture is the discriminator.
# Prints TICK-PARITY-OK only when every fixture's reason agrees across node and python.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

HB_NO_GIT=1 bash "$ROOT/plugin/bootstrap.sh" "$tmp/base" >/dev/null 2>&1 </dev/null
DAG='{"phases":[{"id":"P0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"P0T1","title":"do","requires":[]}]}],"gates":{"G0":{"desc":"g","review":{"prompt":"r"},"criteria":[{"id":"c","desc":"d","cmd":"true"}]}}}'
printf '%s' "$DAG" > "$tmp/base/.hb/dag.json"

# extract data.reason from a tick's stdout (last JSON line)
reason() {
  python3 -c "import sys,json
for ln in reversed(sys.stdin.read().splitlines()):
    ln=ln.strip()
    if ln.startswith('{'):
        try: print(json.loads(ln).get('data',{}).get('reason','')); break
        except Exception: pass
"
}

case_reason() { # name  events-block
  printf '%s\n' "$2" > "$tmp/base/.hb/events.jsonl"
  node "$tmp/base/.hb/hb.js" rebuild >/dev/null 2>&1
  rm -rf "$tmp/n" "$tmp/p"; cp -r "$tmp/base" "$tmp/n"; cp -r "$tmp/base" "$tmp/p"
  rm -rf "$tmp/n/.hb/.lock" "$tmp/p/.hb/.lock"
  local nr pr
  nr=$(STUCK_TICKS=3 HB_NO_GIT=1 HB_ROT_CHECK=0 bash "$tmp/n/.hb/tick.sh" 2>/dev/null | reason)
  pr=$(STUCK_TICKS=3 HB_NO_GIT=1 HB_ROT_CHECK=0 PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli tick --dir "$tmp/p" 2>/dev/null | reason)
  [ "$nr" = "$pr" ] || { echo "FAIL: [$1] node reason='$nr' != python reason='$pr'"; exit 1; }
  echo "  ok [$1] both=$nr"
}

case_reason next_task '{"event":"initialized"}'
case_reason gate_pending '{"event":"initialized"}
{"event":"task_done","task":"P0T1"}'
case_reason all_done '{"event":"initialized"}
{"event":"task_done","task":"P0T1"}
{"event":"gate_passed","gate":"G0"}
{"event":"review_passed","gate":"G0"}'
case_reason review_stall '{"event":"initialized"}
{"event":"task_done","task":"P0T1"}
{"event":"gate_passed","gate":"G0"}
{"event":"review_wake","gate":"G0"}
{"event":"review_wake","gate":"G0"}
{"event":"review_wake","gate":"G0"}'
case_reason build_stuck '{"event":"initialized"}
{"event":"task_failed","task":"P0T1"}
{"event":"task_failed","task":"P0T1"}
{"event":"task_failed","task":"P0T1"}
{"event":"task_failed","task":"P0T1"}
{"event":"task_failed","task":"P0T1"}'

echo "TICK-PARITY-OK: node ≡ python on data.reason (next_task, gate_pending, all_done, review_stuck, build_stuck)."
