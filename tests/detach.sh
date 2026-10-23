#!/usr/bin/env bash
# detach.sh — `hb detach`/`hb reattach`: retract a dependency CLAIM, loudly and reversibly (DT1 spec).
#
# Detach sets a phase's gate_entry to null (the resolver's EXISTING unlocked semantics — zero
# resolver change), recording {detached_from, detached_reason, detached_by, detached_at} and an
# audit-only phase_detached, under the write lock. The declare writes a DETACH-TIME ANCHOR
# (anchors/_detach_<PHASE>.json, direct write, stamped with detached_at, rewritten per declare) so
# `hb changed` reports against the detach moment — never widening to _start, never lying after a
# re-detach or a late predecessor acceptance. The weasel-vector warning fires per-channel: a live
# gate_failed, a live review_failed (a later gate_passed does NOT clear it), a blocking regate, an
# unanswered regate in the log, or a stale rearm. Reattach restores and refuses a resolver brick.
#
# Guard markers (strip-clean single lines): detach-guard: validate | warn | anchor | reattach |
# changed-base, plus lint call-site markers — declarations and STRUCTURAL lines (the withWlock
# wrappers) carry no markers: the lock's teeth are the 6-way race, not a line mutant (a refuter
# catch: a marked structural line strips into a SyntaxError, red for the wrong reason).
# --selftest strips each class from a COPY and expects the named check red for the RIGHT reason.
#
#   bash tests/detach.sh [case]   cases: declare races weasel resolver base lint
#   bash tests/detach.sh --selftest
# Prints <CASE>-OK per case, DETACH-OK when all pass, DETACH-SELFTEST-OK for teeth.
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

