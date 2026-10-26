#!/usr/bin/env bash
# dag-write.sh — the verbs that rewrite dag.json replace it atomically (T188).
#
# park, unpark, regate (declare and --rearm), detach and reattach rewrite dag.json under the write
# lock — but every verb READS dag.json before taking the lock (the shape check, the target lookup).
# A rewrite in place (truncate, then write) lets that read land on an empty or partial file: the
# concurrent verb then refuses ("unknown gate or phase") or the shape check calls a sound plan broken
# — the T182.2 race went red on a loaded CI runner exactly so. The cure is the state.json discipline:
# write a temporary file, rename it over dag.json. A reader then sees the old plan or the new one,
# never a torn one. The deterministic signature of a rename is a NEW inode after every rewrite (an
# in-place write keeps the old one), checked for each verb on both runtimes; the case also asserts
# that no temporary file is left behind.
#
#   bash tests/dag-write.sh            → DAG-WRITE-OK
#   bash tests/dag-write.sh --selftest → DAG-WRITE-SELFTEST-OK
set -u
unset HB_DIR PROJECT_DIR GATE G DAG_FILE EVENTS_FILE 2>/dev/null || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
fail(){ echo "FAIL: $1"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
PY(){ PYTHONPATH="${HB_PY_SRC:-$ROOT/py/src}" python3 -m heartbeat.cli "$@"; }
BASE='{"project":"write-fixture",
 "phases":[
  {"id":"P1","title":"first","gate_entry":null,"gate_exit":"G1",
   "tasks":[{"id":"t1","title":"one","requires":[],"description":"writes one"}]},
  {"id":"P2","title":"second","gate_entry":"G1","gate_exit":"G2",
   "tasks":[{"id":"t3","title":"three","requires":[],"description":"writes three"}]}],
 "gates":{
  "G1":{"desc":"g1","criteria":[{"id":"c1","desc":"behavioral","cmd":"python3 -c \"assert 1+1==2\""}]},
  "G2":{"desc":"g2","criteria":[{"id":"c2","desc":"behavioral","cmd":"python3 -c \"assert 2+2==4\""}]}}}'
ino(){ python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$1"; }

mkp(){   # $1 = dir: P1 complete and G1 passed, so every dag-writing verb has a legal target
  mkdir -p "$1"; ( cd "$1" && bash "$ROOT/plugin/bootstrap.sh" . >/dev/null 2>&1 )
  printf '%s' "$BASE" > "$1/.hb/dag.json"
  ( cd "$1" && HB_ACTOR=doer node .hb/hb.js start t1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done t1 >/dev/null && bash .hb/gate.sh G1 >/dev/null 2>&1 ) || fail "fixture could not complete P1"
  printf 'Rearm evidence for G1 (task t1): the premise died; the revised criteria were run by hand and hold.\n' > "$1/e.md"
}

# one verb: $1 = runtime, $2 = project, $3 = label, rest = the verb's words for that runtime
step(){
  local rt="$1" P="$2" label="$3" before after; shift 3
  before=$(ino "$P/.hb/dag.json")
  if [ "$rt" = node ]; then ( cd "$P" && node .hb/hb.js "$@" ) >/dev/null 2>&1 || fail "$label ($rt): the verb refused on the fixture"
  else ( cd "$P" && PY "$@" --dir "$P" ) >/dev/null 2>&1 || fail "$label ($rt): the verb refused on the fixture"; fi
  after=$(ino "$P/.hb/dag.json")
  [ "$before" != "$after" ] || fail "$label ($rt): dag.json was rewritten IN PLACE (same inode $before) — a concurrent reader can see a torn plan"
  [ ! -e "$P/.hb/dag.json.tmp" ] || fail "$label ($rt): a temporary dag.json.tmp was left behind"
}

case_atomic(){
  local P
  P="$W/node"; mkp "$P"
  HB_ACTOR=al    step node "$P" park           park P2 shelved for now
  HB_ACTOR=al    step node "$P" unpark         unpark P2
  HB_ACTOR=carol step node "$P" "regate declare" regate G1 premise died
  HB_ACTOR=dave  step node "$P" "regate rearm" regate G1 --rearm --artifact e.md
  HB_ACTOR=al    step node "$P" detach         detach P2 dependency was false
  HB_ACTOR=al    step node "$P" reattach       reattach P2
  P="$W/py"; mkp "$P"
  HB_ACTOR=al    step py "$P" park           park P2 --reason "shelved for now"
  HB_ACTOR=al    step py "$P" unpark         unpark P2
  HB_ACTOR=carol step py "$P" "regate declare" regate G1 --reason "premise died"
  HB_ACTOR=dave  step py "$P" "regate rearm" regate G1 --rearm --artifact e.md
  HB_ACTOR=al    step py "$P" detach         detach P2 --reason "dependency was false"
  HB_ACTOR=al    step py "$P" reattach       reattach P2
  echo "DAG-WRITE-OK"
}

selftest(){
  # The node and python writers each route through ONE helper (writeDag / write_dag). Replace it with
  # an in-place write in a COPY of the runtime → the case must go red, on each runtime.
  local P o
  P="$W/st-node"; mkp "$P"
  grep -q 'dag-write-guard' "$P/.hb/hb.js" || fail "selftest: no dag-write-guard marker in hb.js"
  sed -i 's|^.*dag-write-guard.*$|function writeDag(dag) { fs.writeFileSync(DAG, JSON.stringify(dag, null, 2)); }|' "$P/.hb/hb.js"
  node --check "$P/.hb/hb.js" || fail "selftest: the stripped hb.js no longer parses"
  o=$( HB_ACTOR=al step node "$P" park park P2 shelved 2>&1 ) && fail "selftest: node stayed green with an in-place writer"
  echo "$o" | grep -q 'IN PLACE' || fail "selftest: node went red for the wrong reason: $o"
  cp -r "$ROOT/py/src" "$W/py2"
  grep -q 'dag-write-guard' "$W/py2/heartbeat/state.py" || fail "selftest: no dag-write-guard marker in state.py"
  sed -i 's|^.*dag-write-guard.*$|    Path(hb, "dag.json").write_text(json.dumps(dag, indent=2))|' "$W/py2/heartbeat/state.py"
  python3 -c "import sys; sys.path.insert(0, '$W/py2'); import heartbeat.cli" || fail "selftest: the stripped state.py no longer imports"
  P="$W/st-py"; mkp "$P"
  o=$( HB_PY_SRC="$W/py2" HB_ACTOR=al step py "$P" park park P2 --reason shelved 2>&1 ) && fail "selftest: python stayed green with an in-place writer"
  echo "$o" | grep -q 'IN PLACE' || fail "selftest: python went red for the wrong reason: $o"
  echo "DAG-WRITE-SELFTEST-OK"
}

if [ "${1:-}" = "--selftest" ]; then selftest; else case_atomic; fi
