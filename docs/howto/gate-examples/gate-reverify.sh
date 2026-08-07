#!/usr/bin/env bash
# Proof for "Re-verify completed gates": a passed gate is a claim about CURRENT reality, not
# a permanent stamp. Because gates are behavioral and re-runnable, HeartBeat can re-check an
# old proof read-only — and catch it if the work has decayed. Drive the real hb CLI and prove:
#   1. a completed gate re-verifies (hb gate --check => would_pass; hb gate --all => passes),
#   2. re-verification is READ-ONLY (no new events),
#   3. if the artifact regresses, re-verification catches it (would_block / some gates block).
# Prints REVERIFY-OK only when all hold.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

p="$(mktemp -d)"; trap 'rm -rf "$p"' EXIT
hb init "$p" >/dev/null 2>&1
python3 -c 'import json,sys;json.dump({"phases":[{"id":"A0","gate_entry":None,"gate_exit":"GA0","tasks":[{"id":"T1","title":"make out.txt"}]}],"gates":{"GA0":{"desc":"g","criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},open(sys.argv[1],"w"))' "$p/.hb/dag.json"
hb rebuild --dir "$p" >/dev/null 2>&1
hb start T1 --dir "$p" >/dev/null 2>&1; printf 'ok\n' > "$p/out.txt"; hb done T1 --dir "$p" >/dev/null 2>&1; hb gate GA0 --dir "$p" >/dev/null 2>&1

# 1. Intact: re-verify read-only reports it still passes.
ev0="$(wc -l < "$p/.hb/events.jsonl")"
hb gate GA0 --check --dir "$p" 2>&1 | grep -q 'would_pass' || fail "intact gate did not re-verify (would_pass)"
hb gate --all --dir "$p" >/dev/null 2>&1 || fail "hb gate --all failed on an intact project"
# 2. Read-only: --check appended no events.
ev1="$(wc -l < "$p/.hb/events.jsonl")"
[ "$ev0" = "$ev1" ] || fail "re-verification mutated the log ($ev0 -> $ev1) — --check is not read-only"

# 3. Regress the artifact so the behavioral criterion no longer holds.
printf 'REGRESSED\n' > "$p/out.txt"   # no "ok" -> grep -q ok fails
hb gate GA0 --check --dir "$p" 2>&1 | grep -q 'would_block' || fail "a regressed artifact was NOT caught (still would_pass)"
hb gate --all --dir "$p" >/dev/null 2>&1 && fail "hb gate --all passed despite a regressed gate"

# Control: restoring the artifact makes it re-verify again (the check tracks reality).
printf 'ok\n' > "$p/out.txt"
hb gate GA0 --check --dir "$p" 2>&1 | grep -q 'would_pass' || fail "restoring the artifact did not restore would_pass"

echo "REVERIFY-OK: a completed gate re-verifies read-only, and a decayed proof is caught (would_block)."
