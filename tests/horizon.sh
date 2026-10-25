#!/usr/bin/env bash
# horizon.sh — the knowledge horizon made machine-visible (T185, the H1 spec — written BEFORE
# the mechanism).
#
# The contract: a phase may carry "horizon": true. When it is the LAST LIVE (non-parked) phase
# and every live phase is complete, the resolver returns {"type":"replan_pending","phase":<id>}
# instead of all_done (unless that phase is in the projected state.horizon_closed). The tick
# wakes replan_pending ONCE (the .replan-alerted flag stores the phase id), then sleeps
# replan_waiting. Exactly two moves are sanctioned: append the next horizon's phases (the plan
# continues) or `hb horizon close --reason <why>` (the recorded end-of-project decision). The
# close is a VERDICT: fail-closed (no event) when the horizon is not reached, unflagged, already
# closed per the projection, reasonless, on an all-parked plan, or while any live gate's regate
# cycle is open in any state. An all-parked plan keeps today's all_done. The flag is inert
# anywhere but the last live phase. hb-lint type-checks it; hb-audit's speculative_tail rule
# names the cut point of a plan whose trailing phases are unverified guesses. Reports print a
# horizon line. Honest limits pinned as behavior: deleting the flag or parking the phase
# silences the wake (plan surface, unpinned by the drift tripwire).
#
# SPEC-FIRST: every marker / close / append / lint / audit / report case is RED TODAY by design.
#
#   bash tests/horizon.sh [case]   cases: marker close append flags limits parked lint audit report
#   bash tests/horizon.sh --selftest
# Prints <CASE>-OK per case, HORIZON-OK when all pass, HORIZON-SELFTEST-OK for teeth.
set -u
# Env hygiene: under a gate criterion, gate.sh exports HB_DIR/PROJECT_DIR/GATE — and the fixture
# projects' copied CLIs honor env HB_DIR. A proof must never inherit a caller's project pointers.
unset HB_DIR PROJECT_DIR GATE G DAG_FILE EVENTS_FILE 2>/dev/null || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export HB_NO_GIT=1 STUCK_TICKS=999
fail(){ echo "FAIL: $1"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
PY(){ PYTHONPATH="${HB_PY_SRC:-$ROOT/py/src}" python3 -m heartbeat.cli "$@"; }

# ── fixture: H1 → H2, H2 carries the horizon flag ([$2]=noflag drops it) ─────────────────────
mkh(){   # $1 = dir [$2 = noflag]
  mkdir -p "$1"; ( cd "$1" && git init -q >/dev/null 2>&1; bash "$ROOT/plugin/bootstrap.sh" . >/dev/null 2>&1 )
  python3 - "$1/.hb/dag.json" "${2:-flag}" <<'EOF'
import json, sys
p, mode = sys.argv[1], sys.argv[2]
d = {"project": "horizon-fixture",
     "phases": [
       {"id": "H1", "title": "first", "gate_entry": None, "gate_exit": "GATE_H1",
        "tasks": [{"id": "h1a", "title": "h1 work", "requires": [], "description": "h1 work"}]},
       {"id": "H2", "title": "second", "gate_entry": "GATE_H1", "gate_exit": "GATE_H2",
        "tasks": [{"id": "h2a", "title": "h2 work", "requires": [], "description": "h2 work"}]}],
     "gates": {
       "GATE_H1": {"desc": "h1 gate", "criteria": [{"id": "g1", "desc": "behavioral", "cmd": "python3 -c \"assert 1+1==2\""}]},
       "GATE_H2": {"desc": "h2 gate", "criteria": [{"id": "g2", "desc": "behavioral", "cmd": "python3 -c \"assert 2+2==4\""}]}}}
if mode != "noflag":
    d["phases"][1]["horizon"] = True
json.dump(d, open(p, "w"), indent=2)
EOF
}
dotask(){ ( cd "$1" && HB_ACTOR=doer node .hb/hb.js start "$2" >/dev/null && HB_ACTOR=doer node .hb/hb.js done "$2" >/dev/null ) || fail "fixture: task $2 failed"; }
pass(){ ( cd "$1" && bash .hb/gate.sh "$2" >/dev/null 2>&1 ) || fail "fixture: $2 pass failed"; }
reach(){ dotask "$1" h1a; pass "$1" GATE_H1; dotask "$1" h2a; pass "$1" GATE_H2; }   # through the CLI, criteria-pinned passes
addphase(){   # $1=dir $2=id $3=entry $4=exit $5=taskid [$6=flag]
  python3 - "$1/.hb/dag.json" "$2" "$3" "$4" "$5" "${6:-noflag}" <<'EOF'
import json, sys
p, pid, entry, exit_, tid, flag = sys.argv[1:7]
d = json.load(open(p))
ph = {"id": pid, "title": f"appended {pid}", "gate_entry": entry, "gate_exit": exit_,
      "tasks": [{"id": tid, "title": f"{tid} work", "requires": [], "description": f"{tid} work"}]}
if flag == "flag":
    ph["horizon"] = True
d["phases"].append(ph)
d["gates"][exit_] = {"desc": f"{pid} gate", "criteria": [{"id": f"g_{tid}", "desc": "behavioral", "cmd": "python3 -c \"assert 5+5==10\""}]}
json.dump(d, open(p, "w"), indent=2)
EOF
}
dagedit(){   # $1=dir $2=python statement over d (the parsed dag)
  python3 - "$1/.hb/dag.json" "$2" <<'EOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); exec(sys.argv[2]); json.dump(d, open(p, "w"), indent=2)
EOF
}
field(){ python3 -c "
import json, sys
try: d = json.loads(sys.stdin.read())
except Exception: print('<unparseable>'); sys.exit(0)
for k in sys.argv[1].split('.'):
    d = d.get(k, '') if isinstance(d, dict) else ''
print(d if not isinstance(d, (dict, list)) else json.dumps(d))" "$1"; }
# resolver verdict, per runtime (node reads state.json — rebuild first so hand-appended events count)
res(){ if [ "$2" = node ]; then ( cd "$1" && node .hb/hb.js rebuild >/dev/null 2>&1; node .hb/hb-next-task.js .hb/state.json 2>&1 ); else PY next --dir "$1" 2>&1; fi; }
tk(){ if [ "$2" = node ]; then ( cd "$1" && bash .hb/tick.sh 2>/dev/null ); else PY tick --dir "$1" 2>/dev/null; fi; }
hclose(){   # $1=dir $2=runtime $3..=args — the close verb
  local d="$1" rt="$2"; shift 2
  if [ "$rt" = node ]; then ( cd "$d" && HB_ACTOR="${CLOSER:-closer}" node .hb/hb.js horizon "$@" 2>&1 ); else HB_ACTOR="${CLOSER:-closer}" PY horizon "$@" --dir "$d" 2>&1; fi
}
rep(){ if [ "$2" = node ]; then node "$1/.hb/hb-report.js" "$1/.hb" 2>&1; else PY report --dir "$1" 2>&1; fi; }
nev(){ wc -l < "$1/.hb/events.jsonl" | tr -d ' '; }
refused(){   # $1=dir $2=runtime $3=label $4..=close args — nonzero exit, NO event, no crash
  local d="$1" rt="$2" lb="$3" n0 o r; shift 3
  n0=$(nev "$d"); o=$(hclose "$d" "$rt" "$@"); r=$?
  [ "$r" -ne 0 ] || fail "$lb ($rt): close ACCEPTED (exit 0), want refused: $o"
  [ "$(nev "$d")" = "$n0" ] || fail "$lb ($rt): a refused close APPENDED an event"
  echo "$o" | grep -qE 'Traceback|TypeError|IndexError|Cannot read prop' && fail "$lb ($rt): the close CRASHED instead of refusing: $o"
  return 0
}
accepted(){   # $1=dir $2=runtime $3=label $4..=args
  local d="$1" rt="$2" lb="$3" o; shift 3
  o=$(hclose "$d" "$rt" "$@") || fail "$lb ($rt): close refused, want accepted: $o"
  [ "$(tail -n1 "$d/.hb/events.jsonl" | field event)" = horizon_closed ] || fail "$lb ($rt): the accepted close appended no horizon_closed event"
}
declare_rg(){ ( cd "$1" && HB_ACTOR=carol node .hb/hb.js regate "$2" premise died >/dev/null 2>&1 ) || fail "fixture: regate declare refused"; }
rearm_rg(){
  printf 'Rearm evidence for %s (task h2a): the premise died; the revised criteria were run by hand and hold.\n' "$2" > "$1/e.md"
  ( cd "$1" && HB_ACTOR=dave node .hb/hb.js regate "$2" --rearm --artifact e.md >/dev/null 2>&1 ) || fail "fixture: rearm refused"
}
assert_res(){   # $1=dir $2=want-type [$3=want-phase] $4=label — both runtimes, identical keys
  local rt o t ph
  for rt in node py; do
    o=$(res "$1" "$rt"); t=$(echo "$o" | field type); ph=$(echo "$o" | field phase)
    [ "$t" = "$2" ] || fail "$4 ($rt): resolver type '$t', want '$2': $o"
    if [ -n "${3:-}" ]; then [ "$ph" = "$3" ] || fail "$4 ($rt): resolver phase '$ph', want '$3': $o"; fi
  done
}

# ── case: marker — the resolver, the once-wake, the regression pin, the drivers ──────────────
case_marker(){
  local P o r rt kn kp
  # m1: a reached flagged horizon verdicts replan_pending on BOTH resolvers, identical keys
  P="$W/m1"; mkh "$P"; reach "$P"
  assert_res "$P" replan_pending H2 "m1"
  kn=$(res "$P" node | python3 -c "import json,sys; print(sorted(json.load(sys.stdin)))")
  kp=$(res "$P" py | python3 -c "import json,sys; print(sorted(json.load(sys.stdin)))")
  [ "$kn" = "$kp" ] && [ "$kn" = "['phase', 'type']" ] || fail "m1: resolver keys differ or are wrong: node=$kn py=$kp"
  # the sparse projection: no close event → NO horizon_closed key, on both rebuilds
  ( cd "$P" && node .hb/hb.js rebuild >/dev/null ); grep -q horizon_closed "$P/.hb/state.json" && fail "m1: node projected horizon_closed with no close event (sparse-projection pin)"
  PY rebuild --dir "$P" >/dev/null; grep -q horizon_closed "$P/.hb/state.json" && fail "m1: python projected horizon_closed with no close event"
  # m2: each tick wakes ONCE, the action naming BOTH sanctioned moves; the next tick sleeps
  for rt in node py; do
    P="$W/m2-$rt"; mkh "$P"; reach "$P"
    o=$(tk "$P" "$rt")
    [ "$(echo "$o" | field wakeAgent)" = True ] || [ "$(echo "$o" | field wakeAgent)" = true ] || fail "m2 ($rt): the reached horizon did not WAKE: $o"
    [ "$(echo "$o" | field data.reason)" = replan_pending ] || fail "m2 ($rt): wake reason is not replan_pending: $o"
    a=$(echo "$o" | field data.action)
    echo "$a" | grep -qi 'append' || fail "m2 ($rt): the action does not name the append path: $a"
    echo "$a" | grep -q 'horizon close' || fail "m2 ($rt): the action does not name the close verb: $a"
    o=$(tk "$P" "$rt")
    [ "$(echo "$o" | field data.reason)" = replan_waiting ] || fail "m2 ($rt): the second tick did not sleep replan_waiting: $o"
    case "$(echo "$o" | field wakeAgent)" in True|true) fail "m2 ($rt): the second tick woke again (once-only): $o";; esac
  done
  # m3: the same fixture WITHOUT the marker verdicts all_done — the regression pin
  P="$W/m3"; mkh "$P" noflag; reach "$P"
  assert_res "$P" all_done "" "m3"
  for rt in node py; do
    rm -f "$P/.hb/.all-done-alerted"
    [ "$(tk "$P" "$rt" | field data.reason)" = all_done ] || fail "m3 ($rt): unflagged tick did not wake all_done"
  done
  # m4: both exec drivers STOP on replan_pending (never dispatch past it, never exit 0)
  P="$W/m4n"; mkh "$P"; reach "$P"
  o=$( cd "$P" && HB_EXEC_BACKEND=script HB_EXEC_CMD='cat >/dev/null' node .hb/hb-exec.js run 2>&1 ); r=$?
  [ "$r" -ne 0 ] || fail "m4: node hb-exec exited 0 at a reached horizon"
  echo "$o" | grep -q 'HB-EXEC STOP: replan_pending — H2' || fail "m4: node hb-exec did not stop on replan_pending naming H2: $o"
  P="$W/m4p"; mkh "$P"; reach "$P"
  o=$( HB_EXEC_BACKEND=script HB_EXEC_CMD='cat >/dev/null' PY exec run --dir "$P" 2>&1 ); r=$?
  [ "$r" -ne 0 ] || fail "m4: python hb exec exited 0 at a reached horizon"
  echo "$o" | grep -q 'HB-EXEC STOP: replan_pending — H2' || fail "m4: python hb exec did not stop on replan_pending naming H2: $o"
  # ...and on EVERY later run too, after the once-only wake was consumed (never an exit-0 IDLE),
  # whichever runtime's tick consumed it
  for rt in node py; do
    P="$W/m4-again-$rt"; mkh "$P"; reach "$P"
    [ "$(tk "$P" "$rt" | field data.reason)" = replan_pending ] || fail "m4 ($rt): fixture wake missing"
    o=$( cd "$P" && HB_EXEC_BACKEND=script HB_EXEC_CMD='cat >/dev/null' node .hb/hb-exec.js run 2>&1 ); r=$?
    [ "$r" -ne 0 ] && echo "$o" | grep -q 'HB-EXEC STOP: replan_pending — H2' || fail "m4 ($rt-woken): node hb-exec went IDLE/exit 0 after the wake was consumed: $o"
    o=$( HB_EXEC_BACKEND=script HB_EXEC_CMD='cat >/dev/null' PY exec run --dir "$P" 2>&1 ); r=$?
    [ "$r" -ne 0 ] && echo "$o" | grep -q 'HB-EXEC STOP: replan_pending — H2' || fail "m4 ($rt-woken): python hb exec went IDLE/exit 0 after the wake was consumed: $o"
  done
  echo "MARKER-OK"
}

# ── case: close — the recorded decision, fail-closed ─────────────────────────────────────────
case_close(){
  local P Q rt o
  for rt in node py; do
    # c1: not reached (H2 incomplete) → refused; unflagged reached horizon → refused
    P="$W/c1-$rt"; mkh "$P"; dotask "$P" h1a; pass "$P" GATE_H1
    refused "$P" "$rt" "c1(not reached)" close --reason "done here"
    P="$W/c1u-$rt"; mkh "$P" noflag; reach "$P"
    refused "$P" "$rt" "c1(unflagged)" close --reason "done here"
    # c2: missing / empty reason → refused; a wrong subaction → refused
    P="$W/c2-$rt"; mkh "$P"; reach "$P"
    refused "$P" "$rt" "c2(no reason)" close
    refused "$P" "$rt" "c2(empty reason)" close --reason ""
    refused "$P" "$rt" "c2(wrong subaction)" open --reason "x"
    # c3: a valid close appends horizon_closed {phase, reason, actor}, reprojects, then all_done
    CLOSER=erin accepted "$P" "$rt" "c3" close --reason "the learning is recorded"
    tail -n1 "$P/.hb/events.jsonl" | python3 -c "
import json, sys
e = json.loads(sys.stdin.read())
assert e.get('phase') == 'H2', e
assert e.get('reason') == 'the learning is recorded', e
assert e.get('actor') == 'erin', e" || fail "c3 ($rt): the horizon_closed event lacks phase/reason/actor: $(tail -n1 "$P/.hb/events.jsonl")"
    python3 -c "
import json, sys
s = json.load(open(sys.argv[1])); assert s.get('horizon_closed') == ['H2'], s.get('horizon_closed')" "$P/.hb/state.json" || fail "c3 ($rt): state.json does not project horizon_closed: [H2]"
    rm -f "$P/.hb/.all-done-alerted"
    [ "$(tk "$P" "$rt" | field data.reason)" = all_done ] || fail "c3 ($rt): the tick after a close does not wake all_done"
    # already closed (the projection says so) → refused
    refused "$P" "$rt" "c3(already closed)" close --reason "again"
    # c4: rebuild preserves the verdict
    ( cd "$P" && node .hb/hb.js rebuild >/dev/null ) && assert_res "$P" all_done "" "c4(node rebuild)"
    PY rebuild --dir "$P" >/dev/null && assert_res "$P" all_done "" "c4(py rebuild)"
    # c5: ONE source — close, 'initialized' resets, replay the completion history → the horizon
    # is open again: re-verdict replan_pending and re-accept a close (a log scan would wedge)
    P="$W/c5-$rt"; mkh "$P"; reach "$P"
    accepted "$P" "$rt" "c5(first close)" close --reason "first"
    printf '%s\n' '{"event":"initialized","project":"."}' \
      '{"event":"task_done","task":"h1a"}' '{"event":"gate_passed","gate":"GATE_H1"}' \
      '{"event":"task_done","task":"h2a"}' '{"event":"gate_passed","gate":"GATE_H2"}' >> "$P/.hb/events.jsonl"
    ( cd "$P" && node .hb/hb.js rebuild >/dev/null )
    assert_res "$P" replan_pending H2 "c5(after reset + replay)"
    accepted "$P" "$rt" "c5(re-close)" close --reason "second"
    # c6: the regate perimeter, all FOUR shapes
    P="$W/c6-$rt"; mkh "$P"; reach "$P"
    declare_rg "$P" GATE_H2
    refused "$P" "$rt" "c6(declared)" close --reason "x"
    rearm_rg "$P" GATE_H2
    refused "$P" "$rt" "c6(rearmed, no fresh pass)" close --reason "x"
    pass "$P" GATE_H2
    accepted "$P" "$rt" "c6(fresh pass reopens)" close --reason "after the revision"
    Q="$W/c6m-$rt"; mkh "$Q"; reach "$Q"
    dagedit "$Q" 'd["gates"]["GATE_H2"]["regate"] = {"pending": True, "reason": "hand marker", "actor": "x"}'
    refused "$Q" "$rt" "c6(a dag-only PENDING marker, no log event — the regateBlocks clause isolated)" close --reason "x"
    Q="$W/c6e-$rt"; mkh "$Q"; reach "$Q"
    declare_rg "$Q" GATE_H1
    refused "$Q" "$rt" "c6(open revision on an EARLIER live gate)" close --reason "x"
    Q="$W/c6h-$rt"; mkh "$Q"; reach "$Q"
    declare_rg "$Q" GATE_H2
    dagedit "$Q" 'd["gates"]["GATE_H2"].pop("regate", None)'
    refused "$Q" "$rt" "c6(marker hand-cleared — the log is truth)" close --reason "x"
    # c7: an ALL-PARKED plan → the not-reached refusal, never a throw
    P="$W/c7-$rt"; mkh "$P"; reach "$P"
    dagedit "$P" 'for ph in d["phases"]: ph["parked"] = True'
    refused "$P" "$rt" "c7(all parked)" close --reason "x"
  done
  echo "CLOSE-OK"
}

# ── case: append — the other sanctioned move; the close is phase-scoped ──────────────────────
case_append(){
  local P rt o
  for rt in node py; do
    # a1/a2: append past a reached horizon → the ticks hand out the new work; the old flag is inert
    P="$W/a1-$rt"; mkh "$P"; reach "$P"
    addphase "$P" H3 GATE_H2 GATE_H3 h3a
    for r in node py; do
      o=$(res "$P" "$r")
      [ "$(echo "$o" | field id)" = h3a ] || fail "a2 ($r): the old flag is not inert mid-plan — resolver: $o"
    done
    o=$(tk "$P" "$rt")
    [ "$(echo "$o" | field data.reason)" = next_task ] || fail "a1 ($rt): the tick after an append is not next_task: $o"
    echo "$o" | grep -q '"h3a"' || fail "a1 ($rt): the tick did not hand out the appended task: $o"
    # a3: the old phase's close does not quiet a NEW flagged horizon
    P="$W/a3-$rt"; mkh "$P"; reach "$P"
    accepted "$P" "$rt" "a3(close H2)" close --reason "first horizon"
    addphase "$P" H3 GATE_H2 GATE_H3 h3a flag
    dotask "$P" h3a; pass "$P" GATE_H3
    assert_res "$P" replan_pending H3 "a3(new horizon)"
    # a4: a STALE flag never silences a newer horizon — wake, append, complete with NO tick between
    P="$W/a4-$rt"; mkh "$P"; reach "$P"
    [ "$(tk "$P" "$rt" | field data.reason)" = replan_pending ] || fail "a4 ($rt): the first horizon did not wake"
    addphase "$P" H3 GATE_H2 GATE_H3 h3a flag
    dotask "$P" h3a; pass "$P" GATE_H3
    o=$(tk "$P" "$rt")
    [ "$(echo "$o" | field data.reason)" = replan_pending ] || fail "a4 ($rt): the newer horizon was SILENCED by a stale flag: $o"
    echo "$o" | grep -q '"H3"' || fail "a4 ($rt): the wake does not name the new phase H3: $o"
  done
  echo "APPEND-OK"
}

# ── case: flags — the once-flag is cleared on the all_done and task branches; the notifier ────
case_flags(){
  local P rt o n
  for rt in node py; do
    # f1: all_done branch clears it — wake, park the horizon (all_done), unpark → it wakes AGAIN
    P="$W/f1-$rt"; mkh "$P"; reach "$P"
    [ "$(tk "$P" "$rt" | field data.reason)" = replan_pending ] || fail "f1 ($rt): first wake missing"
    ( cd "$P" && node .hb/hb.js park H2 shelved >/dev/null 2>&1 ) || fail "f1: park refused"
    tk "$P" "$rt" >/dev/null
    [ -f "$P/.hb/.replan-alerted" ] && fail "f1 ($rt): the all_done branch left the replan flag set"
    ( cd "$P" && node .hb/hb.js unpark H2 >/dev/null 2>&1 ) || fail "f1: unpark refused"
    [ "$(tk "$P" "$rt" | field data.reason)" = replan_pending ] || fail "f1 ($rt): the re-reached horizon did not wake again"
    # f2: task branch clears it — wake, append UNFLAGGED H3 (dispatch), complete it, park H3 → H2 wakes again
    P="$W/f2-$rt"; mkh "$P"; reach "$P"
    [ "$(tk "$P" "$rt" | field data.reason)" = replan_pending ] || fail "f2 ($rt): first wake missing"
    addphase "$P" H3 GATE_H2 GATE_H3 h3a
    [ "$(tk "$P" "$rt" | field data.reason)" = next_task ] || fail "f2 ($rt): the append did not dispatch"
    [ -f "$P/.hb/.replan-alerted" ] && fail "f2 ($rt): the task branch left the replan flag set"
    rm -rf "$P/.hb/leases"/* 2>/dev/null
    dotask "$P" h3a; pass "$P" GATE_H3
    ( cd "$P" && node .hb/hb.js park H3 shelved >/dev/null 2>&1 ) || fail "f2: park refused"
    [ "$(tk "$P" "$rt" | field data.reason)" = replan_pending ] || fail "f2 ($rt): H2 did not wake again after the task branch"
  done
  # f3: tick.sh notifies replan_pending ONCE per horizon, naming the phase — the notify log holds
  # EXACTLY that one line after the wake + two waiting ticks, a second appended horizon adds EXACTLY
  # one replan_pending|H3 line, and no tick appends an event (the log records decisions only)
  local nt e0
  P="$W/f3"; mkh "$P"; reach "$P"
  nt(){ ( cd "$1" && HB_NOTIFY_CMD='printf "%s|%s\n" "$1" "$3" >> "$PROJECT_DIR/notify.log"' bash .hb/tick.sh >/dev/null 2>&1 ); }
  e0=$(nev "$P")
  nt "$P"; nt "$P"; nt "$P"
  [ "$(cat "$P/notify.log" 2>/dev/null)" = "replan_pending|H2" ] || fail "f3: after the wake + two waiting ticks the notify log is not exactly 'replan_pending|H2': $(cat "$P/notify.log" 2>/dev/null)"
  [ "$(nev "$P")" = "$e0" ] || fail "f3: a horizon tick appended an event"
  addphase "$P" H3 GATE_H2 GATE_H3 h3a flag
  dotask "$P" h3a; pass "$P" GATE_H3
  e0=$(nev "$P")
  nt "$P"; nt "$P"
  [ "$(cat "$P/notify.log")" = "replan_pending|H2
replan_pending|H3" ] || fail "f3: the second horizon did not notify exactly once: $(cat "$P/notify.log")"
  [ "$(nev "$P")" = "$e0" ] || fail "f3: a horizon tick appended an event (second horizon)"
  # f4: the once-flag is ONE cross-runtime surface — a wake by either tick quiets the OTHER runtime's
  # next tick (replan_waiting) — and NEITHER tick appends an event on the wake or the waiting sleep
  local a bb
  for a in node py; do
    bb=py; [ "$a" = py ] && bb=node
    P="$W/f4-$a"; mkh "$P"; reach "$P"
    e0=$(nev "$P")
    [ "$(tk "$P" "$a" | field data.reason)" = replan_pending ] || fail "f4: the $a tick did not wake"
    o=$(tk "$P" "$bb")
    [ "$(echo "$o" | field data.reason)" = replan_waiting ] || fail "f4: after a $a wake the $bb tick did not sleep replan_waiting (the flag is not one surface): $o"
    tk "$P" "$a" >/dev/null
    [ "$(nev "$P")" = "$e0" ] || fail "f4: a horizon tick appended an event ($a wake, $bb + $a waiting)"
  done
  echo "FLAGS-OK"
}

# ── case: limits — the honest limits pinned as behavior ──────────────────────────────────────
case_limits(){
  local P o
  # l1: deleting the flag from the completed phase → all_done, doctor QUIET
  P="$W/l1"; mkh "$P"; reach "$P"
  dagedit "$P" 'd["phases"][1].pop("horizon")'
  assert_res "$P" all_done "" "l1(flag deleted)"
  o=$( cd "$P" && node .hb/hb.js doctor 2>&1 ) || fail "l1: node doctor not quiet: $o"
  o=$( PY doctor --dir "$P" 2>&1 ) || fail "l1: python doctor not quiet: $o"
  # l2: parking the flagged phase → all_done, doctor QUIET
  P="$W/l2"; mkh "$P"; reach "$P"
  ( cd "$P" && node .hb/hb.js park H2 shelved >/dev/null 2>&1 ) || fail "l2: park refused"
  assert_res "$P" all_done "" "l2(flagged phase parked)"
  o=$( cd "$P" && node .hb/hb.js doctor 2>&1 ) || fail "l2: node doctor not quiet: $o"
  o=$( PY doctor --dir "$P" 2>&1 ) || fail "l2: python doctor not quiet: $o"
  echo "LIMITS-OK"
}

# ── case: parked — p1: an all-parked plan keeps today's all_done, no crash ───────────────────
case_parked(){
  local P rt o
  P="$W/p1"; mkh "$P"
  dagedit "$P" 'for ph in d["phases"]: ph["parked"] = True'
  assert_res "$P" all_done "" "p1(all parked, flag on a parked phase)"
  for rt in node py; do
    rm -f "$P/.hb/.all-done-alerted"
    o=$(tk "$P" "$rt")
    [ "$(echo "$o" | field data.reason)" = all_done ] || fail "p1 ($rt): the all-parked tick is not all_done: $o"
  done
  echo "PARKED-OK"
}

# ── case: lint — the marker is type-checked, position never linted ───────────────────────────
case_lint(){
  local P on op rn rp
  P="$W/n1"; mkh "$P"
  # every non-boolean — including the values where JS and python idioms diverge (1/0/1.0 compare
  # equal to True/False in python; null) — is a lint ERROR with identical bytes
  local nv
  for nv in '"yes"' 1 0 1.0 null '[]' '{}'; do
    dagedit "$P" "d['phases'][1]['horizon'] = json.loads('$nv')"
    on=$(node "$P/.hb/hb-lint.js" "$P/.hb/dag.json" 2>&1); rn=$?
    op=$(PY lint "$P/.hb/dag.json" --dir "$P" 2>&1); rp=$?
    [ "$rn" = 1 ] && [ "$rp" = 1 ] || fail "n1: horizon=$nv must be a lint ERROR on both (node=$rn py=$rp): $on / $op"
    on=$(echo "$on" | grep 'horizon must be true or false'); op=$(echo "$op" | grep 'horizon must be true or false')
    [ -n "$on" ] && [ "$on" = "$op" ] || fail "n1: horizon=$nv lint message bytes differ or are missing:
node: $on
py:   $op"
    echo "$on" | grep -q '\[H2\]' || fail "n1: the lint message does not name the phase: $on"
  done
  for v in True False; do
    P="$W/n2-$v"; mkh "$P"
    dagedit "$P" "d['phases'][0]['horizon'] = $v; d['phases'][1]['horizon'] = $v"   # true on a NON-final phase: inert
    node "$P/.hb/hb-lint.js" "$P/.hb/dag.json" >/dev/null 2>&1 || fail "n2: node lint rejected horizon=$v"
    PY lint "$P/.hb/dag.json" --dir "$P" >/dev/null 2>&1 || fail "n2: python lint rejected horizon=$v"
  done
  # n4: the shipped dag schema declares the marker (phases are additionalProperties:false — a schema
  # that omits it would reject every horizon plan the skill tells planners to write)
  python3 - "$ROOT/plugin/dag.schema.json" <<'PYEOF' || fail "n4: plugin/dag.schema.json does not declare a boolean phase 'horizon'"
import json, sys
ph = json.load(open(sys.argv[1]))["properties"]["phases"]["items"]
assert ph["properties"]["horizon"]["type"] == "boolean"
PYEOF
  # n3: the marker is a STRICT boolean on every runtime surface, not only the lint: a truthy
  # non-true value on the reached last phase is NO horizon — both resolvers all_done, no replan
  # wake from either tick, no horizon line in either report, and both closes refuse with no event
  local v rt o
  for v in 1 '"true"' '"yes"' '[true]' '{"on": true}'; do
    P="$W/n3-$(echo "$v" | tr -dc 'a-z0-9')"; mkh "$P"; reach "$P"
    dagedit "$P" "d['phases'][1]['horizon'] = json.loads('$v')"
    assert_res "$P" all_done "" "n3(horizon=$v)"
    for rt in node py; do
      [ "$(tk "$P" "$rt" | field data.reason)" = replan_pending ] && fail "n3 ($rt): horizon=$v woke replan_pending"
      [ -f "$P/.hb/.replan-alerted" ] && fail "n3 ($rt): horizon=$v wrote the replan flag"
      rep "$P" "$rt" | grep -q '^Horizon' && fail "n3 ($rt): horizon=$v printed a horizon line"
      refused "$P" "$rt" "n3(close on horizon=$v)" close --reason "x"
    done
  done
  echo "LINT-OK"
}

# ── case: audit — speculative_tail names the cut point ───────────────────────────────────────
mkaudit(){   # $1=file $2=shape — phases PA (gated head), PB, PC, per shape
  python3 - "$1" "$2" <<'EOF'
import json, sys
f, shape = sys.argv[1], sys.argv[2]
B = lambda i: {"id": i, "desc": "behavioral", "cmd": "python3 -c \"assert 1+1==2\""}
def ph(pid, gate, tasks=True, **kw):
    p = {"id": pid, "title": pid, "gate_entry": None, "gate_exit": gate,
         "tasks": [{"id": pid.lower() + "1", "title": "t", "requires": [], "description": "d"}] if tasks else []}
    p.update(kw); return p
gates = {"G_A": {"desc": "a", "criteria": [B("a1")]}}
if shape == "t1":     # gated head; PB unguarded (no gate); PC hollow (existence only)
    phases = [ph("PA", "G_A"), ph("PB", None), ph("PC", "G_C")]
    gates["G_C"] = {"desc": "c", "criteria": [{"id": "c1", "desc": "e", "cmd": "test -f out.txt"}]}
elif shape == "t2":   # fully gated
    phases = [ph("PA", "G_A"), ph("PB", "G_B"), ph("PC", "G_C")]
    gates["G_B"] = {"desc": "b", "criteria": [B("b1")]}; gates["G_C"] = {"desc": "c", "criteria": [B("c1")]}
elif shape == "t3":   # a single unverified final phase
    phases = [ph("PA", "G_A"), ph("PB", "G_B"), ph("PC", None)]
    gates["G_B"] = {"desc": "b", "criteria": [B("b1")]}
elif shape == "t4":   # no gated head at all
    phases = [ph("PB", None), ph("PC", "G_C")]
    gates = {"G_C": {"desc": "c", "criteria": []}}
elif shape == "t5":   # the unverified tail is parked
    phases = [ph("PA", "G_A"), ph("PB", None, parked=True), ph("PC", None, parked=True)]
elif shape == "t6":   # placeholder tail: zero tasks, zero gate
    phases = [ph("PA", "G_A"), ph("PB", None, tasks=False), ph("PC", None, tasks=False)]
json.dump({"project": "audit-" + shape, "phases": phases, "gates": gates}, open(f, "w"), indent=2)
EOF
}
case_audit(){
  local D="$W/aud" s on op rn rp
  mkdir -p "$D"; mkh "$W/aud-proj"
  for s in t1 t6; do
    mkaudit "$D/$s.json" "$s"
    on=$(node "$ROOT/plugin/templates/hb-audit.js" "$D/$s.json" 2>&1); rn=$?
    op=$(PY audit "$D/$s.json" --dir "$W/aud-proj" 2>&1); rp=$?
    [ "$rn" = "$rp" ] || fail "$s: audit exits differ (node=$rn py=$rp)"
    on=$(echo "$on" | grep 'speculative_tail'); op=$(echo "$op" | grep 'speculative_tail')
    [ "$(echo "$on" | grep -c .)" = 1 ] || fail "$s: node speculative_tail must fire EXACTLY once: '$on'"
    [ -n "$on" ] && [ "$on" = "$op" ] || fail "$s: speculative_tail bytes differ or are missing:
node: $on
py:   $op"
    echo "$on" | grep -q '⚠' || fail "$s: speculative_tail is not warn severity: $on"
    echo "$on" | grep -q 'PB' && echo "$on" | grep -q 'PC' || fail "$s: the finding does not name the tail ids: $on"
    echo "$on" | grep -q 'PA' || fail "$s: the finding does not name the cut phase: $on"
    echo "$on" | grep -q 'horizon' && echo "$on" | grep -q 'plan-to-the-horizon.md' || fail "$s: the finding does not name the horizon cure: $on"
  done
  # t7: hostile gate shapes (lint errors, never audit crashes) read identically on both runtimes —
  # a string/object criteria, a string/array gate value, every non-string gate_exit, a non-object
  # gates map — compared as FULL finding objects (severity, phase, extras), not just rule+message
  local h hn hp
  for h in crit-str crit-obj gate-str gate-arr exit-num exit-zero exit-true exit-empty exit-list exit-obj exit-null gates-arr; do
    mkaudit "$D/$h.json" t1
    python3 - "$D/$h.json" "$h" <<'PYEOF'
import json, sys
f, h = sys.argv[1], sys.argv[2]; d = json.load(open(f))
if h == "crit-str": d["gates"]["G_C"]["criteria"] = "test -f out.txt"
if h == "crit-obj": d["gates"]["G_C"]["criteria"] = {"id": "c1", "cmd": "python3 -c 1"}
if h == "gate-str": d["gates"]["G_C"] = "python3 -c 1"
if h == "gate-arr": d["gates"]["G_C"] = [{"id": "c1", "cmd": "python3 -c 1"}]
if h == "exit-num": d["phases"][2]["gate_exit"] = 5
if h == "exit-zero": d["phases"][2]["gate_exit"] = 0
if h == "exit-true": d["phases"][2]["gate_exit"] = True
if h == "exit-empty": d["phases"][2]["gate_exit"] = ""
if h == "exit-list": d["phases"][2]["gate_exit"] = ["G_C"]
if h == "exit-obj": d["phases"][2]["gate_exit"] = {"g": "G_C"}
if h == "exit-null": d["phases"][2]["gate_exit"] = None
if h == "gates-arr": d["gates"] = [d["gates"]["G_A"]]
json.dump(d, open(f, "w"))
PYEOF
    hn=$(node "$ROOT/plugin/templates/hb-audit.js" "$D/$h.json" --json 2>&1); rn=$?
    hp=$(PY audit "$D/$h.json" --json --dir "$W/aud-proj" 2>&1); rp=$?
    printf '%s\n%s\n' "$hn" "$hp" | grep -qE 'Traceback|TypeError|AttributeError' && fail "t7($h): an audit CRASHED on a hostile gate shape: $hn / $hp"
    [ "$rn" = "$rp" ] || fail "t7($h): audit exits differ (node=$rn py=$rp)"
    hn=$(echo "$hn" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(json.dumps([d["errors"],d["warns"],sorted(json.dumps(f,sort_keys=True) for f in d["findings"])]))')
    hp=$(echo "$hp" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(json.dumps([d["errors"],d["warns"],sorted(json.dumps(f,sort_keys=True) for f in d["findings"])]))')
    [ "$hn" = "$hp" ] || fail "t7($h): findings differ across runtimes:
node: $hn
py:   $hp"
  done
  for s in t2 t3 t4 t5; do
    mkaudit "$D/$s.json" "$s"
    node "$ROOT/plugin/templates/hb-audit.js" "$D/$s.json" 2>&1 | grep -q speculative_tail && fail "$s: node speculative_tail fired on a shape it must stay quiet on"
    PY audit "$D/$s.json" --dir "$W/aud-proj" 2>&1 | grep -q speculative_tail && fail "$s: python speculative_tail fired on a shape it must stay quiet on"
  done
  echo "AUDIT-OK"
}

# ── case: report — the horizon line ──────────────────────────────────────────────────────────
case_report(){
  local P rt l
  for rt in node py; do
    P="$W/r1-$rt"; mkh "$P"
    l=$(rep "$P" "$rt" | grep -i 'horizon')
    echo "$l" | grep -q 'H2' && echo "$l" | grep -qi 'planned' || fail "r1 ($rt): no planned horizon line: '$l'"
    reach "$P"
    l=$(rep "$P" "$rt" | grep -i 'horizon')
    echo "$l" | grep -q 'REACHED' && echo "$l" | grep -qi 'append' && echo "$l" | grep -q 'horizon close' || fail "r2 ($rt): the REACHED line does not name both moves: '$l'"
    CLOSER=frank accepted "$P" "$rt" "r3(close)" close --reason "shipped and learned"
    l=$(rep "$P" "$rt" | grep -i 'horizon')
    echo "$l" | grep -q 'closed by frank' && echo "$l" | grep -q 'shipped and learned' || fail "r3 ($rt): no closed-by line with actor and reason: '$l'"
    # the closed-by line is PHASE-scoped: a newer flagged horizon appended after the close is planned
    addphase "$P" H3 GATE_H2 GATE_H3 h3a flag
    l=$(rep "$P" "$rt" | grep '^Horizon')
    echo "$l" | grep -q 'H3' && echo "$l" | grep -qi 'planned' && ! echo "$l" | grep -q 'closed' || fail "r3 ($rt): the old close leaked onto the new horizon H3: '$l'"
    P="$W/r4-$rt"; mkh "$P" noflag; reach "$P"
    rep "$P" "$rt" | grep -qi 'horizon' && fail "r4 ($rt): an unmarked project printed a horizon line"
  done
  echo "REPORT-OK"
}

# ── selftest: mutation teeth ──────────────────────────────────────────────────────────────────
mutate(){ local b; b=$(grep -c "$2" "$1" 2>/dev/null || true); [ "${b:-0}" -gt 0 ] || fail "selftest: no '$2' marker in $1"; sed -i "/$2/d" "$1"; }
mutate_tree(){ local hits; hits=$(grep -rl "$2" "$1" --include='*.py' || true); [ -n "$hits" ] || fail "selftest: no '$2' marker under $1"; echo "$hits" | xargs sed -i "/$2/d"; }
mkpycopy(){ cp -r "$ROOT/py/src" "$1"; }
selftest(){
  local P o r t
  # s1: node resolver guard stripped → the reached horizon no longer verdicts replan_pending
  P="$W/s1"; mkh "$P"; reach "$P"
  mutate "$P/.hb/hb-next-task.js" "horizon-guard: resolver"
  node --check "$P/.hb/hb-next-task.js" 2>/dev/null || fail "selftest s1: stripped resolver no longer parses"
  t=$(res "$P" node | field type); [ "$t" = replan_pending ] && fail "selftest s1: replan_pending survived the node resolver strip"
  [ "$t" = all_done ] || fail "selftest s1: the stripped resolver broke instead of falling back to all_done: $t"
  # s2: py resolver guard stripped
  P="$W/s2"; mkh "$P"; reach "$P"
  mkpycopy "$W/py-s2"; mutate_tree "$W/py-s2" "horizon-guard: resolver"
  python3 -c "import sys; sys.path.insert(0, '$W/py-s2'); import heartbeat.resolver" || fail "selftest s2: stripped resolver.py no longer imports"
  t=$(HB_PY_SRC="$W/py-s2" PY next --dir "$P" | field type); [ "$t" = replan_pending ] && fail "selftest s2: replan_pending survived the py resolver strip"
  # s3: tick.sh guard stripped → the wake reason is no longer replan_pending
  P="$W/s3"; mkh "$P"; reach "$P"
  mutate "$P/.hb/tick.sh" "horizon-guard: tick"
  bash -n "$P/.hb/tick.sh" 2>/dev/null || fail "selftest s3: stripped tick.sh no longer parses"
  [ "$(tk "$P" node | field data.reason)" = replan_pending ] && fail "selftest s3: the replan wake survived the tick.sh strip"
  # s4: tick.py guard stripped
  P="$W/s4"; mkh "$P"; reach "$P"
  mkpycopy "$W/py-s4"; mutate_tree "$W/py-s4" "horizon-guard: tick"
  python3 -c "import sys; sys.path.insert(0, '$W/py-s4'); import heartbeat.tick" || fail "selftest s4: stripped tick.py no longer imports"
  [ "$(HB_PY_SRC="$W/py-s4" PY tick --dir "$P" 2>/dev/null | field data.reason)" = replan_pending ] && fail "selftest s4: the replan wake survived the tick.py strip"
  # s5: ALL node close guards stripped → an early close AND a mid-regate close are ACCEPTED
  P="$W/s5"; mkh "$P"; dotask "$P" h1a; pass "$P" GATE_H1
  mutate "$P/.hb/hb.js" "horizon-guard: close"
  node --check "$P/.hb/hb.js" 2>/dev/null || fail "selftest s5: stripped hb.js no longer parses"
  o=$( cd "$P" && node .hb/hb.js horizon close --reason early 2>&1 ) || fail "selftest s5: the stripped node close still refused an EARLY close (c1 has no teeth): $o"
  P="$W/s5b"; mkh "$P"; reach "$P"; declare_rg "$P" GATE_H2
  mutate "$P/.hb/hb.js" "horizon-guard: close"
  o=$( cd "$P" && node .hb/hb.js horizon close --reason mid 2>&1 ) || fail "selftest s5: the stripped node close still refused a MID-REGATE close (c6 has no teeth): $o"
  # s6: ALL py close guards stripped → same
  mkpycopy "$W/py-s6"; mutate_tree "$W/py-s6" "horizon-guard: close"
  python3 -c "import sys; sys.path.insert(0, '$W/py-s6'); import heartbeat.cli" || fail "selftest s6: stripped py close no longer imports"
  P="$W/s6"; mkh "$P"; dotask "$P" h1a; pass "$P" GATE_H1
  o=$( HB_PY_SRC="$W/py-s6" PY horizon close --reason early --dir "$P" 2>&1 ) || fail "selftest s6: the stripped py close still refused an EARLY close: $o"
  P="$W/s6b"; mkh "$P"; reach "$P"; declare_rg "$P" GATE_H2
  o=$( HB_PY_SRC="$W/py-s6" PY horizon close --reason mid --dir "$P" 2>&1 ) || fail "selftest s6: the stripped py close still refused a MID-REGATE close: $o"
  # s7: the speculative_tail block stripped from a node audit COPY → t1 goes quiet
  mkdir -p "$W/s7"; cp "$ROOT/plugin/templates/hb-audit.js" "$ROOT/plugin/templates/hb-lint.js" "$W/s7/"
  mutate "$W/s7/hb-audit.js" "horizon-guard: audit"
  node --check "$W/s7/hb-audit.js" 2>/dev/null || fail "selftest s7: stripped hb-audit.js no longer parses"
  mkaudit "$W/s7/t1.json" t1
  node "$W/s7/hb-audit.js" "$W/s7/t1.json" 2>&1 | grep -q speculative_tail && fail "selftest s7: speculative_tail survived the node audit strip"
  # s8: the speculative_tail block stripped from a py audit COPY
  mkh "$W/s8-proj"; mkpycopy "$W/py-s8"; mutate_tree "$W/py-s8" "horizon-guard: audit"
  python3 -c "import sys; sys.path.insert(0, '$W/py-s8'); import heartbeat.audit" || fail "selftest s8: stripped audit.py no longer imports"
  HB_PY_SRC="$W/py-s8" PY audit "$W/s7/t1.json" --dir "$W/s8-proj" 2>&1 | grep -q speculative_tail && fail "selftest s8: speculative_tail survived the py audit strip"
  echo "HORIZON-SELFTEST-OK"
}

# ── dispatch ──────────────────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--selftest" ]; then selftest; exit 0; fi
sel="${1:-all}"
for c in marker close append flags limits parked lint audit report; do
  if [ "$sel" = all ] || [ "$sel" = "$c" ]; then "case_$c" || exit 1; fi
done
[ "$sel" = all ] && echo "HORIZON-OK"
exit 0
