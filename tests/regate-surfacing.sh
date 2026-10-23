#!/usr/bin/env bash
# regate-surfacing.sh — a pending regate is LOUD in hb report on both runtimes (RG3 spec).
#
# The report's phase line for a gate under revision must carry the gate id, a revision marker
# ('revised'), the rearm obligation ('rearm pending') and the recorded reason; the marker is GONE
# after a valid rearm; and a never-regated project's report carries no revision marker at all
# (the feature is invisible until used). Guard markers: `regate-guard: report` in hb-report.js
# and report.py — --selftest strips each and expects the marker assertions to go red.
#
#   bash tests/regate-surfacing.sh [case]   cases: marker clear quiet
#   bash tests/regate-surfacing.sh --selftest
# Prints <CASE>-OK per case, REGATE-SURFACING-OK when all pass, REGATE-SURFACING-SELFTEST-OK for teeth.
set -u
unset HB_DIR PROJECT_DIR GATE G DAG_FILE EVENTS_FILE 2>/dev/null || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
fail(){ echo "FAIL: $1"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
PY(){ PYTHONPATH="${HB_PY_SRC:-$ROOT/py/src}" python3 -m heartbeat.cli "$@"; }

mkproj(){
  mkdir -p "$1"; ( cd "$1" && git init -q >/dev/null 2>&1; bash "$ROOT/plugin/bootstrap.sh" . >/dev/null 2>&1 )
  cat > "$1/.hb/dag.json" <<'EOF'
{"project":"surfacing-fixture",
 "phases":[{"id":"B","title":"reviewed work","gate_entry":null,"gate_exit":"GATE_B",
   "tasks":[{"id":"b1","title":"work","requires":[],"description":"writes m.txt"}]}],
 "gates":{"GATE_B":{"desc":"g","review":{"prompt":"Refute B."},"criteria":[
   {"id":"c1","desc":"behavioral","cmd":"python3 -c \"assert 1+1==2\""}]}}}
EOF
}
both_have(){   # $1 = proj  $2 = grep pattern  $3 = label
  local n p
  n=$( cd "$1" && node .hb/hb-report.js .hb 2>/dev/null ); p=$( cd "$1" && PY report --dir "$1" 2>/dev/null )
  echo "$n" | grep -qi "$2" || fail "$3: node report missing '$2': $n"
  echo "$p" | grep -qi "$2" || fail "$3: python report missing '$2': $p"
}
both_lack(){
  local n p
  n=$( cd "$1" && node .hb/hb-report.js .hb 2>/dev/null ); p=$( cd "$1" && PY report --dir "$1" 2>/dev/null )
  echo "$n" | grep -qi "$2" && fail "$3: node report still carries '$2'"
  echo "$p" | grep -qi "$2" && fail "$3: python report still carries '$2'"
  return 0
}

case_marker(){
  local P="$W/mk"; mkproj "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start b1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done b1 >/dev/null )
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js regate GATE_B volumes were replaced >/dev/null 2>&1 ) || fail "marker: declare failed"
  both_have "$P" "GATE_B" "marker"
  both_have "$P" "revised" "marker"
  both_have "$P" "rearm pending" "marker"
  both_have "$P" "volumes were replaced" "marker"
  echo "MARKER-OK"
}

case_clear(){
  local P="$W/cl"; mkproj "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start b1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done b1 >/dev/null )
  printf 'the work of b1\n' > "$P/m.txt"
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js regate GATE_B volumes were replaced >/dev/null 2>&1 )
  python3 -c "
import json; p='$P/.hb/dag.json'; d=json.load(open(p))
d['gates']['GATE_B']['criteria']=[{'id':'rev1','desc':'revised','cmd':'python3 -c \"assert 2+2==4\"'}]
json.dump(d,open(p,'w'),indent=2)"
  printf 'Rearm evidence for GATE_B (task b1): the volume premise died; the revised criterion runs.\n' > "$P/evidence.md"
  ( cd "$P" && HB_ACTOR=bob node .hb/hb.js regate GATE_B --rearm --artifact evidence.md >/dev/null 2>&1 ) || fail "clear: rearm failed"
  both_lack "$P" "rearm pending" "clear"
  both_lack "$P" "revised" "clear"
  echo "CLEAR-OK"
}

case_quiet(){
  local P="$W/q"; mkproj "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start b1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done b1 >/dev/null )
  both_lack "$P" "regate\|revised\|rearm" "quiet"
  echo "QUIET-OK"
}

mutate(){ local b; b=$(grep -c "$2" "$1" 2>/dev/null || true); [ "${b:-0}" -gt 0 ] || fail "selftest: no '$2' marker in $1"; sed -i "/$2/d" "$1"; }
selftest(){
  local P="$W/st"; mkproj "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start b1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done b1 >/dev/null )
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js regate GATE_B volumes were replaced >/dev/null 2>&1 )
  mutate "$P/.hb/hb-report.js" "regate-guard: report"
  ( cd "$P" && node .hb/hb-report.js .hb 2>/dev/null | grep -qi "rearm pending" ) && fail "selftest: node marker survived its guard strip"
  cp -r "$ROOT/py/src" "$W/py-st"; mutate "$W/py-st/heartbeat/report.py" "regate-guard: report"
  ( cd "$P" && HB_PY_SRC="$W/py-st" PY report --dir "$P" 2>/dev/null | grep -qi "rearm pending" ) && fail "selftest: python marker survived its guard strip"
  echo "REGATE-SURFACING-SELFTEST-OK"
}

if [ "${1:-}" = "--selftest" ]; then selftest; exit 0; fi
sel="${1:-all}"
for c in marker clear quiet; do
  if [ "$sel" = all ] || [ "$sel" = "$c" ]; then "case_$c" || exit 1; fi
done
[ "$sel" = all ] && echo "REGATE-SURFACING-OK"
exit 0
