#!/usr/bin/env bash
# detach-surfacing.sh — a detached phase is LOUD in hb report and doctor on both runtimes (DT2 spec).
#
# The report's phase line for a detached phase carries '⟂ detached from <gate> (by <actor>: <reason>)'
# — text render only (--json byte-free of it), GONE after reattach, ABSENT on a never-detached
# project. Doctor NOTES (never problems; exit 0 when they are the only findings): the live detach
# (naming the phase, the removed gate and re-audit, with the 'no detach anchor' suffix when the
# anchor is missing), direction A — detach fields present while the log attests no LIVE detach
# (no phase_detached at all, OR the last one answered by phase_reattached: the fail-OPEN restore),
# and direction B — an unanswered phase_detached while the phase carries no fields (the re-lock).
# The audit RULESET is untouched: audit output on a detached fixture is byte-identical to the same
# fixture with the detach fields stripped. Guard markers: `detach-guard: report` (both renderers)
# and `detach-guard: doctor` (both doctors) on strip-clean lines.
#
#   bash tests/detach-surfacing.sh [case]   cases: marker clear quiet doctor audit
#   bash tests/detach-surfacing.sh --selftest
# Prints <CASE>-OK per case, DETACH-SURFACING-OK when all pass, DETACH-SURFACING-SELFTEST-OK for teeth.
set -u
# Env hygiene: under a gate criterion, gate.sh exports HB_DIR/PROJECT_DIR/GATE — and the fixture
# projects' copied CLIs honor env HB_DIR. A proof must never inherit a caller's project pointers
# (the same rule as run-tests.sh/parity.sh; its violation polluted a live plan's event log once).
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
 "phases":[
  {"id":"P","title":"predecessor","gate_entry":null,"gate_exit":"GATE_P",
   "tasks":[{"id":"p1","title":"p work","requires":[],"description":"w"}]},
  {"id":"D","title":"dependent","gate_entry":"GATE_P","gate_exit":"GATE_D",
   "tasks":[{"id":"d1","title":"d work","requires":[],"description":"w"}]}],
 "gates":{
  "GATE_P":{"desc":"p gate","criteria":[{"id":"gp1","desc":"behavioral","cmd":"python3 -c \"assert 1\""}]},
  "GATE_D":{"desc":"d gate","criteria":[{"id":"gd1","desc":"behavioral","cmd":"python3 -c \"assert 2\""}]}}}