mkproj(){   # $1 = dir — P (reviewless predecessor, ok-file gate), D (depends on GATE_P), X (independent)
  mkdir -p "$1"; ( cd "$1" && git init -q >/dev/null 2>&1; bash "$ROOT/plugin/bootstrap.sh" . >/dev/null 2>&1 )
  cat > "$1/.hb/dag.json" <<'EOF'
{"project":"detach-fixture",
 "phases":[
  {"id":"P","title":"predecessor","gate_entry":null,"gate_exit":"GATE_P",
   "tasks":[{"id":"p1","title":"p work","requires":[],"description":"produces ok"}]},
  {"id":"D","title":"dependent","gate_entry":"GATE_P","gate_exit":"GATE_D",
   "tasks":[{"id":"d1","title":"d work","requires":[],"description":"produces dwork.txt"}]},
  {"id":"X","title":"independent","gate_entry":null,"gate_exit":"GATE_X",
   "tasks":[{"id":"x1","title":"x work","requires":[],"description":"independent"}]}],
 "gates":{
  "GATE_P":{"desc":"p gate","criteria":[{"id":"gp1","desc":"ok exists behaviorally","cmd":"[ -f \"$PROJECT_DIR/ok\" ] && python3 -c \"assert 1\""}]},
  "GATE_D":{"desc":"d gate","criteria":[{"id":"gd1","desc":"behavioral","cmd":"python3 -c \"assert 1+1==2\""}]},
  "GATE_X":{"desc":"x gate","criteria":[{"id":"gx1","desc":"behavioral","cmd":"python3 -c \"assert 2+2==4\""}]}}}
EOF
}
mkrev(){   # $1 = dir — review-gated predecessor variant
  mkproj "$1"
  python3 -c "
import json; p='$1/.hb/dag.json'; d=json.load(open(p))
d['gates']['GATE_P']['review']={'prompt':'Refute that P is done.'}
d['gates']['GATE_P']['criteria']=[{'id':'gp1','desc':'behavioral','cmd':'python3 -c \"assert 1\"'}]
json.dump(d,open(p,'w'),indent=2)"
}
evcount(){ grep -Ec "\"event\": ?\"$2\"" "$1/.hb/events.jsonl" 2>/dev/null || true; }
dfield(){   # $1=proj $2=phase $3=python expr over p (the phase dict); exit 0 if truthy
  python3 -c "
import json,sys
d=json.load(open('$1/.hb/dag.json')); p=next(x for x in d['phases'] if x['id']=='$2')
sys.exit(0 if ($3) else 1)"; }
detach_n(){ ( cd "$1" && HB_ACTOR="${3:-alice}" node .hb/hb.js detach "$2" premises changed: dependency obsolete 2>&1 ); }
detach_p(){ ( cd "$1" && HB_ACTOR="${3:-alice}" PY detach "$2" --reason "premises changed: dependency obsolete" --dir "$1" 2>&1 ); }

# ── case: declare + reattach ──────────────────────────────────────────────────
case_declare(){
  local P="$W/dec" out
  mkproj "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start p1 >/dev/null )   # _start anchor
  out=$(detach_n "$P" D) || fail "declare: node detach refused: $out"
  echo "$out" | head -1 | grep -q "detached D from GATE_P" || fail "declare: output does not lead with 'detached D from GATE_P': $out"
  dfield "$P" D "p.get('gate_entry') is None and p['detached_from']=='GATE_P' and p['detached_by']=='alice' and p['detached_reason'].startswith('premises changed') and isinstance(p.get('detached_at'),str) and p['detached_at']" \
    || fail "declare: node detach fields wrong"
  [ "$(evcount "$P" phase_detached)" = 1 ] || fail "declare: no phase_detached event"
  [ -f "$P/.hb/anchors/_detach_D.json" ] || fail "declare: no detach anchor written"
  python3 -c "
import json,sys
a=json.load(open('$P/.hb/anchors/_detach_D.json'))
d=json.load(open('$P/.hb/dag.json')); p=next(x for x in d['phases'] if x['id']=='D')
sys.exit(0 if a.get('detached_at')==p['detached_at'] and isinstance(a.get('files'),dict) else 1)" \
    || fail "declare: anchor not stamped with the phase's detached_at"
  # refusal ladder — loud, event-free, dag-neutral
  local n0; n0=$(evcount "$P" phase_detached)
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js detach D another go ) >/dev/null 2>&1 && fail "declare: already-detached accepted"
  out=$( cd "$P" && HB_ACTOR=alice node .hb/hb.js detach D another go 2>&1 ); echo "$out" | grep -qi reattach || fail "declare: already-detached message does not route to reattach: $out"
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js detach X some reason ) >/dev/null 2>&1 && fail "declare: null-entry never-detached phase accepted"
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js detach NOPE some reason ) >/dev/null 2>&1 && fail "declare: unknown id accepted"
  ( cd "$P" && env -u HB_ACTOR node .hb/hb.js detach D r ) >/dev/null 2>&1 && fail "declare: unset HB_ACTOR accepted"
  ( cd "$P" && HB_ACTOR=unknown node .hb/hb.js detach D r ) >/dev/null 2>&1 && fail "declare: HB_ACTOR=unknown accepted"
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js detach D ) >/dev/null 2>&1 && fail "declare: empty reason accepted"
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js detach 'bad/../id' r ) >/dev/null 2>&1 && fail "declare: unsafe phase id accepted"
  [ "$(evcount "$P" phase_detached)" = "$n0" ] || fail "declare: a refused declare appended an event"
  # completed phase: pass GATE_X → X complete → detach... X has null entry; use a completed D-like:
  local C="$W/dec-done"; mkproj "$C"
  : > "$C/ok"; ( cd "$C" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 )
  ( cd "$C" && bash .hb/gate.sh GATE_D >/dev/null 2>&1 )   # D complete (reviewless)
  ( cd "$C" && HB_ACTOR=alice node .hb/hb.js detach D r ) >/dev/null 2>&1 && fail "declare: a COMPLETED phase was detached"
  # reattach: restore + clear + event; brick refusal
  ( cd "$P" && node .hb/hb.js reattach D >/dev/null 2>&1 ) || fail "reattach: refused on a detached phase"
  dfield "$P" D "p.get('gate_entry')=='GATE_P' and 'detached_from' not in p and 'detached_reason' not in p and 'detached_by' not in p and 'detached_at' not in p" \
    || fail "reattach: fields not restored/cleared"
  [ "$(evcount "$P" phase_reattached)" = 1 ] || fail "reattach: no phase_reattached event"
  ( cd "$P" && node .hb/hb.js reattach D ) >/dev/null 2>&1 && fail "reattach: accepted on a non-detached phase"
  # the resolver brick: detached_from kept a DEFINED gate that is no phase's gate_exit
  detach_n "$P" D bob >/dev/null || fail "reattach: re-detach for the brick fixture refused"
  python3 -c "
