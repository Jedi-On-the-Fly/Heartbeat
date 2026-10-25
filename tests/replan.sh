#!/usr/bin/env bash
# replan.sh — the replan contract: plan to the horizon, append freely, and NEVER hand-edit a
# completed gate's criteria without sanction (T184, the DS1 spec — written BEFORE the tripwire).
#
# The boundary: dag.json is the editable plan BELOW the knowledge horizon (append phases, edit
# and drop never-started work — free, and characterized GREEN here today), but a COMPLETED
# gate's criteria are evidence the log has already pinned. gate.sh records every real pass with
# criteria:[{id,cmd,exit}] — the PIN. The tripwire (ds1b) walks each gate's criteria-pinned
# passes in log order plus the current dag criteria as the final element; identity is the
# ORDERED (id, cmd) pairs byte-exact; any ADJACENT difference is UNSANCTIONED DRIFT unless
#   (i)  a gate_regated FOR THAT GATE lies between the two points (contemporaneous sanction), or
#   (ii) a COMPLETED regate cycle — gate_regated → gate_rearmed → fresh criteria-pinned pass,
#        in order, the WHOLE cycle (its gate_regated included) after the pair's later point
#        (ABSOLUTION: late rigor is still rigor; the last cycle absolves all earlier drift).
# Severity: doctor PROBLEM (exit 1), message bytes twin-identical across runtimes, naming the
# gate and the real cure (a full regate cycle). Reach: gate.sh --all / the py sweep EXCLUDE a
# drifted gate from re-evaluation (running weakened criteria proves nothing) and count it
# FAILING, annotated — parked silences neither drift NOR a pending regate (the parked --all
# exit-0 this wave flips); a REMOVED ever-pinned gate appears via the log walk; bare/import
# passes (no criteria field) never pin and never seed. Tick: the NEW human-needed reason
# criteria_drift (never unsanctioned_drift — its freeze-if-intended action would be a one-actor
# self-sanction), firing EVERY tick until cured, reason keys identical across runtimes.
# Honest limits (pinned here as spec): desc and timeout_s are NOT pinned and never compared;
# the trust model is procedural (HB_ACTOR is declared identity, not authentication).
#
# SPEC-FIRST: the drift / cure / sweep / tick cases and the selftest are RED TODAY by design —
# doctor is silent over every one of these edits on both runtimes until ds1b lands. The six
# existing suite checks that assert today's silence (T160.3/.4, T161.2, the two
# py/tests/test_gate.py sweep tests at l.203 and l.232, and T179.4/regate-fail-closed
# case_park) are re-specified to the new contract in ds1b's change — updated, never weakened.
#
#   bash tests/replan.sh [case]   cases: append unstarted quiet verbs drift cure sweep tick
#   bash tests/replan.sh --selftest
# Prints <CASE>-OK per case, REPLAN-OK when all pass, REPLAN-SELFTEST-OK for teeth.
set -u
# Env hygiene: under a gate criterion, gate.sh exports HB_DIR/PROJECT_DIR/GATE — and the fixture
# projects' copied CLIs honor env HB_DIR. A proof must never inherit a caller's project pointers
# (the same rule as run-tests.sh/parity.sh; its violation polluted a live plan's event log once).
unset HB_DIR PROJECT_DIR GATE G DAG_FILE EVENTS_FILE 2>/dev/null || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export HB_NO_GIT=1 STUCK_TICKS=999
fail(){ echo "FAIL: $1"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
PY(){ PYTHONPATH="${HB_PY_SRC:-$ROOT/py/src}" python3 -m heartbeat.cli "$@"; }

# ── fixture: H1 (completable, 2 pinned criteria — reorder needs two) + X (sweep content) ──
mkh(){   # $1 = dir
  mkdir -p "$1"; ( cd "$1" && git init -q >/dev/null 2>&1; bash "$ROOT/plugin/bootstrap.sh" . >/dev/null 2>&1 )
  cat > "$1/.hb/dag.json" <<'EOF'
{"project":"replan-fixture",
 "phases":[
  {"id":"H1","title":"horizon 1","gate_entry":null,"gate_exit":"GATE_H1",
   "tasks":[{"id":"h1a","title":"h1 work","requires":[],"description":"produces ok"}]},
  {"id":"X","title":"independent","gate_entry":null,"gate_exit":"GATE_X",
   "tasks":[{"id":"x1","title":"x work","requires":[],"description":"independent"}]}],
 "gates":{
  "GATE_H1":{"desc":"h1 gate","criteria":[
    {"id":"c1","desc":"ok exists behaviorally","cmd":"[ -f \"$PROJECT_DIR/ok\" ] && python3 -c \"assert 1\""},
    {"id":"c2","desc":"behavioral","cmd":"python3 -c \"assert 2+2==4\""}]},
  "GATE_X":{"desc":"x gate","criteria":[{"id":"gx1","desc":"behavioral","cmd":"python3 -c \"assert 3+3==6\""}]}}}
EOF
}
complete_h1(){   # H1 done THROUGH THE CLI + a real criteria-pinned pass (the pin)
  ( cd "$1" && HB_ACTOR=doer node .hb/hb.js start h1a >/dev/null && HB_ACTOR=doer node .hb/hb.js done h1a >/dev/null )
  : > "$1/ok"
  ( cd "$1" && bash .hb/gate.sh GATE_H1 >/dev/null 2>&1 ) || fail "fixture: GATE_H1 pass failed"
}
pass_x(){ ( cd "$1" && bash .hb/gate.sh GATE_X >/dev/null 2>&1 ) || fail "fixture: GATE_X pass failed"; }
addphase(){   # $1=dir $2=id $3=entry $4=exit $5=taskid [$6=sabotage: dupid|mutate]
  python3 - "$1/.hb/dag.json" "$2" "$3" "$4" "$5" "${6:-none}" <<'EOF'
import json, sys
p, pid, entry, exit_, tid, sab = sys.argv[1:7]
d = json.load(open(p))
ph = {"id": "H1" if sab == "dupid" else pid, "title": f"appended {pid}",
      "gate_entry": None if entry == "null" else entry, "gate_exit": exit_,
      "tasks": [{"id": tid, "title": f"{tid} work", "requires": [], "description": f"produces {tid}.txt"}]}
d["phases"].append(ph)
d["gates"][exit_] = {"desc": f"{pid} gate", "criteria": [
    {"id": f"g_{tid}", "desc": "behavioral", "cmd": "python3 -c \"assert 5+5==10\""}]}
if sab == "mutate":
    next(x for x in d["phases"] if x["id"] == "H1")["title"] = "MUTATED BY THE GENERATOR"
json.dump(d, open(p, "w"), indent=2)
EOF
}
editcmd(){   # $1=dir $2=criterion-index $3=new cmd — the UNSANCTIONED hand-edit
  python3 - "$1/.hb/dag.json" "$2" "$3" <<'EOF'
import json, sys
p, i, c = sys.argv[1], int(sys.argv[2]), sys.argv[3]
d = json.load(open(p)); d["gates"]["GATE_H1"]["criteria"][i]["cmd"] = c
json.dump(d, open(p, "w"), indent=2)
EOF
}
bytedrift(){ editcmd "$1" 1 'python3 -c "assert 2+2==4 "'; }   # ONE byte (trailing space): semantically identical, still passes — byte-exact identity must still trip
weaken(){   editcmd "$1" 0 'python3 -c "assert True"'; }       # drops the ok-file requirement — a real weakening that still passes
# H1's record (parsed dag entry — appenders reserialize, so equality is structural) + its
# projection slice: what "the append touched nothing above the horizon" actually means.
h1slice(){ python3 - "$1/.hb/dag.json" "$1/.hb/state.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); s = json.load(open(sys.argv[2]))
h1 = next((x for x in d.get("phases", []) if x.get("id") == "H1"), None)
print(json.dumps([h1, s.get("completed_phases"), s.get("completed_tasks")], sort_keys=True))
EOF
}
norm(){ python3 -c "
import json, sys
s = json.load(open(sys.argv[1])); s.pop('last_updated', None)
print(json.dumps(s, sort_keys=True))" "$1/.hb/state.json"; }   # idempotence is MODULO last_updated by design (hb.js:107/185, state.py:83/169)
declare_rg(){ ( cd "$1" && HB_ACTOR=carol node .hb/hb.js regate "$2" premise died >/dev/null 2>&1 ) || fail "fixture: regate declare refused"; }
rearm_rg(){
  printf 'Rearm evidence for %s (task h1a): the premise died; the revised criteria were run by hand and hold.\n' "$2" > "$1/e.md"
  ( cd "$1" && HB_ACTOR=dave node .hb/hb.js regate "$2" --rearm --artifact e.md >/dev/null 2>&1 ) || fail "fixture: rearm refused"
}
# BOTH-runtime doctor asserts. Drift is a PROBLEM (exit 1) naming the gate AND the regate-cycle
# cure; quiet is exit 0 with no ✗ line naming the gate (never asserted as zero NOTES).
assert_drift(){   # $1=dir $2=gate $3=label
  local on rn op rp
  on=$( cd "$1" && node .hb/hb.js doctor 2>&1 ); rn=$?
  [ "$rn" = 1 ] || fail "$3: node doctor exit $rn (want 1 — unsanctioned drift must be a PROBLEM): $on"
  echo "$on" | grep '✗' | grep "$2" | grep -qi 'regate cycle' || fail "$3: node problem does not name $2 + the regate-cycle cure: $on"
  op=$( PY doctor --dir "$1" 2>&1 ); rp=$?
  [ "$rp" = 1 ] || fail "$3: python doctor exit $rp (want 1): $op"
  echo "$op" | grep '✗' | grep "$2" | grep -qi 'regate cycle' || fail "$3: python problem does not name $2 + the cure: $op"
}
assert_quiet(){   # $1=dir $2=gate $3=label
  local on rn op rp
  on=$( cd "$1" && node .hb/hb.js doctor 2>&1 ); rn=$?
  [ "$rn" = 0 ] || fail "$3: node doctor exit $rn (want 0): $on"
  echo "$on" | grep '✗' | grep -q "$2" && fail "$3: node reports a problem on $2 where none is owed: $on"
  op=$( PY doctor --dir "$1" 2>&1 ); rp=$?
  [ "$rp" = 0 ] || fail "$3: python doctor exit $rp (want 0): $op"
  echo "$op" | grep '✗' | grep -q "$2" && fail "$3: python reports a problem on $2: $op"
  return 0
}
tickreason(){ ( cd "$1" && HB_ROT_CHECK=1 bash .hb/tick.sh 2>/dev/null ) | python3 -c "
import json, sys
d = json.load(sys.stdin); print(d['data'].get('reason', ''))"; }

# ── case: append — the horizon extends THROUGH THE SANCTIONED SURFACE ────────────────────────
case_append(){
  local P="$W/app" pre post a b
  mkh "$P"; complete_h1 "$P"
  pre=$(h1slice "$P")
  addphase "$P" H2 GATE_H1 GATE_H2 h2a    # fresh id; first new gate_entry = the last completed gate
  node "$P/.hb/hb-lint.js" "$P/.hb/dag.json" >/dev/null 2>&1 || fail "append: node lint rejected the appended plan"
  PY lint "$P/.hb/dag.json" --dir "$P" >/dev/null 2>&1 || fail "append: python lint rejected the appended plan"
  ( cd "$P" && node .hb/hb.js ready 9 2>/dev/null | grep -q '"h2a"' ) || fail "append: node resolver does not offer the appended task"
  ( cd "$P" && PY ready 9 --dir "$P" 2>/dev/null | grep -q '"h2a"' ) || fail "append: python resolver does not offer the appended task"
  # H1's projection is byte-untouched by the append + rebuild (append is a CONTINUATION, not a rewrite)
  ( cd "$P" && node .hb/hb.js rebuild >/dev/null ) || fail "append: node rebuild failed"
  post=$(h1slice "$P"); [ "$pre" = "$post" ] || fail "append: node rebuild touched H1's projection: $pre → $post"
  ( cd "$P" && PY rebuild --dir "$P" >/dev/null ) || fail "append: python rebuild failed"
  post=$(h1slice "$P"); [ "$pre" = "$post" ] || fail "append: python rebuild touched H1's projection"
  # rebuild is idempotent MODULO last_updated, per runtime
  ( cd "$P" && node .hb/hb.js rebuild >/dev/null ); a=$(norm "$P")
  ( cd "$P" && node .hb/hb.js rebuild >/dev/null ); b=$(norm "$P")
  [ "$a" = "$b" ] || fail "append: node rebuild not idempotent modulo last_updated"
  ( cd "$P" && PY rebuild --dir "$P" >/dev/null ); a=$(norm "$P")
  ( cd "$P" && PY rebuild --dir "$P" >/dev/null ); b=$(norm "$P")
  [ "$a" = "$b" ] || fail "append: python rebuild not idempotent modulo last_updated"
  assert_quiet "$P" GATE_H1 "append (an append is sanctioned quiet)"
  # degenerate-id lint surface, PINNED: an id-less phase (even >8 tasks) is a STRUCTURE error on
  # both runtimes (the shape contract, T186) — exit 1/1, the same '[?]' warning bytes and the same
  # path-named error line, no crash (the dev-tests.md claim)
  local dn dq rn rq
  P="$W/app-noid"; mkh "$P"
  python3 - "$P/.hb/dag.json" <<'EOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["phases"].append({"title": "no id", "gate_entry": None, "gate_exit": None,
                    "tasks": [{"id": f"n{i}", "title": "t", "requires": [], "description": "d"} for i in range(9)]})
json.dump(d, open(p, "w"), indent=2)
EOF
  dn=$(node "$P/.hb/hb-lint.js" "$P/.hb/dag.json" 2>&1); rn=$?
  dq=$( PY lint "$P/.hb/dag.json" --dir "$P" 2>&1 ); rq=$?
  [ "$rn" = 1 ] && [ "$rq" = 1 ] || fail "append(degenerate id): an id-less phase must be a lint ERROR on both (node=$rn py=$rq): $dn / $dq"
  echo "$dn$dq" | grep -qE 'Traceback|TypeError' && fail "append(degenerate id): a lint crashed: $dn / $dq"
  local en eq
  en=$(echo "$dn" | grep '✗' | grep 'id: missing'); eq=$(echo "$dq" | grep '✗' | grep 'id: missing')
  [ -n "$en" ] && [ "$en" = "$eq" ] || fail "append(degenerate id): the path-named 'id: missing' error differs or is missing:
node: $en
py:   $eq"
  dn=$(echo "$dn" | grep '\[?\]'); dq=$(echo "$dq" | grep '\[?\]')
  [ -n "$dn" ] && [ "$dn" = "$dq" ] || fail "append(degenerate id): the '[?]' warning bytes differ or are missing:
node: $dn
py:   $dq"
  echo "APPEND-OK"
}

# ── case: unstarted — BELOW the horizon the plan is freely editable ──────────────────────────
case_unstarted(){
  local P="$W/uns" on op
  mkh "$P"; complete_h1 "$P"
  addphase "$P" H2 GATE_H1 GATE_H2 h2a
  addphase "$P" H3 GATE_H2 GATE_H3 h3a
  # edit a never-started phase (reshape its tasks) and DROP another outright, gate included
  python3 - "$P/.hb/dag.json" <<'EOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
h2 = next(x for x in d["phases"] if x["id"] == "H2")
h2["tasks"] = [{"id": "h2b", "title": "reshaped work", "requires": [], "description": "produces h2b.txt"}]
d["phases"] = [x for x in d["phases"] if x["id"] != "H3"]
del d["gates"]["GATE_H3"]
json.dump(d, open(p, "w"), indent=2)
EOF
  node "$P/.hb/hb-lint.js" "$P/.hb/dag.json" >/dev/null 2>&1 || fail "unstarted: node lint rejected the edited plan"
  PY lint "$P/.hb/dag.json" --dir "$P" >/dev/null 2>&1 || fail "unstarted: python lint rejected the edited plan"
  on=$( cd "$P" && node .hb/hb.js doctor 2>&1 ) || fail "unstarted: node doctor exit nonzero (want ZERO PROBLEMS): $on"
  echo "$on" | grep -q '✓ hb doctor: healthy' || fail "unstarted: node doctor not healthy: $on"
  op=$( PY doctor --dir "$P" 2>&1 ) || fail "unstarted: python doctor exit nonzero: $op"
  echo "$op" | grep -q '✓ hb doctor: healthy' || fail "unstarted: python doctor not healthy: $op"
  ( cd "$P" && node .hb/hb.js ready 9 2>/dev/null | grep -q '"h2b"' ) || fail "unstarted: node resolver does not follow the edited plan"
  ( cd "$P" && PY ready 9 --dir "$P" 2>/dev/null | grep -q '"h2b"' ) || fail "unstarted: python resolver does not follow the edited plan"
  echo "UNSTARTED-OK"
}

# ── case: sanctioned quiet — the declared paths never trip the wire ──────────────────────────
case_quiet(){
  local P
  # a declared regate's window: the revision is announced; the regate machinery owns the state
  P="$W/q-win"; mkh "$P"; complete_h1 "$P"
  declare_rg "$P" GATE_H1
  weaken "$P"
  assert_quiet "$P" GATE_H1 "quiet(window)"
  # the full legitimate flow: declare → edit → rearm (different actor, evidence) → fresh pass
  P="$W/q-flow"; mkh "$P"; complete_h1 "$P"
  declare_rg "$P" GATE_H1
  editcmd "$P" 0 'python3 -c "assert 7+7==14"'
  rearm_rg "$P" GATE_H1
  ( cd "$P" && bash .hb/gate.sh GATE_H1 >/dev/null 2>&1 ) || fail "quiet(flow): revised gate re-pass failed"
  assert_quiet "$P" GATE_H1 "quiet(flow)"
  ( cd "$P" && bash .hb/gate.sh --all >/dev/null 2>&1 ) || fail "quiet(flow): node sweep not green after a sanctioned revision"
  PY gate --all --dir "$P" >/dev/null 2>&1 || fail "quiet(flow): python sweep not green after a sanctioned revision"
  # detach/reattach: retracting a dependency CLAIM touches no criteria
  P="$W/q-det"; mkh "$P"; complete_h1 "$P"
  addphase "$P" H2 GATE_H1 GATE_H2 h2a
  addphase "$P" H3 GATE_H2 GATE_H3 h3a
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js detach H3 premises changed >/dev/null 2>&1 ) || fail "quiet(detach): detach refused"
  assert_quiet "$P" GATE_H1 "quiet(detach)"
  ( cd "$P" && node .hb/hb.js reattach H3 >/dev/null 2>&1 ) || fail "quiet(detach): reattach refused"
  assert_quiet "$P" GATE_H1 "quiet(reattach)"
  echo "QUIET-OK"
}

