#!/usr/bin/env bash
# regate-fail-closed.sh — `hb regate` declare + the fail-closed perimeter (RG1 spec, spec-first RED).
#
# A gate whose PREMISES died mid-project (deleted volumes, a dev-mode assumption) today forces an
# unaudited hand-edit. `hb regate` is the sanctioned path: DECLARE snapshots the criteria and marks
# the gate pending; while pending, EVERY evaluation/acceptance path refuses fail-closed — loudly,
# with a DISTINCT signal (gate.sh exit 3), and appending NO gate/review event; the unattended
# surfaces (executors, ticks) escalate or sleep instead of busy-looping or fabricating verdicts.
#
# Guard-marker contract (the selftest's teeth): every regate guard line in the implementation
# carries a `regate-guard` marker comment — gate.sh + gate.py (eval refusal), review_policy.py
# (accept_review), hb.js + cli.py/constraints.py (verbs), hb-lint.js + lint.py (shape), tick.sh +
# tick.py (`regate-guard: tick-sleep`), executor.py (`regate-guard: refuse`, `regate-guard:
# refuted-branch`), hb-exec.js (`regate-guard: review-fail-wrap`, `regate-guard: exit3`).
# --selftest strips each marker's line(s) from a COPY and asserts the matching check goes red.
#
#   bash tests/regate-fail-closed.sh [case]   cases: declare perimeter unattended lint park
#   bash tests/regate-fail-closed.sh --selftest
# Prints <CASE>-OK per case, REGATE-FAIL-CLOSED-OK when all pass, REGATE-FAIL-CLOSED-SELFTEST-OK for teeth.
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
# timeout(1) cannot exec a shell function — executor runs go through this real wrapper instead
printf '#!/usr/bin/env bash\nPYTHONPATH="${HB_PY_SRC:-%s/py/src}" exec python3 -m heartbeat.cli "$@"\n' "$ROOT" > "$W/hbpy"; chmod +x "$W/hbpy"