import json; p='$P/.hb/dag.json'; d=json.load(open(p))
ph=next(x for x in d['phases'] if x['id']=='P'); ph['gate_exit']='GATE_P_RENAMED'
d['gates']['GATE_P_RENAMED']=d['gates']['GATE_P']
json.dump(d,open(p,'w'),indent=2)"
  ( cd "$P" && node .hb/hb.js reattach D ) >/dev/null 2>&1 && fail "reattach: restored a gate that is no phase's gate_exit (resolver brick)"
  # python mirror on a fresh fixture
  local Q="$W/dec-py"; mkproj "$Q"
  ( cd "$Q" && HB_ACTOR=doer node .hb/hb.js start p1 >/dev/null )
  out=$(detach_p "$Q" D) || fail "declare: python detach refused: $out"
  echo "$out" | head -1 | grep -q "detached D from GATE_P" || fail "declare: python output does not lead correctly: $out"
  dfield "$Q" D "p.get('gate_entry') is None and p['detached_from']=='GATE_P' and p['detached_by']=='alice'" || fail "declare: python fields wrong"
  [ "$(evcount "$Q" phase_detached)" = 1 ] && [ -f "$Q/.hb/anchors/_detach_D.json" ] || fail "declare: python event/anchor missing"
  ( cd "$Q" && HB_ACTOR=alice PY detach D --reason "" --dir "$Q" ) >/dev/null 2>&1 && fail "declare: python empty reason accepted"
  ( cd "$Q" && PY reattach D --dir "$Q" ) >/dev/null 2>&1 || fail "reattach: python refused on a detached phase"
  dfield "$Q" D "p.get('gate_entry')=='GATE_P' and 'detached_from' not in p" || fail "reattach: python restore wrong"
  echo "DECLARE-OK"
}

# ── case: races ───────────────────────────────────────────────────────────────
case_races(){
  local P="$W/race" i
  mkproj "$P"; ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start p1 >/dev/null )
  for i in 1 2 3 4 5 6; do ( cd "$P" && HB_ACTOR="r$i" node .hb/hb.js detach D race $i >/dev/null 2>&1 ) & done; wait
  [ "$(evcount "$P" phase_detached)" = 1 ] || fail "races: $(evcount "$P" phase_detached) phase_detached events from 6 concurrent declares (want 1 — the lock is broken)"   # detach-guard: lock is load-bearing here
  [ -f "$P/.hb/anchors/_detach_D.json" ] || fail "races: the winning declare wrote no anchor"
  # detach vs park of ANOTHER phase: both edits survive (the wave-1 lost-update class)
  for i in 1 2 3 4 5 6; do
    local K="$W/race-park-$i"; mkproj "$K"; ( cd "$K" && HB_ACTOR=doer node .hb/hb.js start p1 >/dev/null )
    ( cd "$K" && HB_ACTOR=alice node .hb/hb.js detach D race reason >/dev/null 2>&1 ) &
    ( cd "$K" && node .hb/hb.js park X parked meanwhile >/dev/null 2>&1 ) &
    wait
    dfield "$K" D "p.get('detached_from')=='GATE_P'" || fail "races: a concurrent park ERASED the detach (trial $i)"
    dfield "$K" X "p.get('parked') is True" || fail "races: the detach erased the park (trial $i)"
  done
  # detach vs regate declare on the SAME dag: both markers survive
  for i in 1 2 3; do
    local R="$W/race-rg-$i"; mkproj "$R"; ( cd "$R" && HB_ACTOR=doer node .hb/hb.js start p1 >/dev/null )
    ( cd "$R" && HB_ACTOR=alice node .hb/hb.js detach D race reason >/dev/null 2>&1 ) &
    ( cd "$R" && HB_ACTOR=carol node .hb/hb.js regate GATE_X premises died >/dev/null 2>&1 ) &
    wait
    dfield "$R" D "p.get('detached_from')=='GATE_P'" || fail "races: a concurrent regate erased the detach (trial $i)"
    python3 -c "