# ── case: verbs at the replan point — detach/reattach an APPENDED phase ──────────────────────
case_verbs(){
  local P="$W/verbs"
  mkh "$P"; complete_h1 "$P"
  addphase "$P" H2 GATE_H1 GATE_H2 h2a
  addphase "$P" H3 GATE_H2 GATE_H3 h3a
  ( cd "$P" && node .hb/hb.js ready 9 2>/dev/null | grep -q '"h3a"' ) && fail "verbs: h3a ready while locked behind GATE_H2"
  ( cd "$P" && HB_ACTOR=alice node .hb/hb.js detach H3 premises changed: horizon moved >/dev/null 2>&1 ) || fail "verbs: detach refused on an appended phase"
  ( cd "$P" && node .hb/hb.js ready 9 2>/dev/null | grep -q '"h3a"' ) || fail "verbs: h3a still locked after detach (node)"
  ( cd "$P" && PY ready 9 --dir "$P" 2>/dev/null | grep -q '"h3a"' ) || fail "verbs: h3a still locked after detach (python)"
  ( cd "$P" && node .hb/hb.js reattach H3 >/dev/null 2>&1 ) || fail "verbs: reattach refused"
  ( cd "$P" && node .hb/hb.js ready 9 2>/dev/null | grep -q '"h3a"' ) && fail "verbs: h3a still unlocked after reattach"
  ( cd "$P" && node .hb/hb.js ready 9 2>/dev/null | grep -q '"h2a"' ) || fail "verbs: resolver lost the sane next task"
  echo "VERBS-OK"
}

