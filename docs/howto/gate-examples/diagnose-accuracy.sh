#!/usr/bin/env bash
# Proof for "Diagnose a stuck project": hb diagnose names the SPECIFIC cause, not a generic
# "something's wrong". Drive the real hb CLI, block a project three ways, and assert diagnose
# fingers the actual cause — the failing criterion, the missing rotted file, the awaiting
# gate — and that a healthy project reports "no blocker detected". Prints DIAGNOSE-ACCURACY-OK
# only when each names its real cause and the healthy control is silent.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }
has(){ printf '%s' "$1" | grep -q -- "$2"; }

mkproj(){ # $1 = criteria JSON array, $2 = review? (1/0) -> project dir
  local p; p="$(mktemp -d)"; hb init "$p" >/dev/null 2>&1
  CRIT="$1" REV="$2" python3 -c 'import os,json,sys
g={"desc":"g","criteria":json.loads(os.environ["CRIT"])}
if os.environ["REV"]=="1": g["review"]={"prompt":"refute"}
json.dump({"phases":[{"id":"A0","gate_entry":None,"gate_exit":"GA0","tasks":[{"id":"A0T1","title":"make out.txt"}]}],"gates":{"GA0":g}}, open(sys.argv[1],"w"))' "$p/.hb/dag.json"
  hb rebuild --dir "$p" >/dev/null 2>&1; echo "$p"
}

# 0. HEALTHY control: nothing is wrong -> diagnose is silent.
p="$(mkproj '[{"id":"c1","cmd":"true"}]' 0)"
d="$(hb diagnose --dir "$p" 2>&1)"
has "$d" "no blocker detected" || fail "healthy control: diagnose reported a blocker when nothing is wrong ($d)"
rm -rf "$p"

# 1. GATE_BLOCKED: c1 passes, c2 fails -> diagnose names GA0 and the FAILING criterion c2 (not c1).
p="$(mkproj '[{"id":"c1","cmd":"true"},{"id":"c2","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]' 0)"
hb start A0T1 --dir "$p" >/dev/null 2>&1; hb done A0T1 --dir "$p" >/dev/null 2>&1; hb gate GA0 --dir "$p" >/dev/null 2>&1
d="$(hb diagnose --dir "$p" 2>&1)"
has "$d" "gate_blocked"                  || fail "gate_blocked: diagnose did not identify a blocked gate ($d)"
has "$d" "GA0"                           || fail "gate_blocked: diagnose did not name the gate GA0"
printf '%s' "$d" | grep -qF '[c2]'       || fail "gate_blocked: diagnose did not name the failing criterion c2"
printf '%s' "$d" | grep -qF '[c1]'       && fail "gate_blocked: diagnose wrongly flagged the passing criterion c1"
rm -rf "$p"

# 2. GATE_ROT: complete the phase, delete its gate's artifact -> diagnose names the file.
p="$(mkproj '[{"id":"c1","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]' 0)"
hb start A0T1 --dir "$p" >/dev/null 2>&1; printf 'ok\n' > "$p/out.txt"; hb done A0T1 --dir "$p" >/dev/null 2>&1; hb gate GA0 --dir "$p" >/dev/null 2>&1
rm -f "$p/out.txt"
d="$(hb diagnose --dir "$p" 2>&1)"   # inferred — diagnose must auto-classify the rot
has "$d" "gate_rot"                  || fail "gate_rot: diagnose did not auto-detect rot ($d)"
has "$d" "out.txt"                   || fail "gate_rot: diagnose did not name the missing file out.txt"
has "$d" "no longer reproducible"    || fail "gate_rot: diagnose did not explain the rot"
rm -rf "$p"

# 3. REVIEW_STUCK: a review-gated phase whose review never resolved -> diagnose names the gate.
p="$(mkproj '[{"id":"c1","cmd":"true"}]' 1)"
hb start A0T1 --dir "$p" >/dev/null 2>&1; hb done A0T1 --dir "$p" >/dev/null 2>&1; hb gate GA0 --dir "$p" >/dev/null 2>&1
d="$(hb diagnose --dir "$p" 2>&1)"
has "$d" "review_stuck" || fail "review_stuck: diagnose did not report the stuck review ($d)"
has "$d" "GA0"          || fail "review_stuck: diagnose did not name the awaiting gate GA0"
rm -rf "$p"

echo "DIAGNOSE-ACCURACY-OK: diagnose names the failing criterion, the missing file, and the awaiting gate; silent when healthy."