import json,sys; d=json.load(open('$R/.hb/dag.json'))
sys.exit(0 if (d['gates']['GATE_X'].get('regate') or {}).get('pending') is True else 1)" || fail "races: the detach erased the regate marker (trial $i)"
  done
  echo "RACES-OK"
}

# ── case: the weasel predicate, per channel ───────────────────────────────────
expect_warn(){ echo "$2" | grep -qi "REMOVED, not satisfied" || fail "weasel($1): no warning where one is owed: $2"; }
expect_clean(){ echo "$2" | grep -qi "REMOVED, not satisfied" && fail "weasel($1): warned on a clean detach: $2"; return 0; }
case_weasel(){
  local P out
  # live gate_failed → WARN
  P="$W/wz-fail"; mkproj "$P"; ( cd "$P" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 )   # no ok file → fails
  out=$(detach_n "$P" D); expect_warn live-failed "$out"
  # healed (gate_failed then gate_passed, reviewless) → CLEAN
  P="$W/wz-heal"; mkproj "$P"; ( cd "$P" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 ); : > "$P/ok"; ( cd "$P" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 )
  out=$(detach_n "$P" D); expect_clean healed "$out"
  # never evaluated → CLEAN; and the DISCRIMINATOR: live failures on a DIFFERENT gate stay irrelevant
  P="$W/wz-never"; mkproj "$P"
  printf '%s\n' '{"event":"gate_failed","gate":"GATE_X","pass":0,"fail":1}' '{"event":"gate_passed","gate":"GATE_X"}' '{"event":"review_failed","gate":"GATE_X","note":"other gate"}' >> "$P/.hb/events.jsonl"
  ( cd "$P" && node .hb/hb.js rebuild >/dev/null )
  out=$(detach_n "$P" D); expect_clean discriminator "$out"
  # refuted → WARN; refuted STEADY STATE (re-run det-passed, review owed) → WARN; review-accepted → CLEAN
  P="$W/wz-ref"; mkrev "$P"; ( cd "$P" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 )
  ( cd "$P" && HB_ACTOR=rev node .hb/hb.js review GATE_P fail "a hole" >/dev/null 2>&1 )
  out=$(detach_n "$P" D); expect_warn refuted "$out"
  P="$W/wz-steady"; mkrev "$P"; ( cd "$P" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 )
  ( cd "$P" && HB_ACTOR=rev node .hb/hb.js review GATE_P fail "a hole" >/dev/null 2>&1 )
  ( cd "$P" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 )   # re-run det-passes; review still owed
  out=$(detach_n "$P" D); expect_warn steady-state "$out"
  P="$W/wz-accepted"; mkrev "$P"; ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start p1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done p1 >/dev/null )
  ( cd "$P" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 )
  printf 'I tried to refute GATE_P (task p1): ran the criteria, probed the behavior, nothing broke.\nHOLES: none\n' > "$P/f.md"
  ( cd "$P" && HB_ACTOR=rev node .hb/hb.js review GATE_P pass --artifact f.md >/dev/null 2>&1 ) || fail "weasel: accepted-fixture review pass refused"
  out=$(detach_n "$P" D); expect_clean review-accepted "$out"
  # pending regate → WARN; hand-cleared marker → WARN; stale rearm → WARN
  P="$W/wz-regate"; mkproj "$P"; : > "$P/ok"; ( cd "$P" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 )
  ( cd "$P" && HB_ACTOR=carol node .hb/hb.js regate GATE_P premise died >/dev/null 2>&1 )
  out=$(detach_n "$P" D); expect_warn pending-regate "$out"
  python3 -c "
import json; p='$P/.hb/dag.json'; d=json.load(open(p)); d['gates']['GATE_P']['regate']['pending']=False; json.dump(d,open(p,'w'),indent=2)"
  ( cd "$P" && node .hb/hb.js reattach D >/dev/null 2>&1 )
  out=$(detach_n "$P" D bob); expect_warn hand-cleared "$out"
  P="$W/wz-stale"; mkproj "$P"; : > "$P/ok"; ( cd "$P" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 )
  ( cd "$P" && HB_ACTOR=carol node .hb/hb.js regate GATE_P premise died >/dev/null 2>&1 )
  python3 -c "
