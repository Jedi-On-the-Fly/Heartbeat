#!/usr/bin/env bash
# regate-rearm.sh — `hb regate --rearm`: evidence-gated re-grounding + stale-pass invalidation (RG2 spec).
#
# Rearm re-enables a revised gate ONLY behind the full bar: a well-formed pending record; a DIFFERENT
# actor than the declarer (case-insensitive); a substantive artifact (>=40 trimmed chars) citing a real
# phase anchor; a deterministically audit-clean dag. Success stores the artifact bytes at
# .hb/reviews/<G>.regate.md, pins sha256+actor+model on an audit-only gate_rearmed event and the dag
# rearm record, and re-enables evaluation — but NOT acceptance: every review verdict stays REFUSED
# until a FRESH PROVENANCED gate_passed (criteria/runtime stamped — hb import's bare synthetic pass
# never counts) lands after the rearm, the review CYCLE restarts at the rearm (a pre-declare
# constraint set or free review never satisfies the post-rearm acceptance), doctor re-checks the
# stored evidence forever, diagnose routes to the rearm recovery, and a resumed executor in the
# stale window escalates without dispatching.
#
# Guard-marker contract (selftest teeth; all single-line, strip-clean): regate-guard: rearm-actor,
# rearm-audit, stale-pass (node hb.js + py review_policy), cycle-start (node hb.js reviewCycle + py
# constraints), rearm-rot + marker-sync + stale-accepted (both doctors), stale-resume (both executors).
#
#   bash tests/regate-rearm.sh [case]   cases: matrix success stale cycle doctor diagnose resume
#   bash tests/regate-rearm.sh --selftest
# Prints <CASE>-OK per case, REGATE-REARM-OK when all pass, REGATE-REARM-SELFTEST-OK for teeth.
set -u
unset HB_DIR PROJECT_DIR GATE G DAG_FILE EVENTS_FILE 2>/dev/null || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
fail(){ echo "FAIL: $1"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
PY(){ PYTHONPATH="${HB_PY_SRC:-$ROOT/py/src}" python3 -m heartbeat.cli "$@"; }
printf '#!/usr/bin/env bash\nPYTHONPATH="${HB_PY_SRC:-%s/py/src}" exec python3 -m heartbeat.cli "$@"\n' "$ROOT" > "$W/hbpy"; chmod +x "$W/hbpy"

mkproj(){   # $1 = dir — A (side-effect gate, reviewless), B (constrained review), C (gateless)
  mkdir -p "$1"; ( cd "$1" && git init -q >/dev/null 2>&1; bash "$ROOT/plugin/bootstrap.sh" . >/dev/null 2>&1 )
  cat > "$1/.hb/dag.json" <<'EOF'
{"project":"rearm-fixture",
 "phases":[
  {"id":"A","title":"side-effect gate","gate_entry":null,"gate_exit":"GATE_A",
   "tasks":[{"id":"a1","title":"produce the observed behavior","requires":[],"description":"the gate observes executed.flag"}]},
  {"id":"B","title":"constrained review","gate_entry":"GATE_A","gate_exit":"GATE_B",
   "tasks":[{"id":"b1","title":"reviewed work","requires":[],"description":"work behind an adversarial review; writes m.txt"}]},
  {"id":"C","title":"gateless","gate_entry":null,"gate_exit":null,
   "tasks":[{"id":"c1","title":"no gate","requires":[],"description":"a phase with no gate_exit"}]}],
 "gates":{
  "GATE_A":{"desc":"touches executed.flag — eval is OBSERVABLE","criteria":[
    {"id":"ga1","desc":"observable eval","cmd":"touch \"$PROJECT_DIR/executed.flag\""}]},
  "GATE_B":{"desc":"reviewed gate","review":{"prompt":"Refute that B is done.","constraints":[
    {"id":"P1","claim":"b1 did real work","subjects":["m.txt"],"violation":"m.txt absent"}]},"criteria":[
    {"id":"gb1","desc":"behavioral","cmd":"python3 -c \"assert 1+1==2\""}]}}}
EOF
}
mkrace(){   # $1 = dir — single phase R, UNCONSTRAINED review gate (executor resume fixture)
  mkdir -p "$1"; ( cd "$1" && git init -q >/dev/null 2>&1; bash "$ROOT/plugin/bootstrap.sh" . >/dev/null 2>&1 )
  cat > "$1/.hb/dag.json" <<'EOF'
{"project":"rearm-resume",
 "phases":[{"id":"R","title":"resumed","gate_entry":null,"gate_exit":"GATE_R",
   "tasks":[{"id":"r1","title":"work","requires":[],"description":"work whose review resumes after a rearm"}]}],
 "gates":{"GATE_R":{"desc":"unconstrained reviewed gate","review":{"prompt":"Refute that R is done."},
   "criteria":[{"id":"gr1","desc":"behavioral","cmd":"python3 -c \"assert 1+1==2\""}]}}}
EOF
}
evcount(){ grep -Ec "\"event\": ?\"$2\"" "$1/.hb/events.jsonl" 2>/dev/null || true; }
revcount(){ grep -Ec '"event": ?"(review_passed|review_failed|free_review_recorded)"' "$1/.hb/events.jsonl" 2>/dev/null || true; }
marker(){ python3 -c "
import json,sys
d=json.load(open('$1/.hb/dag.json')); m=(d['gates'].get('$2') or {}).get('regate')
sys.exit(0 if m is not None and ($3) else 1)"; }
edit_criteria(){   # $1 = proj  $2 = gate — the sanctioned revision step: re-point the criterion
  python3 -c "
import json; p='$1/.hb/dag.json'; d=json.load(open(p))
d['gates']['$2']['criteria']=[{'id':'rev1','desc':'revised behavioral','cmd':'python3 -c \"assert 2+2==4\"'}]
json.dump(d,open(p,'w'),indent=2)"
}
good_artifact(){   # $1 = file  $2 = gate  $3 = task — substantive + anchor-citing
  printf 'Rearm evidence for %s (phase of task %s): the dev-mode volume premise died; the revised criterion was run by hand and exercises the real behavior now.\n' "$2" "$3" > "$1"
}
declare_b(){ ( cd "$1" && HB_ACTOR=alice node .hb/hb.js regate "$2" premises died: volumes replaced >/dev/null 2>&1 ); }

# review-owed fixture on GATE_B: b1 done (+ the others), m.txt real, det pass recorded
owed_b(){   # $1 = dir
  mkproj "$1"
  ( cd "$1" && HB_ACTOR=doer node .hb/hb.js start b1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done b1 >/dev/null )
  printf 'the real work of b1\n' > "$1/m.txt"
  ( cd "$1" && bash .hb/gate.sh GATE_B >/dev/null 2>&1 )
}

# ── case: matrix ──────────────────────────────────────────────────────────────
try_rearm_node(){ ( cd "$1" && HB_ACTOR="${3:-bob}" node .hb/hb.js regate "$2" --rearm --artifact "${4:-evidence.md}" ${5:+--model "$5"} 2>&1 ); }
try_rearm_py(){ ( cd "$1" && HB_ACTOR="${3:-bob}" PY regate "$2" --rearm --artifact "${4:-evidence.md}" ${5:+--model "$5"} --dir "$1" 2>&1 ); }
matrix_one(){   # $1 = runtime (node|py)
  local P="$W/mx-$1"; owed_b "$P"
  local try="try_rearm_$1" out
  # no pending regate
  out=$($try "$P" GATE_A bob) && fail "matrix($1): rearm with NO pending regate accepted"
  echo "$out" | grep -qi "no pending regate" || fail "matrix($1): wrong no-pending message: $out"
  declare_b "$P" GATE_B; edit_criteria "$P" GATE_B; good_artifact "$P/evidence.md" GATE_B b1
  # unset HB_ACTOR
  ( cd "$P" && env -u HB_ACTOR node .hb/hb.js regate GATE_B --rearm --artifact evidence.md ) >/dev/null 2>&1 && fail "matrix($1): rearm with unset HB_ACTOR accepted"
  # the DECLARER rearms, case varied
  out=$($try "$P" GATE_B ALICE) && fail "matrix($1): the declarer rearmed their own revision (case-varied)"
  echo "$out" | grep -qi "different" || fail "matrix($1): same-actor refusal does not demand a different actor: $out"
  # missing artifact file
  out=$($try "$P" GATE_B bob nope.md) && fail "matrix($1): a missing artifact file was accepted"
  # thin artifact
  printf 'too thin\n' > "$P/thin.md"
  out=$($try "$P" GATE_B bob thin.md) && fail "matrix($1): a 9-char artifact was accepted"
  # cites nothing from the phase
  printf 'Fifty characters of generic filler prose that references nothing real at all.\n' > "$P/filler.md"
  out=$($try "$P" GATE_B bob filler.md) && fail "matrix($1): an artifact citing nothing was accepted"
  # dag not audit-clean: hollow revision
  python3 -c "
import json; p='$P/.hb/dag.json'; d=json.load(open(p))
d['gates']['GATE_B']['criteria']=[{'id':'h1','desc':'hollow','cmd':'true'}]
json.dump(d,open(p,'w'),indent=2)"
  out=$($try "$P" GATE_B bob) && fail "matrix($1): a HOLLOW revision was rearmed"
  echo "$out" | grep -qi "audit" || fail "matrix($1): the hollow refusal does not name the audit: $out"
  edit_criteria "$P" GATE_B
  # every row left pending untouched, no event, no stored artifact
  marker "$P" GATE_B "m['pending'] is True" || fail "matrix($1): a refused rearm cleared pending"
  [ "$(evcount "$P" gate_rearmed)" = 0 ] || fail "matrix($1): a refused rearm appended gate_rearmed"
  [ ! -f "$P/.hb/reviews/GATE_B.regate.md" ] || fail "matrix($1): a refused rearm stored an artifact"
}
case_matrix(){ matrix_one node; matrix_one py; echo "MATRIX-OK"; }

# ── case: success ─────────────────────────────────────────────────────────────
success_one(){   # $1 = runtime
  local P="$W/ok-$1"; owed_b "$P"
  declare_b "$P" GATE_B; edit_criteria "$P" GATE_B; good_artifact "$P/evidence.md" GATE_B b1
  ( cd "$P" && node .hb/hb.js rebuild >/dev/null ); cp "$P/.hb/state.json" "$W/ok-$1.state"
  local try="try_rearm_$1" out
  out=$($try "$P" GATE_B bob evidence.md sonnet) || fail "success($1): a valid rearm was refused: $out"
  echo "$out" | grep -qi "re-enabled" || fail "success($1): no loud re-enable line: $out"
  echo "$out" | grep -qi "fresh pass" || fail "success($1): the re-enable line does not owe a fresh pass: $out"
  marker "$P" GATE_B "m['pending'] is False and m['rearm']['actor']=='bob' and m['rearm']['model']=='sonnet' and m['rearm']['artifact']=='reviews/GATE_B.regate.md' and isinstance(m['rearm'].get('sha256'),str)" \
    || fail "success($1): rearm record wrong (pending/actor/model/artifact/sha256)"
  cmp -s "$P/evidence.md" "$P/.hb/reviews/GATE_B.regate.md" || fail "success($1): stored artifact bytes differ from the evidence"
  python3 -c "
import hashlib, json, sys
want = hashlib.sha256(open('$P/.hb/reviews/GATE_B.regate.md','rb').read()).hexdigest()
ev = [json.loads(l) for l in open('$P/.hb/events.jsonl') if l.strip()]
re = [e for e in ev if e.get('event') == 'gate_rearmed']
assert len(re) == 1, 'want exactly 1 gate_rearmed, got %d' % len(re)
e = re[0]
assert e.get('sha256') == want, 'event sha256 does not pin the stored bytes'
assert e.get('actor') == 'bob' and e.get('model') == 'sonnet' and e.get('artifact') == 'reviews/GATE_B.regate.md'
m = json.load(open('$P/.hb/dag.json'))['gates']['GATE_B']['regate']
assert m['rearm']['sha256'] == want, 'dag rearm sha256 does not pin the stored bytes'
" || fail "success($1): gate_rearmed provenance wrong"
  python3 -c "
import json
a=json.load(open('$W/ok-$1.state')); b=json.load(open('$P/.hb/state.json'))
keys=['current_phase','active_tasks','completed_tasks','completed_phases','pending_reviews','build_stuck_count','gate']
assert all(a[k]==b[k] for k in keys)" || fail "success($1): gate_rearmed changed the state projection"
  # evaluation re-enabled: the revised gate runs its criteria again
  if [ "$1" = node ]; then ( cd "$P" && bash .hb/gate.sh GATE_B >/dev/null 2>&1 ) || fail "success($1): the rearmed gate did not evaluate"
  else ( cd "$P" && PY gate GATE_B --dir "$P" >/dev/null 2>&1 ) || fail "success($1): the rearmed gate did not evaluate (py)"; fi
  [ "$(evcount "$P" gate_passed)" = 2 ] || fail "success($1): no fresh gate_passed after the rearm"
}
case_success(){ success_one node; success_one py; echo "SUCCESS-OK"; }

# ── case: stale-pass invalidation (+ the import attack) ───────────────────────
case_stale(){
  # reviewless ACCEPTED gate: pass → declare → edit → rearm → verdicts refused until a FRESH
  # PROVENANCED pass; hb import's bare synthetic pass must not unlock anything.
  local P="$W/stale"; mkproj "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start a1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done a1 >/dev/null )
  ( cd "$P" && bash .hb/gate.sh GATE_A >/dev/null 2>&1 ); rm -f "$P/executed.flag"
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js regate GATE_A dev volumes replaced >/dev/null 2>&1 )
  python3 -c "
import json; p='$P/.hb/dag.json'; d=json.load(open(p))
d['gates']['GATE_A']['criteria']=[{'id':'rev1','desc':'revised observable','cmd':'touch \"\$PROJECT_DIR/executed.flag\"'}]
json.dump(d,open(p,'w'),indent=2)"
  good_artifact "$P/evidence.md" GATE_A a1
  try_rearm_node "$P" GATE_A bob >/dev/null || fail "stale: setup rearm refused"
  printf 'I tried to refute GATE_A / phase A (task a1): inspected executed.flag behavior.\nHOLES: none\n' > "$P/findings.md"
  local out v
  for v in pass fail free; do
    out=$( cd "$P" && HB_ACTOR=rev node .hb/hb.js review GATE_A "$v" --artifact findings.md 2>&1 ) && fail "stale: node review $v accepted over a stale pre-rearm pass"
    echo "$out" | grep -Eqi "stale|fresh pass|re-run" || fail "stale: node $v refusal does not name the stale pass: $out"
    out=$( cd "$P" && HB_ACTOR=rev PY review GATE_A "$v" --artifact findings.md --dir "$P" 2>&1 ) && fail "stale: python review $v accepted over a stale pre-rearm pass"
    echo "$out" | grep -Eqi "stale|fresh pass|re-run" || fail "stale: python $v refusal does not name the stale pass: $out"
  done
  [ "$(revcount "$P")" = 0 ] || fail "stale: a refused stale verdict appended a review event"
  # the import attack: a bare synthetic gate_passed must NOT satisfy the fresh-pass rule
  ( cd "$P" && node .hb/hb.js import >/dev/null 2>&1 )
  grep -Eq '"event": ?"gate_passed"[^\n]*"gate": ?"GATE_A"' "$P/.hb/events.jsonl" || true
  out=$( cd "$P" && HB_ACTOR=rev node .hb/hb.js review GATE_A fail note 2>&1 ) && fail "stale: hb import's synthetic pass UNLOCKED the verdicts (node)"
  out=$( cd "$P" && HB_ACTOR=rev PY review GATE_A fail note --dir "$P" 2>&1 ) && fail "stale: a synthetic pass unlocked the verdicts (python)"
  ( cd "$P" && node .hb/hb.js doctor 2>&1 | grep -qi "stale" ) && DOC_OK=1 || DOC_OK=0
  [ "$DOC_OK" = 1 ] || fail "stale: doctor does not flag the accepted gate with a rearm newer than its last provenanced pass"
  # a FRESH provenanced pass unlocks
  ( cd "$P" && bash .hb/gate.sh GATE_A >/dev/null 2>&1 ) || fail "stale: the revised gate did not pass"
  [ -f "$P/executed.flag" ] || fail "stale: the revised criterion did not run"
  ( cd "$P" && HB_ACTOR=rev node .hb/hb.js review GATE_A fail "post-fresh-pass finding" >/dev/null 2>&1 ) || fail "stale: a verdict after a FRESH pass was still refused (node)"
  echo "STALE-OK"
}

# ── case: review-cycle restarts at the rearm ──────────────────────────────────
case_cycle(){
  local P="$W/cyc"; owed_b "$P"
  printf '[{"id":"G1","claim":"m.txt holds b1 work","subjects":["m.txt"],"violation":"m.txt absent"}]' > "$P/g.json"
  ( cd "$P" && HB_ACTOR=author node .hb/hb.js constraints GATE_B --record g.json >/dev/null 2>&1 ) || fail "cycle: pre-declare set not recorded"
  declare_b "$P" GATE_B; edit_criteria "$P" GATE_B; good_artifact "$P/evidence.md" GATE_B b1
  try_rearm_node "$P" GATE_B bob >/dev/null || fail "cycle: rearm refused"
  ( cd "$P" && bash .hb/gate.sh GATE_B >/dev/null 2>&1 ) || fail "cycle: fresh pass failed"
  # BOTH runtimes agree: the pre-declare set does not satisfy the post-rearm cycle
  node -e "
const hb = require('$P/.hb/hb.js');
const dag = JSON.parse(require('fs').readFileSync('$P/.hb/dag.json','utf8'));
process.env.HB_DIR = '$P/.hb';
const cyc = hb.reviewCycle(dag, 'GATE_B');
process.exit(cyc.recorded ? 1 : 0);" 2>/dev/null
  [ $? -eq 0 ] || fail "cycle: node reviewCycle still counts the pre-declare set after the rearm"
  PYTHONPATH="${HB_PY_SRC:-$ROOT/py/src}" python3 -c "
from heartbeat import constraints as c, state as st
dag = st.read_dag('$P/.hb')
pending, recorded, _ev, start = c.review_cycle_full('$P/.hb', dag, 'GATE_B')
assert not recorded, 'python still counts the pre-declare set after the rearm'
p2, r2, _e2 = c.review_cycle('$P/.hb', dag, 'GATE_B')
assert r2 == recorded, 'review_cycle and review_cycle_full disagree on recorded'
" || fail "cycle: python cycle boundary wrong"
  # a pass without a fresh set is refused; a FRESH set is recordable (write-once afresh); then pass
  cat > "$P/answers.md" <<'EOF'
Refutation of GATE_B (phase B, task b1): I ran the revised criterion and probed m.txt.
P1: NOT-REPRODUCED — m.txt exists with b1's content; probe: cat m.txt.
G1: NOT-REPRODUCED — same probe; the subject file holds the work.
EOF
  local out
  out=$( cd "$P" && HB_ACTOR=rev node .hb/hb.js review GATE_B pass --artifact answers.md 2>&1 ) && fail "cycle: pass accepted with only the PRE-DECLARE constraint set"
  echo "$out" | grep -qi "no gate-time constraints" || fail "cycle: wrong refusal (want: no set in this cycle): $out"
  ( cd "$P" && HB_ACTOR=author2 node .hb/hb.js constraints GATE_B --record g.json >/dev/null 2>&1 ) || fail "cycle: a fresh set was not recordable after the rearm (write-once must apply afresh)"
  ( cd "$P" && HB_ACTOR=rev node .hb/hb.js review GATE_B pass --artifact answers.md >/dev/null 2>&1 ) || fail "cycle: pass refused even with the fresh set + answers"
  # FREE-REVIEW boundary: a pre-declare free review must not satisfy the post-rearm cycle
  local F="$W/cyc-free"; owed_b "$F"
  cat > "$F/.hb/refuters/freeprof.json" <<'EOF'
{"persona": "You are a refuter. End with REFUTED or CLEAR.", "questions": [], "free_review": true}
EOF
  python3 -c "
import json; p='$F/.hb/dag.json'; d=json.load(open(p))
d['gates']['GATE_B']['review']['profile']='freeprof'
json.dump(d,open(p,'w'),indent=2)"
  printf '[{"id":"G1","claim":"m.txt holds b1 work","subjects":["m.txt"],"violation":"m.txt absent"}]' > "$F/g.json"
  ( cd "$F" && HB_ACTOR=author node .hb/hb.js constraints GATE_B --record g.json >/dev/null 2>&1 ) || fail "cycle(free): set not recorded"
  printf 'Free breadth review of GATE_B (task b1): looked widely, found nothing.\nHOLES: none\n' > "$F/free.md"
  ( cd "$F" && HB_ACTOR=freerev node .hb/hb.js review GATE_B free --artifact free.md >/dev/null 2>&1 ) || fail "cycle(free): pre-declare free review not recorded"
  declare_b "$F" GATE_B; edit_criteria "$F" GATE_B; good_artifact "$F/evidence.md" GATE_B b1
  try_rearm_node "$F" GATE_B bob >/dev/null || fail "cycle(free): rearm refused"
  ( cd "$F" && bash .hb/gate.sh GATE_B >/dev/null 2>&1 ) || fail "cycle(free): fresh pass failed"
  ( cd "$F" && HB_ACTOR=author2 node .hb/hb.js constraints GATE_B --record g.json >/dev/null 2>&1 ) || fail "cycle(free): fresh set not recordable"
  cp "$P/answers.md" "$F/answers.md"
  out=$( cd "$F" && HB_ACTOR=rev node .hb/hb.js review GATE_B pass --artifact answers.md 2>&1 ) && fail "cycle(free): the PRE-DECLARE free review satisfied the post-rearm pass"
  echo "$out" | grep -qi "free review" || fail "cycle(free): wrong refusal (want: free review owed): $out"
  ( cd "$F" && HB_ACTOR=freerev2 node .hb/hb.js review GATE_B free --artifact free.md >/dev/null 2>&1 ) || fail "cycle(free): a fresh free review was refused"
  ( cd "$F" && HB_ACTOR=rev node .hb/hb.js review GATE_B pass --artifact answers.md >/dev/null 2>&1 ) || fail "cycle(free): pass refused even after the fresh free review"
  echo "CYCLE-OK"
}

# ── case: doctor ──────────────────────────────────────────────────────────────
doctor_both(){   # $1 = proj  $2 = problem|note|clean  $3 = grep pattern  $4 = label
  local n p
  n=$( cd "$1" && node .hb/hb.js doctor 2>&1 ); p=$( cd "$1" && PY doctor --dir "$1" 2>&1 )
  echo "$n" | grep -qi "$3" || fail "doctor($4): node missing '$3': $n"
  echo "$p" | grep -qi "$3" || fail "doctor($4): python missing '$3': $p"
}
case_doctor(){
  # pending → NOTE (doctor stays healthy)
  local P="$W/doc-pend"; owed_b "$P"; declare_b "$P" GATE_B
  doctor_both "$P" note "regate" "pending-note"
  ( cd "$P" && node .hb/hb.js doctor >/dev/null 2>&1 ) || fail "doctor: a pending regate alone must be a NOTE, not a problem (node exit 1)"
  # rearm artifact rot: missing / emptied / byte-flipped → PROBLEM on both
  local Q="$W/doc-rot"; owed_b "$Q"; declare_b "$Q" GATE_B; edit_criteria "$Q" GATE_B
  good_artifact "$Q/evidence.md" GATE_B b1; try_rearm_node "$Q" GATE_B bob >/dev/null || fail "doctor: setup rearm refused"
  cp "$Q/.hb/reviews/GATE_B.regate.md" "$W/doc-rot.bak"
  rm "$Q/.hb/reviews/GATE_B.regate.md"
  doctor_both "$Q" problem "regate" "artifact-missing"
  ( cd "$Q" && node .hb/hb.js doctor >/dev/null 2>&1 ) && fail "doctor: a missing rearm artifact is not a PROBLEM"
  printf 'thin\n' > "$Q/.hb/reviews/GATE_B.regate.md"
  ( cd "$Q" && node .hb/hb.js doctor >/dev/null 2>&1 ) && fail "doctor: an emptied rearm artifact is not a PROBLEM"
  cp "$W/doc-rot.bak" "$Q/.hb/reviews/GATE_B.regate.md"; printf 'x' >> "$Q/.hb/reviews/GATE_B.regate.md"
  ( cd "$Q" && node .hb/hb.js doctor 2>&1 | grep -qi "sha256\|changed" ) || fail "doctor: a byte-flipped rearm artifact is not flagged (node)"
  ( cd "$Q" && PY doctor --dir "$Q" 2>&1 | grep -qi "sha256\|changed" ) || fail "doctor: a byte-flipped rearm artifact is not flagged (python)"
  cp "$W/doc-rot.bak" "$Q/.hb/reviews/GATE_B.regate.md"
  ( cd "$Q" && node .hb/hb.js doctor >/dev/null 2>&1 ) || fail "doctor: a restored artifact still flagged"
  # marker cross-check: the log attests a pending regate, the dag lost the marker
  local M="$W/doc-sync"; owed_b "$M"; declare_b "$M" GATE_B
  python3 -c "
import json; p='$M/.hb/dag.json'; d=json.load(open(p)); d['gates']['GATE_B'].pop('regate',None); json.dump(d,open(p,'w'),indent=2)"
  doctor_both "$M" problem "regate" "marker-sync"
  ( cd "$M" && node .hb/hb.js doctor >/dev/null 2>&1 ) && fail "doctor: a log-attested regate with no dag marker is not a PROBLEM"
  echo "DOCTOR-OK"
}

# ── case: diagnose ────────────────────────────────────────────────────────────
case_diagnose(){
  local P="$W/diag"; owed_b "$P"; declare_b "$P" GATE_B
  local n p
  for mode in "regate_pending" ""; do
    n=$( cd "$P" && node .hb/hb.js diagnose $mode 2>&1 ); p=$( cd "$P" && PY diagnose $mode --dir "$P" 2>&1 )
    echo "$n" | grep -q "GATE_B" && echo "$n" | grep -q "volumes replaced" && echo "$n" | grep -q -- "--rearm" \
      || fail "diagnose(node,${mode:-inferred}): missing gate/reason/recovery: $n"
    echo "$p" | grep -q "GATE_B" && echo "$p" | grep -q "volumes replaced" && echo "$p" | grep -q -- "--rearm" \
      || fail "diagnose(py,${mode:-inferred}): missing gate/reason/recovery: $p"
  done
  # precedence: a stale gate_failed coexists — gate_blocked must route to the rearm recovery,
  # never print a command the perimeter refuses
  local B="$W/diag-blocked"; mkproj "$B"
  python3 -c "
import json; p='$B/.hb/dag.json'; d=json.load(open(p))
d['gates']['GATE_A']['criteria']=[{'id':'ga1','desc':'failing','cmd':'false'}]
json.dump(d,open(p,'w'),indent=2)"
  ( cd "$B" && bash .hb/gate.sh GATE_A >/dev/null 2>&1 )   # gate_failed → gate.errors
  ( cd "$B" && HB_ACTOR=alice node .hb/hb.js regate GATE_A premises died >/dev/null 2>&1 )
  n=$( cd "$B" && node .hb/hb.js diagnose 2>&1 ); p=$( cd "$B" && PY diagnose --dir "$B" 2>&1 )
  echo "$n" | grep -q -- "--rearm" || fail "diagnose(node,precedence): gate_blocked branch does not route to the rearm recovery: $n"
  echo "$p" | grep -q -- "--rearm" || fail "diagnose(py,precedence): gate_blocked branch does not route to the rearm recovery: $p"
  echo "DIAGNOSE-OK"
}

# ── case: post-rearm executor resumption ──────────────────────────────────────
case_resume(){
  local exr P out rc
  for exr in node py; do
    P="$W/resume-$exr"; mkrace "$P"
    ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start r1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done r1 >/dev/null )
    ( cd "$P" && bash .hb/gate.sh GATE_R >/dev/null 2>&1 )   # det pass, review owed
    ( cd "$P" && HB_ACTOR=alice node .hb/hb.js regate GATE_R premise died >/dev/null 2>&1 )
    python3 -c "
import json; p='$P/.hb/dag.json'; d=json.load(open(p))
d['gates']['GATE_R']['criteria']=[{'id':'rev1','desc':'revised','cmd':'python3 -c \"assert 3+3==6\"'}]
json.dump(d,open(p,'w'),indent=2)"
    good_artifact "$P/evidence.md" GATE_R r1
    try_rearm_node "$P" GATE_R bob >/dev/null || fail "resume($exr): setup rearm refused"
    # the natural post-rearm state: review_pending with a STALE pre-rearm pass. A resumed executor
    # must escalate — no backend dispatch, no review event.
    printf '#!/usr/bin/env bash\nmode="${!#}"; cat >/dev/null; touch "%s/dispatched.$mode"; echo "{\\"refuted\\":false,\\"findings\\":\\"should never be asked\\"}"\n' "$P" > "$P/be.sh"; chmod +x "$P/be.sh"
    if [ "$exr" = node ]; then
      out=$( cd "$P" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $P/be.sh" timeout 90 node .hb/hb-exec.js run 2>&1 ); rc=$?
    else
      out=$( cd "$P" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $P/be.sh" timeout 90 "$W/hbpy" exec run --dir "$P" 2>&1 ); rc=$?
    fi
    [ "$rc" -ne 124 ] || fail "resume($exr): executor busy-looped in the stale window"
    [ ! -f "$P/dispatched.refute" ] || fail "resume($exr): the executor dispatched a refuter over a STALE pre-rearm pass"
    [ "$(revcount "$P")" = 0 ] || fail "resume($exr): a review event landed in the stale window"
    echo "$out" | grep -i "hb-exec stop" | grep -Eqi "stale|re-run|revised" || fail "resume($exr): no loud stale-window escalation: $out"
  done
  echo "RESUME-OK"
}

# ── case: truth — the log outranks the marker; thin boundary is runtime-identical ─
case_truth(){
  # (1) thin-artifact boundary PARITY: the SAME bytes must get the SAME verdict on both runtimes
  # (JS trim() vs str.strip() diverge on U+FEFF/U+0085 — the explicit ASCII trim removes that)
  local p1="$W/tr-n" p2="$W/tr-p" art rc_n rc_p
  for art in feff nel astral plain39; do
    rm -rf "$p1" "$p2"; owed_b "$p1"; owed_b "$p2"
    declare_b "$p1" GATE_B; edit_criteria "$p1" GATE_B
    declare_b "$p2" GATE_B; edit_criteria "$p2" GATE_B
    python3 -c "
import sys
body = {'feff': 'GATE_B b1 premise died rearm evidence pad!' .ljust(39)[:39] + '﻿',
        'nel':  'GATE_B b1 premise died rearm.' + '\u0085' * 12,
        'astral': 'GATE_B b1 premise died rearm evid'[:30].ljust(30, 'x') + '\U0001F600' * 5,
        'plain39': 'GATE_B b1 premise died evidence pad 39c'[:39]}['$art']
for d in ('$p1', '$p2'):
    open(d + '/evidence.md', 'w', encoding='utf-8').write(body)"
    try_rearm_node "$p1" GATE_B bob >/dev/null 2>&1; rc_n=$?
    try_rearm_py "$p2" GATE_B bob >/dev/null 2>&1; rc_p=$?
    [ "$rc_n" = "$rc_p" ] || fail "truth($art): the SAME artifact bytes got different verdicts (node=$rc_n py=$rc_p) — the thin boundary diverges"
  done
  [ "$rc_n" -ne 0 ] || fail "truth(plain39): a 39-char artifact was accepted"
  # (2) the HAND-CLEAR exploit: pending set to false by hand (no rearm) — the log is truth:
  # verdicts refused on BOTH runtimes, constraints refused, doctor flags the cleared marker
  local X="$W/clear"; owed_b "$X"; declare_b "$X" GATE_B; edit_criteria "$X" GATE_B
  python3 -c "
import json; p='$X/.hb/dag.json'; d=json.load(open(p)); d['gates']['GATE_B']['regate']['pending']=False; json.dump(d,open(p,'w'),indent=2)"
  ( cd "$X" && bash .hb/gate.sh GATE_B >/dev/null 2>&1 )   # eval re-enabled by the hand edit — the ACCEPTANCE must still refuse
  printf 'I tried to refute GATE_B (task b1): probed the revised criterion.\nHOLES: none\n' > "$X/findings.md"
  local out v
  for v in pass fail; do
    out=$( cd "$X" && HB_ACTOR=rev node .hb/hb.js review GATE_B "$v" --artifact findings.md 2>&1 ) && fail "truth: node review $v ACCEPTED over a hand-cleared marker (the exploit)"
    echo "$out" | grep -qi "unanswered" || fail "truth: node $v refusal does not cite the log: $out"
    out=$( cd "$X" && HB_ACTOR=rev PY review GATE_B "$v" --artifact findings.md --dir "$X" 2>&1 ) && fail "truth: python review $v ACCEPTED over a hand-cleared marker"
    echo "$out" | grep -qi "unanswered" || fail "truth: python $v refusal does not cite the log: $out"
  done
  [ "$(revcount "$X")" = 0 ] || fail "truth: a verdict event landed over a hand-cleared marker"
  printf '[{"id":"G1","claim":"m.txt holds b1 work","subjects":["m.txt"],"violation":"absent"}]' > "$X/g.json"
  ( cd "$X" && HB_ACTOR=author node .hb/hb.js constraints GATE_B --record g.json ) >/dev/null 2>&1 && fail "truth: constraints recorded over a hand-cleared marker"
  doctor_both "$X" problem "cleared marker\|fabricated" "hand-clear"
  ( cd "$X" && node .hb/hb.js doctor >/dev/null 2>&1 ) && fail "truth: doctor healthy over a hand-cleared marker"
  # recovery from the hand edit: RE-DECLARE (the cleared marker allows it), then a proper rearm —
  # the single gate_rearmed answers BOTH declares in the log
  declare_b "$X" GATE_B || fail "truth: the recovery re-declare was refused"
  good_artifact "$X/evidence.md" GATE_B b1
  try_rearm_node "$X" GATE_B bob >/dev/null || fail "truth: recovery rearm refused"
  ( cd "$X" && bash .hb/gate.sh GATE_B >/dev/null 2>&1 )
  ( cd "$X" && HB_ACTOR=rev node .hb/hb.js review GATE_B fail "a finding, properly" >/dev/null 2>&1 ) || fail "truth: a verdict refused even after the proper rearm + fresh pass"
  # (3) a FABRICATED rearm record (pending:false + rearm pin with no event) → doctor problem
  local Y="$W/fab"; owed_b "$Y"; declare_b "$Y" GATE_B
  python3 -c "
import json; p='$Y/.hb/dag.json'; d=json.load(open(p))
d['gates']['GATE_B']['regate']['pending']=False
d['gates']['GATE_B']['regate']['rearm']={'actor':'evil','artifact':'reviews/GATE_B.regate.md','sha256':'deadbeef'*8}
json.dump(d,open(p,'w'),indent=2)"
  doctor_both "$Y" problem "fabricated\|no gate_rearmed" "fabricated-rearm"
  echo "TRUTH-OK"
}

# ── selftest: mutation teeth ──────────────────────────────────────────────────
mutate(){ local before; before=$(grep -c "$2" "$1" 2>/dev/null || true); [ "${before:-0}" -gt 0 ] || fail "selftest: no '$2' marker in $1"; sed -i "/$2/d" "$1"; }
mkpycopy(){ cp -r "$ROOT/py/src" "$1"; }
selftest(){
  local P out
  # s1: node rearm-actor guard stripped → the declarer rearms their own revision (red)
  P="$W/s1"; owed_b "$P"; declare_b "$P" GATE_B; edit_criteria "$P" GATE_B; good_artifact "$P/evidence.md" GATE_B b1
  mutate "$P/.hb/hb.js" "regate-guard: rearm-actor"
  try_rearm_node "$P" GATE_B ALICE >/dev/null 2>&1 || fail "selftest s1: same-actor rearm still refused after the guard strip (sed missed?)"
  marker "$P" GATE_B "m['pending'] is False" || fail "selftest s1: the stripped guard did not let the rearm land (not load-bearing)"
  # s2: node rearm-audit guard stripped → a hollow revision rearms (red)
  P="$W/s2"; owed_b "$P"; declare_b "$P" GATE_B
  python3 -c "
import json; p='$P/.hb/dag.json'; d=json.load(open(p))
d['gates']['GATE_B']['criteria']=[{'id':'h1','desc':'hollow','cmd':'true'}]
json.dump(d,open(p,'w'),indent=2)"
  good_artifact "$P/evidence.md" GATE_B b1
  mutate "$P/.hb/hb.js" "regate-guard: rearm-audit"
  try_rearm_node "$P" GATE_B bob >/dev/null 2>&1 || fail "selftest s2: hollow rearm still refused after the audit guard strip"
  # s3: python rearm-actor guard stripped → same-actor rearm lands (red)
  P="$W/s3"; owed_b "$P"; declare_b "$P" GATE_B; edit_criteria "$P" GATE_B; good_artifact "$P/evidence.md" GATE_B b1
  mkpycopy "$W/py-s3"; mutate "$W/py-s3/heartbeat/cli.py" "regate-guard: rearm-actor"
  ( cd "$P" && HB_ACTOR=ALICE HB_PY_SRC="$W/py-s3" PY regate GATE_B --rearm --artifact evidence.md --dir "$P" >/dev/null 2>&1 ) \
    || fail "selftest s3: python same-actor rearm still refused after the guard strip"
  # s4: node stale-pass guard stripped → a verdict lands over a stale pass (red)
  P="$W/s4"; mkproj "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start a1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done a1 >/dev/null )
  ( cd "$P" && bash .hb/gate.sh GATE_A >/dev/null 2>&1 )
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js regate GATE_A died >/dev/null 2>&1 )
  python3 -c "
import json; p='$P/.hb/dag.json'; d=json.load(open(p))
d['gates']['GATE_A']['criteria']=[{'id':'rev1','desc':'revised','cmd':'python3 -c \"assert 1\"'}]
json.dump(d,open(p,'w'),indent=2)"
  good_artifact "$P/evidence.md" GATE_A a1
  try_rearm_node "$P" GATE_A bob >/dev/null || fail "selftest s4: setup rearm refused"
  mutate "$P/.hb/hb.js" "regate-guard: stale-pass"
  ( cd "$P" && HB_ACTOR=rev node .hb/hb.js review GATE_A fail finding >/dev/null 2>&1 ) || fail "selftest s4: stale verdict still refused after the guard strip"
  [ "$(revcount "$P")" != 0 ] || fail "selftest s4: the stripped stale-pass guard did not let the verdict land"
  # s5: python stale-pass guard stripped → accept_review lands a stale verdict (red)
  mkpycopy "$W/py-s5"; mutate "$W/py-s5/heartbeat/review_policy.py" "regate-guard: stale-pass"
  P="$W/s5"; mkproj "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start a1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done a1 >/dev/null )
  ( cd "$P" && bash .hb/gate.sh GATE_A >/dev/null 2>&1 )
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js regate GATE_A died >/dev/null 2>&1 )
  good_artifact "$P/evidence.md" GATE_A a1
  try_rearm_node "$P" GATE_A bob >/dev/null || fail "selftest s5: setup rearm refused"
  PYTHONPATH="$W/py-s5" python3 -c "
import os; os.environ['HB_ACTOR']='rev'
from heartbeat import review_policy
rc,_o,_e = review_policy.accept_review('$P/.hb','GATE_A','fail',note='x')
raise SystemExit(0 if rc==0 else 1)" || fail "selftest s5: python stale verdict still refused after the guard strip"
  # s6: cycle-start boundary stripped → the pre-declare set survives the rearm (red)
  P="$W/s6"; owed_b "$P"
  printf '[{"id":"G1","claim":"m.txt holds b1 work","subjects":["m.txt"],"violation":"m.txt absent"}]' > "$P/g.json"
  ( cd "$P" && HB_ACTOR=author node .hb/hb.js constraints GATE_B --record g.json >/dev/null 2>&1 )
  declare_b "$P" GATE_B; edit_criteria "$P" GATE_B; good_artifact "$P/evidence.md" GATE_B b1
  try_rearm_node "$P" GATE_B bob >/dev/null || fail "selftest s6: setup rearm refused"
  ( cd "$P" && bash .hb/gate.sh GATE_B >/dev/null 2>&1 )
  mutate "$P/.hb/hb.js" "regate-guard: cycle-start"
  node -e "
const hb = require('$P/.hb/hb.js');
process.env.HB_DIR = '$P/.hb';
const dag = JSON.parse(require('fs').readFileSync('$P/.hb/dag.json','utf8'));
process.exit(hb.reviewCycle(dag, 'GATE_B').recorded ? 0 : 1);" 2>/dev/null \
    || fail "selftest s6: the stripped boundary still invalidates the pre-declare set (not load-bearing)"
  # s7: doctor rearm-rot guard stripped → a byte-flipped artifact goes unflagged (red)
  P="$W/s7"; owed_b "$P"; declare_b "$P" GATE_B; edit_criteria "$P" GATE_B; good_artifact "$P/evidence.md" GATE_B b1
  try_rearm_node "$P" GATE_B bob >/dev/null || fail "selftest s7: setup rearm refused"
  printf 'x' >> "$P/.hb/reviews/GATE_B.regate.md"
  mutate "$P/.hb/hb.js" "regate-guard: rearm-rot"
  ( cd "$P" && node .hb/hb.js doctor 2>&1 | grep -qi "regate" ) && fail "selftest s7: doctor still flags the artifact after the rot guard strip"
  # s8: executor stale-resume guards stripped → a dispatch happens in the stale window (red)
  P="$W/s8"; mkrace "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start r1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done r1 >/dev/null )
  ( cd "$P" && bash .hb/gate.sh GATE_R >/dev/null 2>&1 )
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js regate GATE_R died >/dev/null 2>&1 )
  good_artifact "$P/evidence.md" GATE_R r1
  try_rearm_node "$P" GATE_R bob >/dev/null || fail "selftest s8: setup rearm refused"
  printf '#!/usr/bin/env bash\nmode="${!#}"; cat >/dev/null; touch "%s/dispatched.$mode"; echo "{\\"refuted\\":false,\\"findings\\":\\"fifty chars of findings about GATE_R and r1 for substance\\"}"\n' "$P" > "$P/be.sh"; chmod +x "$P/be.sh"
  mutate "$P/.hb/hb-exec.js" "regate-guard: stale-resume"
  ( cd "$P" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $P/be.sh" timeout 90 node .hb/hb-exec.js run >/dev/null 2>&1 )
  [ -f "$P/dispatched.refute" ] || fail "selftest s8: stripping the stale-resume guard did not re-open the dispatch (not load-bearing)"
  mkpycopy "$W/py-s8"; mutate "$W/py-s8/heartbeat/executor.py" "regate-guard: stale-resume"
  rm -f "$P/dispatched.refute"
  ( cd "$P" && HB_PY_SRC="$W/py-s8" HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $P/be.sh" timeout 90 "$W/hbpy" exec run --dir "$P" >/dev/null 2>&1 )
  [ -f "$P/dispatched.refute" ] || fail "selftest s8: stripping the python stale-resume guard did not re-open the dispatch"
  # s9: doctor marker-sync guard stripped → the log/dag divergence goes silent (red)
  P="$W/s9"; owed_b "$P"; declare_b "$P" GATE_B
  python3 -c "
import json; p='$P/.hb/dag.json'; d=json.load(open(p)); d['gates']['GATE_B'].pop('regate',None); json.dump(d,open(p,'w'),indent=2)"
  mutate "$P/.hb/hb.js" "regate-guard: marker-sync"
  ( cd "$P" && node .hb/hb.js doctor 2>&1 | grep -qi "regate" ) && fail "selftest s9: doctor still flags the marker divergence after the guard strip"
  # s10: the log-truth guards stripped → the hand-clear exploit succeeds again (red), both runtimes
  P="$W/s10"; owed_b "$P"; declare_b "$P" GATE_B; edit_criteria "$P" GATE_B
  python3 -c "
import json; p='$P/.hb/dag.json'; d=json.load(open(p)); d['gates']['GATE_B']['regate']['pending']=False; json.dump(d,open(p,'w'),indent=2)"
  ( cd "$P" && bash .hb/gate.sh GATE_B >/dev/null 2>&1 )
  printf 'I tried to refute GATE_B (task b1): probed the revised criterion.\nHOLES: none\n' > "$P/findings.md"
  mutate "$P/.hb/hb.js" "regate-guard: log-truth"
  ( cd "$P" && HB_ACTOR=rev node .hb/hb.js review GATE_B fail finding >/dev/null 2>&1 ) || fail "selftest s10: node verdict still refused after the log-truth strip"
  mkpycopy "$W/py-s10"; mutate "$W/py-s10/heartbeat/review_policy.py" "regate-guard: log-truth"
  PYTHONPATH="$W/py-s10" python3 -c "
import os; os.environ['HB_ACTOR']='rev2'
from heartbeat import review_policy
rc,_o,_e = review_policy.accept_review('$P/.hb','GATE_B','fail',note='x')
raise SystemExit(0 if rc==0 else 1)" || fail "selftest s10: python verdict still refused after the log-truth strip"
  echo "REGATE-REARM-SELFTEST-OK"
}

# ── dispatch ──────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--selftest" ]; then selftest; exit 0; fi
sel="${1:-all}"
for c in matrix success stale cycle doctor diagnose resume truth; do
  if [ "$sel" = all ] || [ "$sel" = "$c" ]; then "case_$c" || exit 1; fi
done
[ "$sel" = all ] && echo "REGATE-REARM-OK"
exit 0
