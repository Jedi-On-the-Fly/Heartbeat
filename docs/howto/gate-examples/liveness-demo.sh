#!/usr/bin/env bash
# Proof for "Prove liveness": the tick escalates instead of hanging. Drive the real hb CLI
# and prove three alarms fire when something is wrong — and stay SILENT when it is not:
#   1. BUILD_STUCK   — repeated no-progress (failed attempts) raises build_stuck.
#   2. STALE LEASE   — a lease past its staleness threshold is reclaimed (lease_expired).
#   3. REVIEW_STUCK  — an unresolved review is surfaced by diagnose.
# Prints LIVENESS-OK only when all hold (each with a silent-when-healthy control).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 HB_ROT_CHECK=0 STUCK_TICKS=999
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

mkp(){ # $1 = review-block JSON fragment ("" for none) -> echoes project dir
  local p; p="$(mktemp -d)"; hb init "$p" >/dev/null 2>&1
  cat > "$p/.hb/dag.json" <<JSON
{ "phases":[{"id":"A0","gate_entry":null,"gate_exit":"GA0","tasks":[{"id":"A0T1","title":"do"}]}],
  "gates":{"GA0":{"desc":"g",${1}"criteria":[{"id":"c","cmd":"true"}]}} }
JSON
  hb rebuild --dir "$p" >/dev/null 2>&1; echo "$p"
}
reason(){ hb tick --dir "$1" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('reason',''))"; }

# 1. BUILD_STUCK: silent at first, fires after repeated no-progress.
p="$(mkp '')"
[ "$(reason "$p")" != "build_stuck" ] || fail "G1 control: build_stuck fires on a healthy project"
for _ in 1 2 3 4 5; do hb start A0T1 --dir "$p" >/dev/null 2>&1; hb fail A0T1 --dir "$p" >/dev/null 2>&1; done
[ "$(reason "$p")" = "build_stuck" ] || fail "G1: no build_stuck after repeated failed attempts"
rm -rf "$p"

# 2. STALE LEASE: a fresh lease is kept; a stale one is reclaimed (lease_expired event).
p="$(mkp '')"
hb start A0T1 --dir "$p" >/dev/null 2>&1
hb tick --dir "$p" >/dev/null 2>&1
grep -q lease_expired "$p/.hb/events.jsonl" && fail "G2 control: a fresh lease was reclaimed"
LOCK_STALE_S=0 HEARTBEAT_STALE_S=0 hb tick --dir "$p" >/dev/null 2>&1
grep -q lease_expired "$p/.hb/events.jsonl" || fail "G2: a stale lease was not reclaimed (no lease_expired)"
rm -rf "$p"

# 3. REVIEW_STUCK: not on a fresh project; surfaced once a review is pending.
p="$(mkp '"review":{"prompt":"refute"},')"
hb diagnose --dir "$p" 2>&1 | grep -qi review_stuck && fail "G3 control: review_stuck on a fresh project"
hb start A0T1 --dir "$p" >/dev/null 2>&1; hb done A0T1 --dir "$p" >/dev/null 2>&1; hb gate GA0 --dir "$p" >/dev/null 2>&1
hb diagnose --dir "$p" 2>&1 | grep -qi review_stuck || fail "G3: an unresolved review was not surfaced as review_stuck"
rm -rf "$p"

echo "LIVENESS-OK: build_stuck fires on no-progress, stale leases reclaimed, review_stuck surfaced — each silent when healthy."