import json; p='$P/.hb/dag.json'; d=json.load(open(p))
d['gates']['GATE_P']['criteria']=[{'id':'rev1','desc':'revised','cmd':'python3 -c \"assert 3\"'}]
json.dump(d,open(p,'w'),indent=2)"
  printf 'Rearm evidence for GATE_P (task p1): the premise died; the revised criterion was run by hand.\n' > "$P/e.md"
  ( cd "$P" && HB_ACTOR=dave node .hb/hb.js regate GATE_P --rearm --artifact e.md >/dev/null 2>&1 ) || fail "weasel: stale-fixture rearm refused"
  out=$(detach_n "$P" D); expect_warn stale-rearm "$out"
  # the warning never weakens the revised gate's own perimeter
  ( cd "$W/wz-regate" && HB_ACTOR=rev node .hb/hb.js review GATE_P fail x ) >/dev/null 2>&1 && fail "weasel: the detach weakened the regate perimeter (verdict accepted)"
  # python parity on two arms (steady-state + clean)
  P="$W/wz-py"; mkrev "$P"; ( cd "$P" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 )
  ( cd "$P" && HB_ACTOR=rev node .hb/hb.js review GATE_P fail "a hole" >/dev/null 2>&1 )
  ( cd "$P" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 )
  out=$(detach_p "$P" D); expect_warn py-steady "$out"
  P="$W/wz-py2"; mkproj "$P"; out=$(detach_p "$P" D); expect_clean py-never "$out"
  echo "WEASEL-OK"
}

# ── case: resolver reuse (zero resolver change) ───────────────────────────────
case_resolver(){
  local P="$W/res"; mkproj "$P"
  ( cd "$P" && node .hb/hb.js ready 9 2>/dev/null | grep -q '"d1"' ) && fail "resolver: d1 ready while locked behind GATE_P"
  detach_n "$P" D >/dev/null || fail "resolver: detach refused"
  ( cd "$P" && node .hb/hb.js ready 9 2>/dev/null | grep -q '"d1"' ) || fail "resolver: d1 still locked after detach (node)"
  ( cd "$P" && PY ready 9 --dir "$P" 2>/dev/null | grep -q '"d1"' ) || fail "resolver: d1 still locked after detach (python)"
  echo "RESOLVER-OK"
}