# ── case: drift — RED TODAY: the tripwire itself ─────────────────────────────────────────────
case_drift(){
  local P on op nl pl
  # d1: a one-byte hand-edit of a completed gate's criteria — PROBLEM, twin-identical bytes
  P="$W/d1"; mkh "$P"; complete_h1 "$P"
  bytedrift "$P"
  assert_drift "$P" GATE_H1 "drift(byte-edit)"
  on=$( cd "$P" && node .hb/hb.js doctor 2>&1 ); op=$( PY doctor --dir "$P" 2>&1 )
  nl=$(echo "$on" | grep '✗' | grep GATE_H1 | sed 's/^[[:space:]]*✗[[:space:]]*//' | sort)
  pl=$(echo "$op" | grep '✗' | grep GATE_H1 | sed 's/^[[:space:]]*✗[[:space:]]*//' | sort)
  [ -n "$nl" ] && [ "$nl" = "$pl" ] || fail "drift(byte-edit): problem bytes not twin-identical across runtimes:
--- node ---
$nl
--- python ---
$pl"
  # d2: the LAUNDER — weaken, then plainly re-pass so a fresh pass pins the weakened criteria.
  # The pin HISTORY is truth: the adjacent pin pair has no sanction between → still drift.
  P="$W/d2"; mkh "$P"; complete_h1 "$P"
  weaken "$P"
  ( cd "$P" && bash .hb/gate.sh GATE_H1 >/dev/null 2>&1 ) || fail "drift(launder): weakened re-pass failed (fixture)"
  assert_drift "$P" GATE_H1 "drift(launder)"
  # d3: a bare/import pass (no criteria field) never shadows the pin sequence
  P="$W/d3"; mkh "$P"; complete_h1 "$P"
  bytedrift "$P"
  printf '%s\n' '{"event":"gate_passed","gate":"GATE_H1"}' >> "$P/.hb/events.jsonl"
  ( cd "$P" && node .hb/hb.js rebuild >/dev/null 2>&1 )
  assert_drift "$P" GATE_H1 "drift(bare-shadow)"
  # d4: an ever-pinned gate REMOVED from the dag — found via the log walk, same problem
  P="$W/d4"; mkh "$P"; complete_h1 "$P"
  python3 - "$P/.hb/dag.json" <<'EOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
del d["gates"]["GATE_H1"]
next(x for x in d["phases"] if x["id"] == "H1")["gate_exit"] = None
json.dump(d, open(p, "w"), indent=2)
EOF
  assert_drift "$P" GATE_H1 "drift(removed)"
  # d5: criteria REORDERED — identity is the ORDERED sequence
  P="$W/d5"; mkh "$P"; complete_h1 "$P"
  python3 - "$P/.hb/dag.json" <<'EOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
cr = d["gates"]["GATE_H1"]["criteria"]; d["gates"]["GATE_H1"]["criteria"] = [cr[1], cr[0]]
json.dump(d, open(p, "w"), indent=2)
EOF
  assert_drift "$P" GATE_H1 "drift(reorder)"
  # d6: desc/timeout_s-only edits do NOT drift — the honest limit: only (id, cmd) is pinned
  P="$W/d6"; mkh "$P"; complete_h1 "$P"
  python3 - "$P/.hb/dag.json" <<'EOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["gates"]["GATE_H1"]["criteria"][0]["desc"] = "reworded description"
d["gates"]["GATE_H1"]["criteria"][1]["timeout_s"] = 120
json.dump(d, open(p, "w"), indent=2)
EOF
  assert_quiet "$P" GATE_H1 "drift(desc-timeout: unpinned by design)"
  # d7: degenerate (id, cmd) values classify IDENTICALLY on both runtimes and crash neither
  # (a refuter catch: String()/str() coercions split them — missing id read 'undefined' on node
  # and 'None' on python; `true` vs "true" collided only on node). Contract: missing-vs-null id
  # and 1.0-vs-1 agree QUIET; bool-vs-string and a non-dict pin entry agree DRIFT, no traceback.
  hostile(){   # $1=dir $2=pin-criteria-json $3=dag-criteria-json — synthetic GATE_X pin vs dag
    mkh "$1"
    printf '{"event":"gate_passed","gate":"GATE_X","pass":1,"fail":0,"criteria":%s}\n' "$2" >> "$1/.hb/events.jsonl"
    python3 - "$1/.hb/dag.json" "$3" <<'EOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["gates"]["GATE_X"]["criteria"] = json.loads(sys.argv[2])
json.dump(d, open(p, "w"), indent=2)
EOF
  }
  nocrash(){   # $1=dir $2=label — neither doctor may stack-trace on the hostile log
    ( cd "$1" && node .hb/hb.js doctor 2>&1; PY doctor --dir "$1" 2>&1 ) | grep -qiE 'Traceback|TypeError: Cannot' && fail "$2: a doctor CRASHED on a hostile log"; return 0
  }
  P="$W/d7a"; hostile "$P" '[{"cmd":"zzz"}]' '[{"id":null,"cmd":"zzz"}]'
  assert_quiet "$P" GATE_X "drift(hostile: missing id == null id)"; nocrash "$P" "drift(hostile a)"
  P="$W/d7b"; hostile "$P" '[{"id":true,"cmd":"zzz"}]' '[{"id":"true","cmd":"zzz"}]'
  assert_drift "$P" GATE_X "drift(hostile: bool id vs string id)"; nocrash "$P" "drift(hostile b)"
  P="$W/d7c"; hostile "$P" '[{"id":1.0,"cmd":"zzz"}]' '[{"id":1,"cmd":"zzz"}]'
  assert_quiet "$P" GATE_X "drift(hostile: 1.0 == 1, JS number semantics)"; nocrash "$P" "drift(hostile c)"
  P="$W/d7d"; hostile "$P" '["garbage"]' '[{"id":"gx1","cmd":"zzz"}]'
  assert_drift "$P" GATE_X "drift(hostile: non-dict pin entry)"; nocrash "$P" "drift(hostile d)"
  # (e) out-of-schema NUMBERS compare as a TYPE CLASS on both runtimes — mimicking JS number
  # formatting splits at the 2^53/exponent boundaries (a refuter catch), so the honest limit is
  # class identity: a real weakening still trips on the string cmd, which stays byte-exact
  P="$W/d7e"; hostile "$P" '[{"id":9007199254740993,"cmd":"zzz"}]' '[{"id":9007199254740992,"cmd":"zzz"}]'
  assert_quiet "$P" GATE_X "drift(hostile: numbers compare as a class — the honest limit)"; nocrash "$P" "drift(hostile e)"
  P="$W/d7f"; hostile "$P" '[{"id":7,"cmd":"zzz"}]' '[{"id":7,"cmd":"yyy"}]'
  assert_drift "$P" GATE_X "drift(hostile: the string cmd stays byte-exact under a numeric id)"; nocrash "$P" "drift(hostile f)"
  echo "DRIFT-OK"
}