EOF
}
detached(){ mkproj "$1"; ( cd "$1" && HB_ACTOR=alice node .hb/hb.js detach D volumes were replaced >/dev/null 2>&1 ) || fail "fixture: detach failed"; }
both_have(){
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
doctor_note(){   # $1 = proj  $2 = pattern  $3 = label — a NOTE on both runtimes, doctor exit 0
  local n p
  n=$( cd "$1" && node .hb/hb.js doctor 2>&1 ); [ $? -eq 0 ] || fail "$3: node doctor exited nonzero (a detach finding must be a NOTE)"
  echo "$n" | grep -qi "$2" || fail "$3: node doctor missing '$2': $n"
  ( cd "$1" && PY doctor --dir "$1" >/dev/null 2>&1 ) || fail "$3: python doctor exited nonzero"
  p=$( cd "$1" && PY doctor --dir "$1" 2>&1 )
  echo "$p" | grep -qi "$2" || fail "$3: python doctor missing '$2': $p"
}

case_marker(){
  local P="$W/mk"; detached "$P"
  both_have "$P" "detached from GATE_P" "marker"
  both_have "$P" "volumes were replaced" "marker"
  both_have "$P" "alice" "marker"
  ( cd "$P" && node .hb/hb-report.js .hb --json 2>/dev/null | grep -qi "detached from" ) && fail "marker: node --json carries the marker"
  ( cd "$P" && PY report --json --dir "$P" 2>/dev/null | grep -qi "detached from" ) && fail "marker: python --json carries the marker"
  echo "MARKER-OK"
}
case_clear(){
  local P="$W/cl"; detached "$P"
  ( cd "$P" && node .hb/hb.js reattach D >/dev/null 2>&1 ) || fail "clear: reattach failed"
  both_lack "$P" "detached from" "clear"
  echo "CLEAR-OK"
}
case_quiet(){
  local P="$W/q"; mkproj "$P"
  both_lack "$P" "detach" "quiet"
  echo "QUIET-OK"
}
case_doctor(){
  # live detach → NOTE naming phase, gate, re-audit
  local P="$W/doc"; detached "$P"
  doctor_note "$P" "D.*GATE_P\|detached" "doctor-live"
  ( cd "$P" && node .hb/hb.js doctor 2>&1 | grep -qi "re-audit" ) || fail "doctor-live: the note does not say re-audit"
  # anchor-missing suffix on the live note
  rm "$P/.hb/anchors/_detach_D.json"
  doctor_note "$P" "no detach anchor" "doctor-anchor-missing"
  # a stamp-MISMATCHED anchor reads as missing and is said aloud too — changed()'s exact
  # predicate; the suffix once keyed on existence only, widening silently (a refuter catch)
  local SM="$W/doc-stamp"; detached "$SM"
  python3 -c "
import json; p='$SM/.hb/anchors/_detach_D.json'; a=json.load(open(p))
a['detached_at']='1999-01-01T00:00:00Z'; json.dump(a,open(p,'w'))"
  doctor_note "$SM" "no detach anchor" "doctor-stamp-mismatch"
  # direction A fixture 1: fields present, NO phase_detached event at all (a hand edit)
  local A="$W/doc-a1"; mkproj "$A"
  python3 -c "
import json; p='$A/.hb/dag.json'; d=json.load(open(p))
D=next(x for x in d['phases'] if x['id']=='D')
D['gate_entry']=None; D.update({'detached_from':'GATE_P','detached_reason':'r','detached_by':'a','detached_at':'2026-01-01T00:00:00Z'})
json.dump(d,open(p,'w'),indent=2)"
  doctor_note "$A" "no live detach\|hand edit\|does not attest" "doctor-dirA-noevent"
  # direction A fixture 2: the fail-OPEN restore — the last phase_detached is ANSWERED, fields back
  local A2="$W/doc-a2"; detached "$A2"
  ( cd "$A2" && node .hb/hb.js reattach D >/dev/null 2>&1 )
  python3 -c "
import json; p='$A2/.hb/dag.json'; d=json.load(open(p))
D=next(x for x in d['phases'] if x['id']=='D')
D['gate_entry']=None; D.update({'detached_from':'GATE_P','detached_reason':'r','detached_by':'a','detached_at':'2026-01-01T00:00:00Z'})
json.dump(d,open(p,'w'),indent=2)"
  doctor_note "$A2" "no live detach\|hand edit\|does not attest" "doctor-dirA-restored"
  # direction B: an unanswered phase_detached, fields gone (the re-lock)
  local B="$W/doc-b"; detached "$B"
  python3 -c "
import json; p='$B/.hb/dag.json'; d=json.load(open(p))
D=next(x for x in d['phases'] if x['id']=='D')
D['gate_entry']='GATE_P'
for k in ('detached_from','detached_reason','detached_by','detached_at'): D.pop(k,None)
json.dump(d,open(p,'w'),indent=2)"
  doctor_note "$B" "re-lock\|silently re-locked\|unanswered" "doctor-dirB"
  echo "DOCTOR-OK"
}
case_audit(){
  local P="$W/au"; detached "$P"
  local Q="$W/au-stripped"; cp -r "$P" "$Q"
  python3 -c "
import json; p='$Q/.hb/dag.json'; d=json.load(open(p))
D=next(x for x in d['phases'] if x['id']=='D')
for k in ('detached_from','detached_reason','detached_by','detached_at'): D.pop(k,None)
json.dump(d,open(p,'w'),indent=2)"
  # repair the stripped copy's lint standing is irrelevant — audit must not read the fields at all
  local an aq pn pq
  an=$(node "$P/.hb/hb-audit.js" "$P/.hb/dag.json" 2>&1); aq=$(node "$Q/.hb/hb-audit.js" "$Q/.hb/dag.json" 2>&1)
  [ "$an" = "$aq" ] || fail "audit: node audit output differs between the detached and stripped fixtures (the ruleset read the fields)"
  pn=$( PY audit "$P/.hb/dag.json" --dir "$P" 2>&1 ); pq=$( PY audit "$Q/.hb/dag.json" --dir "$Q" 2>&1 )
  [ "$pn" = "$pq" ] || fail "audit: python audit output differs between the fixtures"
  echo "AUDIT-OK"
}

mutate(){ local b; b=$(grep -c "$2" "$1" 2>/dev/null || true); [ "${b:-0}" -gt 0 ] || fail "selftest: no '$2' marker in $1"; sed -i "/$2/d" "$1"; }
selftest(){
  local P="$W/st"; detached "$P"
  mutate "$P/.hb/hb-report.js" "detach-guard: report"
  node --check "$P/.hb/hb-report.js" 2>/dev/null || fail "selftest: stripped hb-report.js no longer parses"
  ( cd "$P" && node .hb/hb-report.js .hb 2>/dev/null | grep -qi "detached from" ) && fail "selftest: node marker survived its guard strip"
  cp -r "$ROOT/py/src" "$W/py-st"; mutate "$W/py-st/heartbeat/report.py" "detach-guard: report"
  python3 -c "import sys; sys.path.insert(0,'$W/py-st'); import heartbeat.report" || fail "selftest: stripped report.py no longer imports"
  ( cd "$P" && HB_PY_SRC="$W/py-st" PY report --dir "$P" 2>/dev/null | grep -qi "detached from" ) && fail "selftest: python marker survived its guard strip"
  local P2="$W/st2"; detached "$P2"
  mutate "$P2/.hb/hb.js" "detach-guard: doctor"
  node --check "$P2/.hb/hb.js" 2>/dev/null || fail "selftest: stripped hb.js no longer parses"
  ( cd "$P2" && node .hb/hb.js doctor 2>&1 | grep -qi "detached" ) && fail "selftest: node doctor note survived its guard strip"
  cp -r "$ROOT/py/src" "$W/py-st2"; mutate "$W/py-st2/heartbeat/doctor.py" "detach-guard: doctor"
  python3 -c "import sys; sys.path.insert(0,'$W/py-st2'); import heartbeat.doctor" || fail "selftest: stripped doctor.py no longer imports"
  ( cd "$P2" && HB_PY_SRC="$W/py-st2" PY doctor --dir "$P2" 2>&1 | grep -qi "detached" ) && fail "selftest: python doctor note survived its guard strip"
  echo "DETACH-SURFACING-SELFTEST-OK"
}

if [ "${1:-}" = "--selftest" ]; then selftest; exit 0; fi
sel="${1:-all}"
for c in marker clear quiet doctor audit; do
  if [ "$sel" = all ] || [ "$sel" = "$c" ]; then "case_$c" || exit 1; fi
done
[ "$sel" = all ] && echo "DETACH-SURFACING-OK"
exit 0