# ── fixture builders ──────────────────────────────────────────────────────────
mkproj(){   # $1 = dir (created); writes the MAIN dag: A (side-effect gate), B (constrained review), C (no gate)
  mkdir -p "$1"; ( cd "$1" && git init -q >/dev/null 2>&1; bash "$ROOT/plugin/bootstrap.sh" . >/dev/null 2>&1 )
  cat > "$1/.hb/dag.json" <<'EOF'
{"project":"regate-fixture",
 "phases":[
  {"id":"A","title":"side-effect gate","gate_entry":null,"gate_exit":"GATE_A",
   "tasks":[{"id":"a1","title":"produce the observed behavior","requires":[],"description":"the gate observes executed.flag"}]},
  {"id":"B","title":"constrained review","gate_entry":"GATE_A","gate_exit":"GATE_B",
   "tasks":[{"id":"b1","title":"reviewed work","requires":[],"description":"work behind an adversarial review"}]},
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
mkrace(){   # $1 = dir; single phase R, UNCONSTRAINED review gate (the executor race fixture)
  mkdir -p "$1"; ( cd "$1" && git init -q >/dev/null 2>&1; bash "$ROOT/plugin/bootstrap.sh" . >/dev/null 2>&1 )
  cat > "$1/.hb/dag.json" <<'EOF'
{"project":"regate-race",
 "phases":[{"id":"R","title":"raced","gate_entry":null,"gate_exit":"GATE_R",
   "tasks":[{"id":"r1","title":"raced work","requires":[],"description":"work whose review is raced by a declare"}]}],
 "gates":{"GATE_R":{"desc":"unconstrained reviewed gate","review":{"prompt":"Refute that R is done."},
   "criteria":[{"id":"gr1","desc":"behavioral","cmd":"python3 -c \"assert 1+1==2\""}]}}}
EOF
}
declare_node(){ ( cd "$1" && HB_ACTOR="${3:-alice}" node .hb/hb.js regate "$2" premises died: volumes replaced ); }
evcount(){ grep -Ec "\"event\": ?\"$2\"" "$1/.hb/events.jsonl" 2>/dev/null || true; }
revcount(){ grep -Ec '"event": ?"(review_passed|review_failed|free_review_recorded)"' "$1/.hb/events.jsonl" 2>/dev/null || true; }
marker(){   # $1=proj $2=gate $3=python expr over m (the regate record); exit 0 if truthy
  python3 -c "
import json,sys
d=json.load(open('$1/.hb/dag.json')); m=(d['gates'].get('$2') or {}).get('regate')
sys.exit(0 if m is not None and ($3) else 1)"
}
tick_reason(){ python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('wakeAgent'), (d.get('data') or {}).get('reason'))"; }

# ── case: declare ─────────────────────────────────────────────────────────────
case_declare(){
  local P="$W/decl"; mkproj "$P"
  local ORIG_CRIT; ORIG_CRIT=$(python3 -c "import json;print(json.dumps(json.load(open('$P/.hb/dag.json'))['gates']['GATE_A']['criteria']))")
  ( cd "$P" && node .hb/hb.js rebuild >/dev/null )   # project OUR dag before capturing the baseline
  cp "$P/.hb/state.json" "$W/state.before"
  # node declare on a GATE id: marker {at,reason,actor,prev_criteria,pending} + audit-only event
  declare_node "$P" GATE_A || fail "declare: node declare exited nonzero"
  marker "$P" GATE_A "m['pending'] is True and m['reason']=='premises died: volumes replaced' and m['actor']=='alice' and isinstance(m.get('at'),str) and json.dumps(m['prev_criteria'])==json.dumps($ORIG_CRIT)" \
    || fail "declare: node marker wrong or missing (need pending/reason/actor/at/prev_criteria snapshot)"
  [ "$(evcount "$P" gate_regated)" = 1 ] || fail "declare: no gate_regated event appended"
  python3 -c "
import json,sys
a=json.load(open('$W/state.before')); b=json.load(open('$P/.hb/state.json'))
keys=['current_phase','active_tasks','completed_tasks','completed_phases','pending_reviews','build_stuck_count','gate']
sys.exit(0 if all(a[k]==b[k] for k in keys) else 1)" || fail "declare: gate_regated changed the state projection"
  # PHASE id resolves to its gate_exit
  declare_node "$P" B bob || fail "declare: node phase-id declare failed"
  marker "$P" GATE_B "m['pending'] is True and m['actor']=='bob'" || fail "declare: phase id B did not resolve to GATE_B"
  # refusals — each loud, no event, marker untouched
  local n0; n0=$(evcount "$P" gate_regated)
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js regate GATE_A another go ) 2>/dev/null && fail "declare: second declare while pending was ACCEPTED"
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js regate GATE_A ) 2>/dev/null && fail "declare: empty reason accepted (node)"
  ( cd "$P" && env -u HB_ACTOR node .hb/hb.js regate GATE_A some reason ) 2>/dev/null && fail "declare: unset HB_ACTOR accepted (node)"
  ( cd "$P" && HB_ACTOR=unknown node .hb/hb.js regate GATE_A some reason ) 2>/dev/null && fail "declare: HB_ACTOR=unknown accepted (node)"
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js regate NOPE some reason ) 2>/dev/null && fail "declare: unknown id accepted (node)"
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js regate C some reason ) 2>/dev/null && fail "declare: phase with no gate_exit accepted (node)"
  [ "$(evcount "$P" gate_regated)" = "$n0" ] || fail "declare: a refused declare appended an event"
  marker "$P" GATE_A "m['reason']=='premises died: volumes replaced'" || fail "declare: a refused declare mutated the pending snapshot"
  # P2: concurrent declares — check-then-write under ONE lock: exactly one wins, on each runtime
  local C="$W/conc"; mkproj "$C"
  for i in 1 2 3 4 5 6; do ( cd "$C" && HB_ACTOR="racer$i" node .hb/hb.js regate GATE_A race $i >/dev/null 2>&1 ) & done; wait
  [ "$(evcount "$C" gate_regated)" = 1 ] || fail "declare: $(evcount "$C" gate_regated) gate_regated events from 6 concurrent node declares (want exactly 1 — the lock is broken)"
  local C2="$W/conc-py"; mkproj "$C2"
  for i in 1 2 3 4 5 6; do ( cd "$C2" && HB_ACTOR="racer$i" PY regate GATE_A --reason "race $i" --dir "$C2" >/dev/null 2>&1 ) & done; wait
  [ "$(evcount "$C2" gate_regated)" = 1 ] || fail "declare: $(evcount "$C2" gate_regated) gate_regated events from 6 concurrent python declares (want exactly 1 — the lock is broken)"
  # a concurrent PARK of another phase must not erase a fresh marker: EVERY dag read-modify-write
  # holds the write lock (an unlocked park lost the update in 2/40 races — refuter catch)
  local K="$W/park-race" i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    rm -rf "$K"; mkproj "$K"
    ( cd "$K" && HB_ACTOR=alice node .hb/hb.js regate GATE_A race reason >/dev/null 2>&1 ) &
    ( cd "$K" && node .hb/hb.js park B parked meanwhile >/dev/null 2>&1 ) &
    wait
    if [ "$(evcount "$K" gate_regated)" = 1 ]; then
      marker "$K" GATE_A "m['pending'] is True" || fail "declare: a concurrent node park ERASED the declared regate marker (trial $i)"
    fi
  done
  for i in 1 2 3 4 5 6; do
    rm -rf "$K"; mkproj "$K"
    ( cd "$K" && HB_ACTOR=alice PY regate GATE_A --reason "race reason" --dir "$K" >/dev/null 2>&1 ) &
    ( cd "$K" && PY park B --reason "parked meanwhile" --dir "$K" >/dev/null 2>&1 ) &
    wait
    if [ "$(evcount "$K" gate_regated)" = 1 ]; then
      marker "$K" GATE_A "m['pending'] is True" || fail "declare: a concurrent python park ERASED the declared regate marker (trial $i)"
    fi
  done
  # python declare: same semantics on a fresh fixture
  local Q="$W/decl-py"; mkproj "$Q"
  ( cd "$Q" && HB_ACTOR=alice PY regate GATE_A --reason "premises died: volumes replaced" --dir "$Q" ) || fail "declare: python declare exited nonzero"
  marker "$Q" GATE_A "m['pending'] is True and m['reason']=='premises died: volumes replaced' and m['actor']=='alice' and isinstance(m.get('prev_criteria'),list)" \
    || fail "declare: python marker wrong or missing"
  [ "$(evcount "$Q" gate_regated)" = 1 ] || fail "declare: python appended no gate_regated event"
  ( cd "$Q" && HB_ACTOR=alice PY regate GATE_A --reason "again" --dir "$Q" ) 2>/dev/null && fail "declare: python accepted a second declare"
  ( cd "$Q" && env -u HB_ACTOR PY regate GATE_B --reason x --dir "$Q" ) 2>/dev/null && fail "declare: python accepted unset HB_ACTOR"
  ( cd "$Q" && HB_ACTOR=alice PY regate GATE_B --reason "" --dir "$Q" ) 2>/dev/null && fail "declare: python accepted an empty reason"
  ( cd "$Q" && HB_ACTOR=alice PY regate C --reason x --dir "$Q" ) 2>/dev/null && fail "declare: python accepted a phase with no gate_exit"
  echo "DECLARE-OK"
}