# ── case: cure — only a COMPLETED regate cycle absolves (RED TODAY) ──────────────────────────
case_cure(){
  local P="$W/cure"
  # the laundered fixture: drift lives in an INTERIOR pin pair — hardest to absolve honestly
  mkh "$P"; complete_h1 "$P"
  weaken "$P"
  ( cd "$P" && bash .hb/gate.sh GATE_H1 >/dev/null 2>&1 ) || fail "cure: launder re-pass failed (fixture)"
  assert_drift "$P" GATE_H1 "cure(pre: laundered drift)"
  # a bare declare cures NOTHING — absolution needs the whole cycle
  declare_rg "$P" GATE_H1
  assert_drift "$P" GATE_H1 "cure(bare declare)"
  # declare + rearm without the fresh pass cures NOTHING
  rearm_rg "$P" GATE_H1
  assert_drift "$P" GATE_H1 "cure(declare+rearm, no fresh pass)"
  # the fresh criteria-pinned pass completes the cycle → doctor goes quiet (late rigor is rigor)
  ( cd "$P" && bash .hb/gate.sh GATE_H1 >/dev/null 2>&1 ) || fail "cure: post-rearm fresh pass failed"
  assert_quiet "$P" GATE_H1 "cure(completed cycle absolves)"
  # after the cure, a NEW hand-edit drifts again — absolution is not a license
  bytedrift "$P"
  assert_drift "$P" GATE_H1 "cure(re-drift after absolution)"
  # a completed cycle on a DIFFERENT gate cures nothing (cross-gate interleave)
  local Q="$W/cure-x"; mkh "$Q"; complete_h1 "$Q"; pass_x "$Q"
  bytedrift "$Q"
  declare_rg "$Q" GATE_X
  python3 - "$Q/.hb/dag.json" <<'EOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["gates"]["GATE_X"]["criteria"][0]["cmd"] = 'python3 -c "assert 4+4==8"'
json.dump(d, open(p, "w"), indent=2)
EOF
  rearm_rg "$Q" GATE_X
  ( cd "$Q" && bash .hb/gate.sh GATE_X >/dev/null 2>&1 ) || fail "cure(cross): GATE_X cycle pass failed"
  assert_drift "$Q" GATE_H1 "cure(cross-gate cycle must not absolve)"
  # the anchor is CYCLE-scoped: an old innocent cycle + a later plain re-pass cures NOTHING —
  # the WHOLE cycle (its gate_regated included) must postdate the drifted pair's later point
  local R="$W/cure-old"; mkh "$R"; complete_h1 "$R"
  declare_rg "$R" GATE_H1
  editcmd "$R" 0 'python3 -c "assert 9+9==18"'
  rearm_rg "$R" GATE_H1
  ( cd "$R" && bash .hb/gate.sh GATE_H1 >/dev/null 2>&1 ) || fail "cure(old): innocent cycle pass failed"
  assert_quiet "$R" GATE_H1 "cure(old: innocent cycle is quiet)"
  weaken "$R"
  ( cd "$R" && bash .hb/gate.sh GATE_H1 >/dev/null 2>&1 ) || fail "cure(old): later launder re-pass failed"
  assert_drift "$R" GATE_H1 "cure(an old cycle must not launder later drift)"
  echo "CURE-OK"
}