# ── case: the changed base (the detach anchor) ────────────────────────────────
case_base(){
  local P="$W/base"; mkproj "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start p1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done p1 >/dev/null )   # _start on the pristine tree
  printf 'other-phase noise\n' > "$P/noise.txt"   # work _start would wrongly attribute to D
  detach_n "$P" D >/dev/null || fail "base: detach refused"
  printf 'd work\n' > "$P/dwork.txt"
  local c1n c1p
  c1n=$( cd "$P" && node .hb/hb.js changed GATE_D 2>&1 )
  echo "$c1n" | grep -q "dwork.txt" || fail "base(1): d's own work missing (node): $c1n"
  echo "$c1n" | grep -q "noise.txt" && fail "base(1): widened to _start — pre-detach noise reported (node): $c1n"
  c1p=$( cd "$P" && PY changed GATE_D --dir "$P" 2>&1 )
  echo "$c1p" | grep -q "dwork.txt" || fail "base(1): python missing dwork"
  echo "$c1p" | grep -q "noise.txt" && fail "base(1): python widened to _start"
  # (2) LATE ACCEPTANCE: GATE_P accepted after the detach — the base must not shift
  : > "$P/ok"; ( cd "$P" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 ) || fail "base(2): GATE_P pass failed"
  local c2n; c2n=$( cd "$P" && node .hb/hb.js changed GATE_D 2>&1 )
  echo "$c2n" | grep -q "dwork.txt" || fail "base(2): late acceptance HID d's work (the base shifted): $c2n"
  echo "$c2n" | grep -q "noise.txt" && fail "base(2): base shifted wide after late acceptance: $c2n"
  # (6) stamp mismatch → treated missing → _start fallback (noise appears)
  python3 -c "
import json; p='$P/.hb/anchors/_detach_D.json'; a=json.load(open(p)); a['detached_at']='1999-01-01T00:00:00Z'; json.dump(a,open(p,'w'))"
  local c6; c6=$( cd "$P" && node .hb/hb.js changed GATE_D 2>&1 )
  echo "$c6" | grep -q "noise.txt" || fail "base(6): a stamp-mismatched anchor was trusted (must fall back to _start): $c6"
  ( cd "$P" && PY changed GATE_D --dir "$P" 2>&1 | grep -q "noise.txt" ) || fail "base(6): python trusted the mismatched stamp"
  # (3) missing anchor → _start fallback
  rm "$P/.hb/anchors/_detach_D.json"
  ( cd "$P" && node .hb/hb.js changed GATE_D 2>&1 | grep -q "noise.txt" ) || fail "base(3): missing anchor did not fall back to _start"
  # (4) reattach → gate_entry wins (GATE_P's acceptance anchor is now the base)
  ( cd "$P" && node .hb/hb.js reattach D >/dev/null 2>&1 ) || fail "base(4): reattach refused"
  printf 'post-reattach work\n' > "$P/rwork.txt"
  local c4; c4=$( cd "$P" && node .hb/hb.js changed GATE_D 2>&1 )
  echo "$c4" | grep -q "rwork.txt" || fail "base(4): post-reattach work missing"
  echo "$c4" | grep -q "dwork.txt" && fail "base(4): gate_entry base not restored (pre-acceptance work still reported): $c4"
  # (5) RE-DETACH: the anchor must be REWRITTEN (write-once would still show rwork)
  detach_n "$P" D bob >/dev/null || fail "base(5): re-detach refused"
  printf 'post second detach\n' > "$P/post2.txt"
  local c5n c5p
  c5n=$( cd "$P" && node .hb/hb.js changed GATE_D 2>&1 )
  echo "$c5n" | grep -q "post2.txt" || fail "base(5): post-re-detach work missing"
  echo "$c5n" | grep -q "rwork.txt" && fail "base(5): STALE anchor — pre-re-detach work reported (write-once lie): $c5n"
  c5p=$( cd "$P" && PY changed GATE_D --dir "$P" 2>&1 )
  echo "$c5p" | grep -q "post2.txt" || fail "base(5): python missing post2"
  echo "$c5p" | grep -q "rwork.txt" && fail "base(5): python reported the write-once lie"
  echo "BASE-OK"
}

# ── case: lint runnables ──────────────────────────────────────────────────────
lint_err(){   # $1 = proj — both lints must ERROR non-emptily, mentioning detach
  local n p
  n=$(node "$1/.hb/hb-lint.js" "$1/.hb/dag.json" 2>&1) && fail "lint($2): node accepted the malformed record"
  echo "$n" | grep -qiE "detach|_detach_|_start" || fail "lint($2): node error does not name the rule: $n"
  p=$( PY lint "$1/.hb/dag.json" --dir "$1" 2>&1 ) && fail "lint($2): python accepted the malformed record"
  echo "$p" | grep -qiE "detach|_detach_|_start" || fail "lint($2): python error does not name the rule: $p"
}
case_lint(){
  local P
  for k in partial nonnull notexit emptyts reserved unsafeid; do
    P="$W/lint-$k"; mkproj "$P"
    python3 - "$P/.hb/dag.json" "$k" <<'EOF'
import json, sys
p, k = sys.argv[1], sys.argv[2]
d = json.load(open(p))
D = next(x for x in d["phases"] if x["id"] == "D")
full = {"detached_from": "GATE_P", "detached_reason": "r", "detached_by": "a", "detached_at": "2026-01-01T00:00:00Z"}
if k == "partial":
    D["gate_entry"] = None; D["detached_from"] = "GATE_P"            # missing the other fields
elif k == "nonnull":
    D.update(full)                                                    # fields but gate_entry still set
elif k == "notexit":
    D["gate_entry"] = None; D.update(full); D["detached_from"] = "GATE_X_ORPHAN"
    d["gates"]["GATE_X_ORPHAN"] = {"desc": "defined but no phase exits through it", "criteria": [{"id": "c", "desc": "d", "cmd": "python3 -c 'assert 1'"}]}
elif k == "emptyts":
    D["gate_entry"] = None; D.update(full); D["detached_at"] = "  "
elif k == "reserved":
    d["gates"]["_detach_EVIL"] = {"desc": "reserved name", "criteria": [{"id": "c", "desc": "d", "cmd": "python3 -c 'assert 1'"}]}
elif k == "unsafeid":
    d["phases"].append({"id": "../evil", "title": "bad", "gate_entry": None, "gate_exit": None, "tasks": []})
    d["phases"][-1].update(full)
json.dump(d, open(p, "w"), indent=2)
EOF
    lint_err "$P" "$k"
  done
  # a WELL-FORMED detach lints clean
  P="$W/lint-ok"; mkproj "$P"; detach_n "$P" D >/dev/null
  node "$P/.hb/hb-lint.js" "$P/.hb/dag.json" >/dev/null 2>&1 || fail "lint: node rejected a well-formed detach"
  PY lint "$P/.hb/dag.json" --dir "$P" >/dev/null 2>&1 || fail "lint: python rejected a well-formed detach"
  echo "LINT-OK"
}