# ── case: perimeter ───────────────────────────────────────────────────────────
case_perimeter(){
  # EVER-PASSED state: pass GATE_A, then declare, then every path must refuse.
  local P="$W/perim"; mkproj "$P"
  ( cd "$P" && bash .hb/gate.sh GATE_A >/dev/null 2>&1 ) || fail "perimeter: fixture GATE_A did not pass pre-declare"
  rm -f "$P/executed.flag"
  declare_node "$P" GATE_A
  local g1 g0 r0; g0=$(evcount "$P" gate_passed); g1=$(evcount "$P" gate_failed)
  local out rc
  out=$( cd "$P" && bash .hb/gate.sh GATE_A 2>&1 ); rc=$?
  [ "$rc" -eq 3 ] || fail "perimeter: gate.sh single-gate refusal exit=$rc (want the DISTINCT code 3)"
  echo "$out" | grep -qi regate || fail "perimeter: gate.sh refusal is not loud about the regate"
  echo "$out" | grep -q "volumes replaced" || fail "perimeter: gate.sh refusal does not name the reason"
  [ ! -f "$P/executed.flag" ] || fail "perimeter: gate.sh EVALUATED a pending-regate gate (flag touched)"
  ( cd "$P" && bash .hb/gate.sh --check GATE_A >/dev/null 2>&1 ); [ $? -eq 3 ] || fail "perimeter: gate.sh --check refusal is not exit 3"
  [ ! -f "$P/executed.flag" ] || fail "perimeter: --check evaluated the criteria"
  [ "$(evcount "$P" gate_passed)" = "$g0" ] && [ "$(evcount "$P" gate_failed)" = "$g1" ] || fail "perimeter: a refusal appended a gate event"
  out=$( cd "$P" && bash .hb/gate.sh --all 2>&1 ); rc=$?
  [ "$rc" -ne 0 ] || fail "perimeter: --all sweep exit 0 over a pending regate (ever-passed state)"
  echo "$out" | grep -qi regate || fail "perimeter: --all does not name the pending regate"
  echo "$out" | grep -q "ALL GATES PASS" && fail "perimeter: --all printed ALL GREEN over a pending regate"
  [ ! -f "$P/executed.flag" ] || fail "perimeter: --all evaluated a pending-regate gate"
  # python: same three forms, same signal class
  ( cd "$P" && PY gate GATE_A --dir "$P" >/dev/null 2>&1 ); [ $? -eq 3 ] || fail "perimeter: python hb gate refusal is not exit 3"
  ( cd "$P" && PY gate GATE_A --check --dir "$P" >/dev/null 2>&1 ); [ $? -eq 3 ] || fail "perimeter: python --check refusal is not exit 3"
  out=$( cd "$P" && PY gate --all --dir "$P" 2>&1 ) && fail "perimeter: python --all exit 0 over a pending regate"
  echo "$out" | grep -qi "regate-pending" || fail "perimeter: python --all did not print the counted-FAILING regate line (a crash is not a refusal): $out"
  [ ! -f "$P/executed.flag" ] || fail "perimeter: python evaluated a pending-regate gate"
  # fail-closed on a MALFORMED marker: []/{}/"yes" must all REFUSE on BOTH runtimes (truthiness
  # rules differ between the runtimes — a permissive read would silently disarm one of them)
  local MF="$W/perim-malformed"; mkproj "$MF"
  for junk in '[]' '{}' '"yes"'; do
    python3 -c "
import json; p='$MF/.hb/dag.json'; d=json.load(open(p)); d['gates']['GATE_A']['regate']=json.loads('$junk'); json.dump(d,open(p,'w'))"
    ( cd "$MF" && bash .hb/gate.sh GATE_A >/dev/null 2>&1 ); [ $? -eq 3 ] || fail "perimeter: gate.sh evaluated under a malformed regate marker ($junk)"
    ( cd "$MF" && PY gate GATE_A --dir "$MF" >/dev/null 2>&1 ); [ $? -eq 3 ] || fail "perimeter: python evaluated under a malformed regate marker ($junk)"
    [ ! -f "$MF/executed.flag" ] || fail "perimeter: a malformed marker let the criteria run ($junk)"
  done
  # diagnose must not execute the criteria of a pending gate (python calls eval_gate directly today)
  ( cd "$P" && node .hb/hb.js diagnose >/dev/null 2>&1 ) || true
  ( cd "$P" && PY diagnose --dir "$P" >/dev/null 2>&1 ) || true
  [ ! -f "$P/executed.flag" ] || fail "perimeter: diagnose EXECUTED a pending-regate gate's criteria"
  # NEVER-PASSED state: a planned gate with a pending regate must still fail the sweep
  local N="$W/perim-never"; mkproj "$N"
  declare_node "$N" GATE_A
  out=$( cd "$N" && bash .hb/gate.sh --all 2>&1 ); rc=$?
  [ "$rc" -ne 0 ] || fail "perimeter: --all exit 0 over a NEVER-PASSED pending regate (planned-skip hole)"
  echo "$out" | grep -qi regate || fail "perimeter: --all silent about a never-passed pending regate"
  ( cd "$N" && PY gate --all --dir "$N" >/dev/null 2>&1 ) && fail "perimeter: python --all exit 0 over a never-passed pending regate"
  # ACCEPTANCE surfaces: review pass/fail/free + constraints --record, review-owed fixture
  local V="$W/perim-rev"; mkproj "$V"
  ( cd "$V" && HB_ACTOR=doer node .hb/hb.js start b1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done b1 >/dev/null )
  printf 'the real work of b1\n' > "$V/m.txt"   # G1's subject EXISTS: the constraints refusal below must be the REGATE one, never a grounding miss
  ( cd "$V" && bash .hb/gate.sh GATE_B >/dev/null 2>&1 )
  grep -Eq '"event": ?"gate_passed"' "$V/.hb/events.jsonl" || fail "perimeter: review fixture GATE_B never det-passed"
  declare_node "$V" GATE_B
  cat > "$V/findings.md" <<'EOF'
I tried to refute GATE_B / phase B (task b1): ran the criteria, inspected m.txt, found nothing broken.
HOLES: none
EOF
  r0=$(revcount "$V")
  for verdict in pass fail free; do
    out=$( cd "$V" && HB_ACTOR=reviewer node .hb/hb.js review GATE_B "$verdict" --artifact findings.md 2>&1 ) && fail "perimeter: node review $verdict ACCEPTED while regate pending"
    echo "$out" | grep -qi regate || fail "perimeter: node review $verdict refusal not loud about the regate"
    out=$( cd "$V" && HB_ACTOR=reviewer PY review GATE_B "$verdict" --artifact findings.md --dir "$V" 2>&1 ) && fail "perimeter: python review $verdict ACCEPTED while regate pending"
    echo "$out" | grep -qi regate || fail "perimeter: python review $verdict refusal not loud about the regate"
  done
  # the python CHOKEPOINT driven directly (the MCP review tool and the executor route through it)
  PYTHONPATH="${HB_PY_SRC:-$ROOT/py/src}" python3 -c "
import os, sys
os.environ['HB_ACTOR'] = 'reviewer'
from heartbeat import review_policy
for v in ('pass', 'fail', 'free'):
    rc, out, err = review_policy.accept_review('$V/.hb', 'GATE_B', v, artifact='findings.md')
    assert rc != 0, 'accept_review %s succeeded while regate pending' % v
    assert 'regate' in (out + err).lower(), 'accept_review %s refusal silent about the regate: %r' % (v, err)
" || fail "perimeter: review_policy.accept_review is not a regate chokepoint"
  [ "$(revcount "$V")" = "$r0" ] || fail "perimeter: a refused review verdict appended a review event"
  # constraints recording refused while pending (both runtimes) — and refused FOR THE REGATE,
  # not for an unrelated grounding miss (m.txt exists and is in the change list)
  printf '[{"id":"G1","claim":"x behaves","subjects":["m.txt"],"violation":"it does not"}]' > "$V/g.json"
  local c0; c0=$(evcount "$V" constraints_recorded)
  out=$( cd "$V" && HB_ACTOR=author node .hb/hb.js constraints GATE_B --record g.json 2>&1 ) && fail "perimeter: node constraints --record accepted while pending"
  echo "$out" | grep -qi regate || fail "perimeter: node constraints refusal is not the regate one: $out"
  out=$( cd "$V" && HB_ACTOR=author PY constraints GATE_B --record g.json --dir "$V" 2>&1 ) && fail "perimeter: python constraints --record accepted while pending"
  echo "$out" | grep -qi regate || fail "perimeter: python constraints refusal is not the regate one: $out"
  [ "$(evcount "$V" constraints_recorded)" = "$c0" ] || fail "perimeter: a refused constraints record appended an event"
  # a PHASE id must not bypass the review guard (refuter catch): review B == review GATE_B
  out=$( cd "$V" && HB_ACTOR=reviewer node .hb/hb.js review B fail "trying via the phase id" 2>&1 ) && fail "perimeter: node review via PHASE id accepted while regate pending"
  echo "$out" | grep -qi regate || fail "perimeter: node phase-id review refusal is not the regate one: $out"
  out=$( cd "$V" && HB_ACTOR=reviewer PY review B fail "trying via the phase id" --dir "$V" 2>&1 ) && fail "perimeter: python review via PHASE id accepted while regate pending"
  echo "$out" | grep -qi regate || fail "perimeter: python phase-id review refusal is not the regate one: $out"
  [ "$(revcount "$V")" = "$r0" ] || fail "perimeter: a phase-id review refusal appended a review event"
  # the acceptance-anchor writer refuses too (write-once records must not freeze a revised tree)
  ( cd "$V" && node .hb/hb.js anchor GATE_B ) >/dev/null 2>&1 && fail "perimeter: hb anchor wrote an acceptance anchor for a pending-regate gate"
  [ ! -f "$V/.hb/anchors/GATE_B.json" ] || fail "perimeter: an anchor file exists for a pending-regate gate"
  echo "PERIMETER-OK"
}