# ── case: sweep — gate.sh --all + the py twin reach the drift (RED TODAY) ────────────────────
sweep_n(){ ( cd "$1" && bash .hb/gate.sh --all 2>&1 ); }
sweep_p(){ PY gate --all --dir "$1" 2>&1; }
assert_sweep_drift(){   # $1=dir $2=label — both runtimes: exit 1, GATE_H1 excluded + annotated
  local o r
  o=$(sweep_n "$1"); r=$?
  [ "$r" = 1 ] || fail "$2: node sweep exit $r (want 1 — a drifted gate is counted FAILING): $o"
  echo "$o" | grep -q '=== Gate: GATE_H1' && fail "$2: node sweep RE-EVALUATED the drifted gate (running weakened criteria proves nothing): $o"
  echo "$o" | grep -i 'drift' | grep -q 'GATE_H1' || fail "$2: node sweep does not annotate the drifted gate: $o"
  o=$(sweep_p "$1"); r=$?
  [ "$r" = 1 ] || fail "$2: python sweep exit $r (want 1): $o"
  echo "$o" | grep -q '=== Gate: GATE_H1' && fail "$2: python sweep re-evaluated the drifted gate: $o"
  echo "$o" | grep -i 'drift' | grep -q 'GATE_H1' || fail "$2: python sweep does not annotate the drifted gate: $o"
}
case_sweep(){
  local P o r
  # w1: drifted → excluded from re-evaluation, counted FAILING; the innocent gate still runs
  P="$W/w1"; mkh "$P"; complete_h1 "$P"; pass_x "$P"
  bytedrift "$P"
  o=$(sweep_n "$P")
  echo "$o" | grep -q '=== Gate: GATE_X' || fail "sweep(w1): node sweep dropped the INNOCENT gate: $o"
  assert_sweep_drift "$P" "sweep(w1: drifted)"
  # w2: PARKED silences nothing — park the drifted gate's phase, still counted FAILING
  ( cd "$P" && node .hb/hb.js park H1 shelved >/dev/null 2>&1 ) || fail "sweep(w2): park refused"
  assert_sweep_drift "$P" "sweep(w2: parked drift)"
  # w3: the adjacent hole this wave flips — a PARKED phase's PENDING REGATE stays in the
  # failing count (today: annotated skip, exit 0 — the silence T179.4/case_park pins)
  P="$W/w3"; mkh "$P"; complete_h1 "$P"; pass_x "$P"
  declare_rg "$P" GATE_H1
  ( cd "$P" && node .hb/hb.js park H1 shelved >/dev/null 2>&1 ) || fail "sweep(w3): park refused"
  o=$(sweep_n "$P"); r=$?
  [ "$r" = 1 ] || fail "sweep(w3): node sweep exit $r (want 1 — parked must not silence a pending regate): $o"
  echo "$o" | grep -i 'regate' | grep -q 'GATE_H1' || fail "sweep(w3): node sweep does not annotate the parked pending regate: $o"
  o=$(sweep_p "$P"); r=$?
  [ "$r" = 1 ] || fail "sweep(w3): python sweep exit $r (want 1): $o"
  echo "$o" | grep -i 'regate' | grep -q 'GATE_H1' || fail "sweep(w3): python sweep does not annotate it: $o"
  # w4: a REMOVED ever-pinned gate appears via the log walk
  P="$W/w4"; mkh "$P"; complete_h1 "$P"; pass_x "$P"
  python3 - "$P/.hb/dag.json" <<'EOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
del d["gates"]["GATE_H1"]
next(x for x in d["phases"] if x["id"] == "H1")["gate_exit"] = None
json.dump(d, open(p, "w"), indent=2)
EOF
  assert_sweep_drift "$P" "sweep(w4: removed)"
  # w5: bare imports never seed the walk — a bare-passed gate absent from the dag is NOT drift
  P="$W/w5"; mkh "$P"; pass_x "$P"
  printf '%s\n' '{"event":"gate_passed","gate":"GATE_B"}' >> "$P/.hb/events.jsonl"
  ( cd "$P" && node .hb/hb.js rebuild >/dev/null 2>&1 )
  sweep_n "$P" >/dev/null 2>&1 || fail "sweep(w5): node sweep red over a bare-passed gate (bare passes must never seed)"
  sweep_p "$P" >/dev/null 2>&1 || fail "sweep(w5): python sweep red over a bare-passed gate"
  echo "SWEEP-OK"
}