# ── selftest: mutation teeth ──────────────────────────────────────────────────
mutate(){ local b; b=$(grep -c "$2" "$1" 2>/dev/null || true); [ "${b:-0}" -gt 0 ] || fail "selftest: no '$2' marker in $1"; sed -i "/$2/d" "$1"; }
mkpycopy(){ cp -r "$ROOT/py/src" "$1"; }
selftest(){
  local P out
  # s1: validate guard stripped → the refusal ladder re-opens (empty reason accepted), file still parses
  P="$W/s1"; mkproj "$P"
  mutate "$P/.hb/hb.js" "detach-guard: validate"
  node --check "$P/.hb/hb.js" 2>/dev/null || fail "selftest s1: stripped hb.js no longer parses"
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js detach D ) >/dev/null 2>&1 || fail "selftest s1: empty reason still refused after the validate strip"
  # s2: warn guard stripped → the refuted fixture detaches silently (red)
  P="$W/s2"; mkrev "$P"; ( cd "$P" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 )
  ( cd "$P" && HB_ACTOR=rev node .hb/hb.js review GATE_P fail hole >/dev/null 2>&1 )
  mutate "$P/.hb/hb.js" "detach-guard: warn"
  out=$(detach_n "$P" D 2>&1)
  echo "$out" | grep -qi "REMOVED, not satisfied" && fail "selftest s2: the warning survived its guard strip"
  # s3: anchor guard stripped → no anchor written → base(1) widens (red)
  P="$W/s3"; mkproj "$P"; ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start p1 >/dev/null )
  printf 'noise\n' > "$P/noise.txt"
  mutate "$P/.hb/hb.js" "detach-guard: anchor"
  detach_n "$P" D >/dev/null 2>&1
  [ -f "$P/.hb/anchors/_detach_D.json" ] && fail "selftest s3: the anchor survived its guard strip"
  ( cd "$P" && node .hb/hb.js changed GATE_D 2>&1 | grep -q "noise.txt" ) || fail "selftest s3: the strip did not re-open the _start widening (not load-bearing)"
  # s4: changed-base guard stripped → even a good anchor is ignored → widening (red)
  P="$W/s4"; mkproj "$P"; ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start p1 >/dev/null )
  printf 'noise\n' > "$P/noise.txt"
  detach_n "$P" D >/dev/null || fail "selftest s4: setup detach refused"
  mutate "$P/.hb/hb.js" "detach-guard: changed-base"
  ( cd "$P" && node .hb/hb.js changed GATE_D 2>&1 | grep -q "noise.txt" ) || fail "selftest s4: changed still honored the anchor after the strip"
  # s5: reattach guard stripped → the resolver-brick restore is accepted (red)
  P="$W/s5"; mkproj "$P"; detach_n "$P" D >/dev/null
  python3 -c "
import json; p='$P/.hb/dag.json'; d=json.load(open(p))
ph=next(x for x in d['phases'] if x['id']=='P'); ph['gate_exit']='GATE_P2'; d['gates']['GATE_P2']=d['gates']['GATE_P']
json.dump(d,open(p,'w'),indent=2)"
  mutate "$P/.hb/hb.js" "detach-guard: reattach"
  ( cd "$P" && node .hb/hb.js reattach D ) >/dev/null 2>&1 || fail "selftest s5: the brick restore still refused after the strip"
  # s6: node lint guard stripped → a malformed record lints clean (red)
  P="$W/s6"; mkproj "$P"
  python3 -c "