# ── case: unattended ──────────────────────────────────────────────────────────
mkbackend(){   # $1 = file  $2 = refuted true|false  $3 = project (declares regate mid-refute)  $4 = marker file
  cat > "$1" <<EOF
#!/usr/bin/env bash
mode="\${!#}"; cat >/dev/null
touch "$4.\$mode"
if [ "\$mode" = refute ]; then
  HB_ACTOR=racer node "$3/.hb/hb.js" regate GATE_R mid-review premise death >/dev/null 2>&1
  echo '{"refuted":$2,"findings":"raced findings about GATE_R and r1: I ran the criteria and inspected the phase — nothing broken found."}'
else
  echo '{"ok":true,"summary":"noop"}'
fi
EOF
  chmod +x "$1"
}
case_unattended(){
  # (a) TICK SLEEP — regate declared BEFORE the tick: both ticks sleep regate_pending_waiting,
  #     executors exit bounded/idle WITHOUT dispatching the backend.
  local p s
  for state in gatepending reviewowed; do
    p="$W/un-$state"; mkproj "$p"
    ( cd "$p" && HB_ACTOR=doer node .hb/hb.js start a1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done a1 >/dev/null )
    ( cd "$p" && HB_ACTOR=doer node .hb/hb.js start c1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done c1 >/dev/null )
    if [ "$state" = reviewowed ]; then
      ( cd "$p" && bash .hb/gate.sh GATE_A >/dev/null 2>&1 ); rm -f "$p/executed.flag"
      ( cd "$p" && HB_ACTOR=doer node .hb/hb.js start b1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done b1 >/dev/null )
      ( cd "$p" && bash .hb/gate.sh GATE_B >/dev/null 2>&1 )
      declare_node "$p" GATE_B
    else
      declare_node "$p" GATE_A
    fi
    s=$( cd "$p" && bash .hb/tick.sh 2>/dev/null | tick_reason )
    [ "$s" = "False regate_pending_waiting" ] || fail "unattended($state): tick.sh said '$s' (want sleep regate_pending_waiting)"
    s=$( cd "$p" && PY tick --dir "$p" 2>/dev/null | tick_reason )
    [ "$s" = "False regate_pending_waiting" ] || fail "unattended($state): python tick said '$s' (want the IDENTICAL sleep reason)"
    printf '#!/usr/bin/env bash\ntouch "%s/dispatched"; cat >/dev/null; echo "{\\"ok\\":true}"\n' "$p" > "$p/be.sh"; chmod +x "$p/be.sh"
    ( cd "$p" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $p/be.sh" timeout 60 node .hb/hb-exec.js run >/dev/null 2>&1 )
    [ $? -ne 124 ] || fail "unattended($state): node executor did not exit bounded on a sleeping tick"
    [ ! -f "$p/dispatched" ] || fail "unattended($state): node executor dispatched the backend over a pending regate"
    ( cd "$p" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $p/be.sh" timeout 60 "$W/hbpy" exec run --dir "$p" >/dev/null 2>&1 )
    [ $? -ne 124 ] || fail "unattended($state): python executor did not exit bounded"
    [ ! -f "$p/dispatched" ] || fail "unattended($state): python executor dispatched the backend over a pending regate"
    [ "$(revcount "$p")" = 0 ] || fail "unattended($state): an idle executor run appended a review event"
  done
  # (b) MID-REVIEW RACE — the backend ITSELF declares the regate before returning its verdict.
  local exr out
  for exr in node py; do
    for verdict in true false; do
      p="$W/race-$exr-$verdict"; mkrace "$p"
      ( cd "$p" && HB_ACTOR=doer node .hb/hb.js start r1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done r1 >/dev/null )
      mkbackend "$p/be.sh" "$verdict" "$p" "$p/called"
      if [ "$exr" = node ]; then
        out=$( cd "$p" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $p/be.sh" timeout 90 node .hb/hb-exec.js run 2>&1 ); rc=$?
      else
        out=$( cd "$p" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $p/be.sh" timeout 90 "$W/hbpy" exec run --dir "$p" 2>&1 ); rc=$?
      fi
      [ "$rc" -ne 124 ] || fail "race($exr,$verdict): executor busy-looped (timeout)"
      [ -f "$p/called.refute" ] || fail "race($exr,$verdict): the refute backend was never dispatched — the race never ran"
      marker "$p" GATE_R "m['pending'] is True" || fail "race($exr,$verdict): the mid-review declare did not land"
      [ "$(revcount "$p")" = 0 ] || fail "race($exr,$verdict): a review event landed while the regate was pending (fabricated verdict)"
      echo "$out" | grep -i "hb-exec stop" | grep -qi regate || fail "race($exr,$verdict): the executor did not escalate loudly about the regate (no HB-EXEC STOP line names it)"
    done
  done
  # (c) GATE-PATH SIGNAL — a one-shot tick shim wakes gate_pending over the pending regate, so
  #     gate.sh's exit 3 actually REACHES the node executor's escalation branch (python: pytest).
  p="$W/shim"; mkrace "$p"
  ( cd "$p" && HB_ACTOR=doer node .hb/hb.js start r1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done r1 >/dev/null )
  local WAKE; WAKE=$( cd "$p" && bash .hb/tick.sh 2>/dev/null )
  echo "$WAKE" | grep -q '"gate_pending"' || fail "shim: fixture pre-declare tick is not gate_pending: $WAKE"
  declare_node "$p" GATE_R
  mv "$p/.hb/tick.sh" "$p/.hb/tick.real.sh"
  { printf '#!/usr/bin/env bash\nif [ ! -f "%s/.hb/.shimmed" ]; then touch "%s/.hb/.shimmed"; cat <<'"'"'JSON'"'"'\n' "$p" "$p"
    printf '%s\n' "$WAKE"
    printf 'JSON\nelse\n  exec bash "%s/.hb/tick.real.sh" "$@"\nfi\n' "$p"; } > "$p/.hb/tick.sh"
  chmod +x "$p/.hb/tick.sh"
  printf '#!/usr/bin/env bash\ncat >/dev/null; echo "{\\"ok\\":true}"\n' > "$p/be.sh"; chmod +x "$p/be.sh"
  out=$( cd "$p" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $p/be.sh" timeout 90 node .hb/hb-exec.js run 2>&1 ); rc=$?
  [ "$rc" -ne 124 ] || fail "shim: node executor busy-looped on the gate-path refusal"
  # the EXECUTOR's own escalation, not gate.sh's inherited refusal text (a refuter catch: the
  # loose grep stayed green with the exit-3 branch deleted)
  echo "$out" | grep -i "hb-exec stop" | grep -qi regate || fail "shim: node executor swallowed gate.sh's exit-3 refusal (no HB-EXEC STOP line names the regate)"
  grep -Eq '"event": ?"gate_(passed|failed)"' "$p/.hb/events.jsonl" && fail "shim: the refused gate run appended a gate event"
  echo "UNATTENDED-OK"
}

# ── case: lint ────────────────────────────────────────────────────────────────
case_lint(){
  local P="$W/lint"; mkproj "$P"
  python3 - "$P/.hb/dag.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
d["gates"]["GATE_A"]["regate"] = {"pending": "yes"}   # malformed: wrong type, no reason/actor/prev_criteria
json.dump(d, open(sys.argv[1], "w"))
EOF
  local out
  out=$(node "$P/.hb/hb-lint.js" "$P/.hb/dag.json" 2>&1) && fail "lint: node accepted a malformed regate record"
  echo "$out" | grep -qi regate || fail "lint: node error does not name the regate record"
  out=$( PY lint "$P/.hb/dag.json" --dir "$P" 2>&1 ) && fail "lint: python accepted a malformed regate record"
  echo "$out" | grep -qi regate || fail "lint: python error does not name the regate record"
  # well-formed lints clean on both
  local Q="$W/lint-ok"; mkproj "$Q"
  declare_node "$Q" GATE_A
  node "$Q/.hb/hb-lint.js" "$Q/.hb/dag.json" >/dev/null 2>&1 || fail "lint: node rejected a WELL-FORMED regate record"
  PY lint "$Q/.hb/dag.json" --dir "$Q" >/dev/null 2>&1 || fail "lint: python rejected a well-formed regate record"
  echo "LINT-OK"
}

# ── case: park ────────────────────────────────────────────────────────────────
case_park(){
  local P="$W/park"; mkproj "$P"
  ( cd "$P" && bash .hb/gate.sh GATE_A >/dev/null 2>&1 ); rm -f "$P/executed.flag"
  declare_node "$P" GATE_A
  ( cd "$P" && node .hb/hb.js park A retired for now >/dev/null )
  ( cd "$P" && bash .hb/gate.sh GATE_A >/dev/null 2>&1 ); [ $? -eq 3 ] || fail "park: eval of a parked+pending gate is not refused (exit 3)"
  # Parked retires a gate from EVALUATION — it does not silence its pending revision: the
  # regate stays in the FAILING count on both runtimes (the T184 flip of this check's old
  # exit-0 pin; a sweep must never say ALL GREEN over an unrefuted revision, parked or not).
  local out rc
  out=$( cd "$P" && bash .hb/gate.sh --all 2>&1 ); rc=$?
  [ "$rc" -eq 1 ] || fail "park: a PARKED pending regate must stay in the FAILING count (exit $rc, want 1)"
  [ -f "$P/executed.flag" ] && fail "park: the parked gate was EVALUATED by the sweep (retirement from evaluation broken)"
  echo "$out" | grep -i parked | grep -qi regate || fail "park: the parked listing does not ANNOTATE the pending regate"
  echo "$out" | grep -i 'counted FAILING' | grep -q 'GATE_A' || fail "park: the failing-count annotation does not name the parked gate"
  ( cd "$P" && PY gate --all --dir "$P" >/dev/null 2>&1 ); [ $? -eq 1 ] || fail "park: python sweep exit 0 over a parked pending regate"
  ( cd "$P" && PY gate --all --dir "$P" 2>&1 | grep -i 'counted FAILING' | grep -q 'GATE_A' ) || fail "park: python failing-count annotation does not name the parked gate"
  echo "PARK-OK"
}

# ── selftest: mutation teeth ──────────────────────────────────────────────────
mutate(){   # $1 = file  $2 = marker pattern — delete the guard lines, assert bytes changed
  local before; before=$(grep -c "$2" "$1" 2>/dev/null || true)
  [ "${before:-0}" -gt 0 ] || fail "selftest: no '$2' guard marker in $1 — the implementation must carry it"
  sed -i "/$2/d" "$1"
}
mkpycopy(){ cp -r "$ROOT/py/src" "$1"; }   # mutated python runtime, selected via HB_PY_SRC
selftest(){
  local P out
  # m1: gate.sh guard stripped → the guard RE-OPENS (the gate evaluates), for the right reason:
  # the stripped script still parses and the criteria actually run (a crash is red for the wrong reason)
  P="$W/st1"; mkproj "$P"; declare_node "$P" GATE_A
  mutate "$P/.hb/gate.sh" "regate-guard"
  bash -n "$P/.hb/gate.sh" || fail "selftest m1: stripped gate.sh no longer parses — guard lines are not self-contained"
  ( cd "$P" && bash .hb/gate.sh GATE_A >/dev/null 2>&1 ); rc=$?
  [ "$rc" -eq 3 ] && fail "selftest m1: gate.sh refusal survived its guard being stripped (no teeth)"
  [ -f "$P/executed.flag" ] || fail "selftest m1: the stripped guard did not re-open evaluation (red for the wrong reason, rc=$rc)"
  # m2: gate.py guard stripped → python guard re-opens, same right-reason requirement
  P="$W/st2"; mkproj "$P"; declare_node "$P" GATE_A
  mkpycopy "$W/py-m2"; mutate "$W/py-m2/heartbeat/gate.py" "regate-guard"
  ( cd "$P" && HB_PY_SRC="$W/py-m2" PY gate GATE_A --dir "$P" >/dev/null 2>&1 ); rc=$?
  [ "$rc" -eq 3 ] && fail "selftest m2: python gate refusal survived the eval_gate guard strip"
  [ -f "$P/executed.flag" ] || fail "selftest m2: the stripped python guard did not re-open evaluation (red for the wrong reason, rc=$rc)"
  # m3: accept_review guard stripped → a fail verdict lands while pending (red)
  P="$W/st3"; mkproj "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start b1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done b1 >/dev/null && bash .hb/gate.sh GATE_B >/dev/null 2>&1 )
  declare_node "$P" GATE_B
  mkpycopy "$W/py-m3"; mutate "$W/py-m3/heartbeat/review_policy.py" "regate-guard"
  HB_PY_SRC="$W/py-m3" PYTHONPATH="$W/py-m3" python3 -c "
import os; os.environ['HB_ACTOR']='reviewer'
from heartbeat import review_policy
rc,_o,_e = review_policy.accept_review('$P/.hb','GATE_B','fail',note='x')
raise SystemExit(0 if rc==0 else 1)" || fail "selftest m3: accept_review still refused after its guard was stripped (sed missed?)"
  [ "$(revcount "$P")" = 1 ] || fail "selftest m3: stripped guard did not let the event land (mutation not load-bearing)"
  # m4: executor.py refuted-branch guard stripped → the py race (refuted:true) lets review_failed land (red)
  P="$W/st4"; mkrace "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start r1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done r1 >/dev/null )
  mkbackend "$P/be.sh" true "$P" "$P/called"
  mkpycopy "$W/py-m4"; mutate "$W/py-m4/heartbeat/executor.py" "regate-guard: refuted-branch"
  ( cd "$P" && HB_PY_SRC="$W/py-m4" HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $P/be.sh" timeout 90 "$W/hbpy" exec run --dir "$P" >/dev/null 2>&1 )
  [ "$(revcount "$P")" != 0 ] || fail "selftest m4: stripping the refuted-branch guard did not let a review event land (mutation not load-bearing)"
  # m5: executor.py refuse guard stripped → the refuse-guard pytest case goes red. The mutated tree
  # carries its own tests/ because conftest.py inserts <tree>/src ahead of PYTHONPATH.
  mkdir -p "$W/m5root"; cp -r "$ROOT/py/src" "$W/m5root/src"; cp -r "$ROOT/py/tests" "$W/m5root/tests"
  mutate "$W/m5root/src/heartbeat/executor.py" "regate-guard: refuse"
  ( cd "$W/m5root" && "$ROOT/py/.venv/bin/python" -m pytest -q tests -k "regate and refuse_guard" >/dev/null 2>&1 ) \
    && fail "selftest m5: the refuse-guard pytest case stayed green after the guard was stripped"
  # m6: hb-exec.js review-fail wrap stripped → the node race (refuted:true — the verdict that hits
  # the review-fail call) loses its guarded escalation: it busy-loops (timeout) or crashes (red)
  P="$W/st6"; mkrace "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start r1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done r1 >/dev/null )
  mkbackend "$P/be.sh" true "$P" "$P/called"
  mutate "$P/.hb/hb-exec.js" "regate-guard: review-fail-wrap"
  out=$( cd "$P" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $P/be.sh" timeout 90 node .hb/hb-exec.js run 2>&1 ); rc=$?
  # teeth = the race check's own assertion (an HB-EXEC STOP line naming the regate) must now FAIL:
  # the stripped wrap silently drops the verdict (idle/timeout/crash), never that escalation.
  if echo "$out" | grep -i "hb-exec stop" | grep -qi regate; then
    fail "selftest m6: node race check survived the review-fail wrap being stripped (no teeth)"
  fi
  # m7: lint guards stripped → malformed record lints clean (red), both runtimes
  P="$W/st7"; mkproj "$P"
  python3 -c "
import json; p='$P/.hb/dag.json'; d=json.load(open(p)); d['gates']['GATE_A']['regate']={'pending':'yes'}; json.dump(d,open(p,'w'))"
  mutate "$P/.hb/hb-lint.js" "regate-guard"
  node "$P/.hb/hb-lint.js" "$P/.hb/dag.json" >/dev/null 2>&1 || fail "selftest m7: node lint still errors after its guard was stripped"
  mkpycopy "$W/py-m7"; mutate "$W/py-m7/heartbeat/lint.py" "regate-guard"
  HB_PY_SRC="$W/py-m7" PY lint "$P/.hb/dag.json" --dir "$P" >/dev/null 2>&1 || fail "selftest m7: python lint still errors after its guard was stripped"
  # m8: tick guards stripped → the tick wakes gate_pending over a pending regate (red), both runtimes
  P="$W/st8"; mkproj "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start a1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done a1 >/dev/null )
  declare_node "$P" GATE_A
  mutate "$P/.hb/tick.sh" "regate-guard"
  bash -n "$P/.hb/tick.sh" || fail "selftest m8: stripped tick.sh no longer parses — guard lines are not self-contained"
  out=$( cd "$P" && bash .hb/tick.sh 2>/dev/null | tick_reason )
  [ "$out" = "False regate_pending_waiting" ] && fail "selftest m8: tick.sh still sleeps after its guard was stripped"
  mkpycopy "$W/py-m8"; mutate "$W/py-m8/heartbeat/tick.py" "regate-guard"
  out=$( cd "$P" && HB_PY_SRC="$W/py-m8" PY tick --dir "$P" 2>/dev/null | tick_reason )
  [ "$out" = "False regate_pending_waiting" ] && fail "selftest m8: python tick still sleeps after its guard was stripped"
  # m9: node hb-exec's exit3 escalation stripped → the shim check (an HB-EXEC STOP line naming the
  # regate) must go red — the loose inherited-text grep survived this exact mutation (refuter catch)
  P="$W/st9"; mkrace "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start r1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done r1 >/dev/null )
  WAKE9=$( cd "$P" && bash .hb/tick.sh 2>/dev/null )
  declare_node "$P" GATE_R
  mv "$P/.hb/tick.sh" "$P/.hb/tick.real.sh"
  { printf '#!/usr/bin/env bash\nif [ ! -f "%s/.hb/.shimmed" ]; then touch "%s/.hb/.shimmed"; cat <<'"'"'JSON'"'"'\n' "$P" "$P"
    printf '%s\n' "$WAKE9"
    printf 'JSON\nelse\n  exec bash "%s/.hb/tick.real.sh" "$@"\nfi\n' "$P"; } > "$P/.hb/tick.sh"
  chmod +x "$P/.hb/tick.sh"
  printf '#!/usr/bin/env bash\ncat >/dev/null; echo "{\\"ok\\":true}"\n' > "$P/be.sh"; chmod +x "$P/be.sh"
  mutate "$P/.hb/hb-exec.js" "regate-guard: exit3"
  out=$( cd "$P" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $P/be.sh" timeout 90 node .hb/hb-exec.js run 2>&1 )
  if echo "$out" | grep -i "hb-exec stop" | grep -qi regate; then
    fail "selftest m9: the shim check survived the exit3 escalation being stripped (no teeth)"
  fi
  # m10: the python executor's gate-path guard stripped → the gate-path pytest case goes red
  mkdir -p "$W/m10root"; cp -r "$ROOT/py/src" "$W/m10root/src"; cp -r "$ROOT/py/tests" "$W/m10root/tests"
  mutate "$W/m10root/src/heartbeat/executor.py" "regate-guard: gate-path"
  ( cd "$W/m10root" && "$ROOT/py/.venv/bin/python" -m pytest -q tests -k "regate and gate_path" >/dev/null 2>&1 ) \
    && fail "selftest m10: the gate-path pytest case stayed green after the executor guard was stripped"
  # m11: node's constraints --record guard stripped → the record LANDS on a pending-regate gate
  # (with a REAL grounded subject, so no unrelated refusal can mask the bypass — refuter catch)
  P="$W/st11"; mkproj "$P"
  ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start b1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done b1 >/dev/null )
  printf 'the real work of b1\n' > "$P/m.txt"
  ( cd "$P" && bash .hb/gate.sh GATE_B >/dev/null 2>&1 )
  declare_node "$P" GATE_B
  printf '[{"id":"G1","claim":"x behaves","subjects":["m.txt"],"violation":"it does not"}]' > "$P/g.json"
  mutate "$P/.hb/hb.js" "regate-guard: constraints"
  mutate "$P/.hb/hb.js" "regate-guard: log-truth"   # the constraints verb is DOUBLE-guarded (marker + log) — strip both to prove the family's teeth
  ( cd "$P" && HB_ACTOR=author node .hb/hb.js constraints GATE_B --record g.json >/dev/null 2>&1 )
  [ "$(evcount "$P" constraints_recorded)" != 0 ] || fail "selftest m11: stripping the node constraints guards did not let a record land (mutation not load-bearing — check the fixture grounds m.txt)"
  echo "REGATE-FAIL-CLOSED-SELFTEST-OK"
}

# ── dispatch ──────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--selftest" ]; then selftest; exit 0; fi
sel="${1:-all}"
for c in declare perimeter unattended lint park; do
  if [ "$sel" = all ] || [ "$sel" = "$c" ]; then "case_$c" || exit 1; fi
done
[ "$sel" = all ] && echo "REGATE-FAIL-CLOSED-OK"
exit 0