# ── case: tick — the NEW criteria_drift reason, every tick until cured (RED TODAY) ───────────
case_tick(){
  local P="$W/tick" r a
  mkh "$P"; complete_h1 "$P"
  addphase "$P" H2 GATE_H1 GATE_H2 h2a   # a dispatchable task exists: drift must OUTRANK next_task
  bytedrift "$P"
  r=$(tickreason "$P")
  [ "$r" = "criteria_drift" ] || fail "tick: node reason is '$r', want criteria_drift (human-needed, outranks dispatch)"
  a=$( ( cd "$P" && HB_ROT_CHECK=1 bash .hb/tick.sh 2>/dev/null ) | python3 -c "
import json, sys
d = json.load(sys.stdin); print(d['data'].get('action', ''))" )
  echo "$a" | grep -qi 'regate' || fail "tick: the action text does not name the cure: $a"
  # EVERY tick until cured — no once-only flag (that second read above already ticked twice);
  # a third tick still wakes criteria_drift:
  r=$(tickreason "$P")
  [ "$r" = "criteria_drift" ] || fail "tick: a later tick stopped reporting ('$r') — must fire every tick until cured"
  r=$( HB_ROT_CHECK=1 PY tick --dir "$P" 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin); print(d['data'].get('reason', ''))" )   # HB_ROT_CHECK pinned: the suite exports 0 (fast fixture ticks) and the knob gates the whole doctor-driven block
  [ "$r" = "criteria_drift" ] || fail "tick: python reason is '$r', want criteria_drift (reason keys identical across runtimes)"
  # both DRIVERS stop on drift: each executor escalates criteria_drift and exits nonzero —
  # never a busy-loop, never a dispatch past it (the exec claim plan-to-the-horizon.md anchors here)
  o=$( cd "$P" && HB_ROT_CHECK=1 HB_EXEC_BACKEND=script HB_EXEC_CMD='cat >/dev/null' node .hb/hb-exec.js run 2>&1 ); x=$?
  [ "$x" -ne 0 ] || fail "tick: node hb-exec exited 0 over criteria_drift (must stop)"
  echo "$o" | grep -q 'HB-EXEC STOP: criteria_drift' || fail "tick: node hb-exec did not escalate criteria_drift: $o"
  o=$( HB_ROT_CHECK=1 HB_EXEC_BACKEND=script HB_EXEC_CMD='cat >/dev/null' PY exec run --dir "$P" 2>&1 ); x=$?
  [ "$x" -ne 0 ] || fail "tick: python hb exec exited 0 over criteria_drift (must stop)"
  echo "$o" | grep -q 'HB-EXEC STOP: criteria_drift' || fail "tick: python hb exec did not escalate criteria_drift: $o"
  # the cure un-sticks the loop: full cycle → the tick goes back to work
  declare_rg "$P" GATE_H1
  rearm_rg "$P" GATE_H1
  ( cd "$P" && bash .hb/gate.sh GATE_H1 >/dev/null 2>&1 ) || fail "tick: cure cycle fresh pass failed"
  r=$(tickreason "$P")
  [ "$r" = "next_task" ] || fail "tick: node reason after the cure is '$r', want next_task"
  # a dispatching tick LEASES the task it hands out (atomic claim) — free it so the python
  # twin can dispatch too (the stale-reclaim path would do the same after the deadline)
  rm -rf "$P/.hb/leases"/* 2>/dev/null
  r=$( HB_ROT_CHECK=1 PY tick --dir "$P" 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin); print(d['data'].get('reason', ''))" )
  [ "$r" = "next_task" ] || fail "tick: python reason after the cure is '$r', want next_task"
  echo "TICK-OK"
}

# ── selftest: mutation teeth ──────────────────────────────────────────────────────────────────
mutate(){ local b; b=$(grep -c "$2" "$1" 2>/dev/null || true); [ "${b:-0}" -gt 0 ] || fail "selftest: no '$2' marker in $1"; sed -i "/$2/d" "$1"; }
mkpycopy(){ cp -r "$ROOT/py/src" "$1"; }
selftest(){
  local P o r
  # s1: a duplicate appended id must be CAUGHT by the lint the append case leans on
  P="$W/s1"; mkh "$P"; complete_h1 "$P"
  addphase "$P" H2 GATE_H1 GATE_H2 h2a dupid
  node "$P/.hb/hb-lint.js" "$P/.hb/dag.json" >/dev/null 2>&1 && fail "selftest s1: node lint accepted a duplicate appended id"
  PY lint "$P/.hb/dag.json" --dir "$P" >/dev/null 2>&1 && fail "selftest s1: python lint accepted a duplicate appended id"
  # s2: a generator that MUTATES H1's record must redden the untouched-slice comparison
  P="$W/s2"; mkh "$P"; complete_h1 "$P"
  local pre post
  pre=$(h1slice "$P")
  addphase "$P" H2 GATE_H1 GATE_H2 h2a mutate
  ( cd "$P" && node .hb/hb.js rebuild >/dev/null 2>&1 )
  post=$(h1slice "$P")
  [ "$pre" = "$post" ] && fail "selftest s2: the H1-slice comparison is blind — a mutated H1 record left it identical"
  # s3: the node drift-guard stripped from a COPY → the doctor goes silent (the check's teeth)
  P="$W/s3"; mkh "$P"; complete_h1 "$P"
  bytedrift "$P"
  mutate "$P/.hb/hb.js" "drift-guard: doctor"
  node --check "$P/.hb/hb.js" 2>/dev/null || fail "selftest s3: stripped hb.js no longer parses (marker on a structural line)"
  o=$( cd "$P" && node .hb/hb.js doctor 2>&1 )
  echo "$o" | grep '✗' | grep -q GATE_H1 && fail "selftest s3: the drift problem survived its guard strip (marker not load-bearing)"
  # s4: the python drift-guard stripped from a COPY → same silence
  P="$W/s4"; mkh "$P"; complete_h1 "$P"
  bytedrift "$P"
  mkpycopy "$W/py-s4"; mutate "$W/py-s4/heartbeat/doctor.py" "drift-guard: doctor"
  python3 -c "import sys; sys.path.insert(0, '$W/py-s4'); import heartbeat.doctor" || fail "selftest s4: stripped doctor.py no longer imports"
  o=$( HB_PY_SRC="$W/py-s4" PY doctor --dir "$P" 2>&1 )
  echo "$o" | grep '✗' | grep -q GATE_H1 && fail "selftest s4: the python drift problem survived its guard strip"
  # s5: the sweep guard stripped from the fixture's gate.sh → the drifted gate stops counting
  P="$W/s5"; mkh "$P"; complete_h1 "$P"; pass_x "$P"
  bytedrift "$P"
  mutate "$P/.hb/gate.sh" "drift-guard: sweep"
  bash -n "$P/.hb/gate.sh" 2>/dev/null || fail "selftest s5: stripped gate.sh no longer parses (marker on a structural line)"
  o=$( cd "$P" && bash .hb/gate.sh --all 2>&1 ); r=$?
  if [ "$r" = 1 ]; then echo "$o" | grep -i 'drift' | grep -q 'GATE_H1' && fail "selftest s5: the sweep drift teeth survived their guard strip"; fi
  # s6: the tick guard stripped from the fixture's tick.sh → the wake reason falls back to work
  P="$W/s6"; mkh "$P"; complete_h1 "$P"
  addphase "$P" H2 GATE_H1 GATE_H2 h2a
  bytedrift "$P"
  mutate "$P/.hb/tick.sh" "drift-guard: tick"
  bash -n "$P/.hb/tick.sh" 2>/dev/null || fail "selftest s6: stripped tick.sh no longer parses (marker on a structural line)"
  r=$(tickreason "$P")
  [ "$r" = "criteria_drift" ] && fail "selftest s6: criteria_drift survived its guard strip (marker not load-bearing)"
  # s7: the PYTHON sweep guards stripped from a runtime COPY → the drifted gate stops counting
  # (both runtimes' guard classes get stripped — a refuter catch: only node's were)
  P="$W/s7"; mkh "$P"; complete_h1 "$P"; pass_x "$P"
  bytedrift "$P"
  mkpycopy "$W/py-s7"; mutate "$W/py-s7/heartbeat/gate.py" "drift-guard: sweep"; mutate "$W/py-s7/heartbeat/cli.py" "drift-guard: sweep"
  python3 -c "import sys; sys.path.insert(0, '$W/py-s7'); import heartbeat.gate, heartbeat.cli" || fail "selftest s7: stripped gate.py/cli.py no longer import (marker on a structural line)"
  o=$( HB_PY_SRC="$W/py-s7" PY gate --all --dir "$P" 2>&1 ); r=$?
  if [ "$r" = 1 ]; then echo "$o" | grep -i 'drift' | grep -q 'GATE_H1' && fail "selftest s7: the python sweep drift teeth survived their guard strip"; fi
  # s8: the PYTHON tick guards stripped from a runtime COPY → the wake reason falls back to work
  P="$W/s8"; mkh "$P"; complete_h1 "$P"
  addphase "$P" H2 GATE_H1 GATE_H2 h2a
  bytedrift "$P"
  mkpycopy "$W/py-s8"; mutate "$W/py-s8/heartbeat/tick.py" "drift-guard: tick"
  python3 -c "import sys; sys.path.insert(0, '$W/py-s8'); import heartbeat.tick" || fail "selftest s8: stripped tick.py no longer imports (marker on a structural line — the IndentationError class)"
  r=$( HB_ROT_CHECK=1 HB_PY_SRC="$W/py-s8" PY tick --dir "$P" 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin); print(d['data'].get('reason', ''))" )   # HB_ROT_CHECK pinned ON so the strip, not the knob, is what silences the reason
  [ "$r" = "criteria_drift" ] && fail "selftest s8: python criteria_drift survived its guard strip"
  echo "REPLAN-SELFTEST-OK"
}

# ── dispatch ──────────────────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--selftest" ]; then selftest; exit 0; fi
sel="${1:-all}"
for c in append unstarted quiet verbs drift cure sweep tick; do
  if [ "$sel" = all ] || [ "$sel" = "$c" ]; then "case_$c" || exit 1; fi
done
[ "$sel" = all ] && echo "REPLAN-OK"
exit 0