import json; p='$P/.hb/dag.json'; d=json.load(open(p))
D=next(x for x in d['phases'] if x['id']=='D'); D['gate_entry']=None; D['detached_from']='GATE_P'
json.dump(d,open(p,'w'),indent=2)"
  mutate "$P/.hb/hb-lint.js" "detach-guard"
  node "$P/.hb/hb-lint.js" "$P/.hb/dag.json" >/dev/null 2>&1 || fail "selftest s6: node lint still errors after the strip"
  mkpycopy "$W/py-s6"; mutate "$W/py-s6/heartbeat/lint.py" "detach-guard"
  HB_PY_SRC="$W/py-s6" PY lint "$P/.hb/dag.json" --dir "$P" >/dev/null 2>&1 || fail "selftest s6: python lint still errors after the strip"
  # s7: python warn guard stripped → the steady-state fixture detaches silently (red)
  P="$W/s7"; mkrev "$P"; ( cd "$P" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 )
  ( cd "$P" && HB_ACTOR=rev node .hb/hb.js review GATE_P fail hole >/dev/null 2>&1 )
  ( cd "$P" && bash .hb/gate.sh GATE_P >/dev/null 2>&1 )
  mkpycopy "$W/py-s7"; mutate "$W/py-s7/heartbeat/cli.py" "detach-guard: warn"
  out=$( cd "$P" && HB_ACTOR=alice HB_PY_SRC="$W/py-s7" PY detach D --reason "r" --dir "$P" 2>&1 )
  echo "$out" | grep -qi "REMOVED, not satisfied" && fail "selftest s7: the python warning survived its guard strip"
  # s8: python changed-base guard stripped → widening (red)
  P="$W/s8"; mkproj "$P"; ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start p1 >/dev/null )
  printf 'noise\n' > "$P/noise.txt"
  detach_n "$P" D >/dev/null || fail "selftest s8: setup detach refused"
  mkpycopy "$W/py-s8"; mutate "$W/py-s8/heartbeat/anchors.py" "detach-guard: changed-base"
  ( cd "$P" && HB_PY_SRC="$W/py-s8" PY changed GATE_D --dir "$P" 2>&1 | grep -q "noise.txt" ) || fail "selftest s8: python changed still honored the anchor after the strip"
  # s9: python validate guard stripped → empty reason accepted (red), module still imports
  P="$W/s9"; mkproj "$P"
  mkpycopy "$W/py-s9"; mutate "$W/py-s9/heartbeat/cli.py" "detach-guard: validate"
  HB_PY_SRC="$W/py-s9" python3 -c "import sys; sys.path.insert(0,'$W/py-s9'); import heartbeat.cli" || fail "selftest s9: stripped cli.py no longer imports"
  ( cd "$P" && HB_ACTOR=alice HB_PY_SRC="$W/py-s9" PY detach D --reason "" --dir "$P" ) >/dev/null 2>&1 || fail "selftest s9: python empty reason still refused after the validate strip"
  # s10: python reattach guard stripped → the resolver-brick restore is accepted (red)
  P="$W/s10"; mkproj "$P"; detach_n "$P" D >/dev/null
  python3 -c "
import json; p='$P/.hb/dag.json'; d=json.load(open(p))
ph=next(x for x in d['phases'] if x['id']=='P'); ph['gate_exit']='GATE_P2'; d['gates']['GATE_P2']=d['gates']['GATE_P']
json.dump(d,open(p,'w'),indent=2)"
  mkpycopy "$W/py-s10"; mutate "$W/py-s10/heartbeat/cli.py" "detach-guard: reattach"
  ( cd "$P" && HB_PY_SRC="$W/py-s10" PY reattach D --dir "$P" ) >/dev/null 2>&1 || fail "selftest s10: the python brick restore still refused after the strip"
  echo "DETACH-SELFTEST-OK"
}

# ── dispatch ──────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--selftest" ]; then selftest; exit 0; fi
sel="${1:-all}"
for c in declare races weasel resolver base lint; do
  if [ "$sel" = all ] || [ "$sel" = "$c" ]; then "case_$c" || exit 1; fi
done
[ "$sel" = all ] && echo "DETACH-OK"
exit 0
