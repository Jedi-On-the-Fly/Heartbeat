#!/usr/bin/env bash
# Proof for "Escalate instead of retry forever": the driver retries a failing task a BOUNDED
# number of times (HB_EXEC_ATTEMPT_CAP) and then ESCALATES for a human — it does not loop
# forever. Drive the real executor:
#   1. a worker that always fails -> the task is retried exactly cap times, then the driver
#      stops with attempts_exhausted (non-zero) and the phase is not completed,
#   2. control: a worker that succeeds completes on the first attempt (no escalation).
# Prints ESCALATE-VS-RETRY-OK only when retries are bounded by the cap and the driver escalates.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
failer="$work/fail.sh"; printf '#!/usr/bin/env bash\ncat >/dev/null\necho '\''{"ok":false,"summary":"could not do it"}'\''\n' > "$failer"; chmod +x "$failer"
worker="$work/ok.sh";   printf '#!/usr/bin/env bash\ncat >/dev/null\necho ok > out.txt\necho '\''{"ok":true,"summary":"done"}'\''\n' > "$worker"; chmod +x "$worker"

mkproj(){ local p; p="$(mktemp -d)"; hb init "$p" >/dev/null 2>&1
  python3 -c 'import json,sys;json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_P0","tasks":[{"id":"T1","title":"produce out.txt"}]}],"gates":{"GATE_P0":{"desc":"g","criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},open(sys.argv[1],"w"))' "$p/.hb/dag.json"
  hb rebuild --dir "$p" >/dev/null 2>&1; echo "$p"; }
done_P0(){ hb state --dir "$1" | python3 -c "import sys,json;sys.exit(0 if 'P0' in json.load(sys.stdin).get('completed_phases',[]) else 1)"; }

CAP=3
# 1. Failing worker: retried exactly CAP times, then escalate.
p="$(mkproj)"
HB_EXEC_CMD="$failer" HB_EXEC_ATTEMPT_CAP="$CAP" HB_EXEC_MAX_ITERS=50 hb exec run --dir "$p" >/dev/null 2>&1; rc=$?
n="$(grep -c '"event": "task_failed"' "$p/.hb/events.jsonl")"
[ "$rc" -ne 0 ]      || fail "the driver did not escalate a persistently failing task (it may loop forever)"
[ "$n" -eq "$CAP" ]  || fail "the task was not retried exactly cap=$CAP times (got $n) — retry is not bounded by the cap"
done_P0 "$p" && fail "the phase completed despite the worker always failing"
rm -rf "$p"

# 2. Control: a working worker completes on the first attempt (no retry storm, no escalation).
p="$(mkproj)"
HB_EXEC_CMD="$worker" HB_EXEC_ATTEMPT_CAP="$CAP" HB_EXEC_MAX_ITERS=50 hb exec run --dir "$p" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || fail "control: a working worker did not complete cleanly (rc=$rc)"
done_P0 "$p" || fail "control: a working worker did not complete the phase"
[ "$(grep -c '"event": "task_failed"' "$p/.hb/events.jsonl")" -eq 0 ] || fail "control: a working worker produced failures"
rm -rf "$p"

echo "ESCALATE-VS-RETRY-OK: a failing task is retried exactly $CAP times, then the driver escalates; a good worker completes without retry."
