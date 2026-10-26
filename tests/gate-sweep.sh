#!/usr/bin/env bash
# gate-sweep.sh — gate-time-only criteria (T187).
#
# A criterion may carry "sweep": false: it is checked when its gate passes (and by an explicit
# `gate.sh --check <G>` / `hb gate <G> --check`), but the regression sweep (`gate.sh --all` /
# `hb gate --all`, the pre-push guard) does NOT re-run it. The case it exists for: a criterion that
# runs the WHOLE test suite proves "this phase broke nothing" at gate time; re-running it once per
# gate in every sweep is the same suite run N times, and CI runs it on every push anyway.
# The sweep is never silent about it: each skipped criterion is listed, the verdict counts them,
# and a gate left with NOTHING to re-verify is named. Lint type-checks the field (a boolean, on
# both runtimes, identical bytes). Like desc and timeout_s, the field is NOT pinned by the drift
# tripwire (only a criterion's (id, cmd) is), so marking an accepted criterion sweep:false is quiet.
#
#   bash tests/gate-sweep.sh            → GATE-SWEEP-OK
#   bash tests/gate-sweep.sh --selftest → GATE-SWEEP-SELFTEST-OK
set -u
unset HB_DIR PROJECT_DIR GATE G DAG_FILE EVENTS_FILE 2>/dev/null || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export HB_NO_GIT=1 STUCK_TICKS=999
fail(){ echo "FAIL: $1"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
PY(){ PYTHONPATH="${HB_PY_SRC:-$ROOT/py/src}" python3 -m heartbeat.cli "$@"; }

# G1: a fast check + a gate-time-only check that leaves a mark each time it runs.
# G2: ONLY gate-time-only checks (nothing left for the sweep).
mkp(){   # $1 = dir
  mkdir -p "$1"; ( cd "$1" && bash "$ROOT/plugin/bootstrap.sh" . >/dev/null 2>&1 )
  python3 - "$1/.hb/dag.json" <<'EOF'
import json, sys
mark = lambda f: 'python3 -c "import sys; open(sys.argv[1],\'a\').write(\'x\')" "$PROJECT_DIR/%s"' % f
d = {"project": "sweep",
     "phases": [{"id": "P1", "title": "one", "gate_entry": None, "gate_exit": "G1", "tasks": [{"id": "t1", "title": "t", "requires": [], "description": "d"}]},
                {"id": "P2", "title": "two", "gate_entry": "G1", "gate_exit": "G2", "tasks": [{"id": "t2", "title": "t", "requires": [], "description": "d"}]}],
     "gates": {"G1": {"desc": "g1", "criteria": [{"id": "fast", "desc": "quick", "cmd": "python3 -c \"assert 1+1==2\""},
                                                 {"id": "suite", "desc": "the whole suite", "cmd": mark("g1.ran"), "sweep": False}]},
               "G2": {"desc": "g2", "criteria": [{"id": "only", "desc": "gate-time only", "cmd": mark("g2.ran"), "sweep": False}]}}}
json.dump(d, open(sys.argv[1], "w"), indent=2)
EOF
  ( cd "$1" && for t in t1 t2; do HB_ACTOR=doer node .hb/hb.js start $t >/dev/null && HB_ACTOR=doer node .hb/hb.js done $t >/dev/null; done )
}
marks(){ cat "$1/$2" 2>/dev/null | wc -c | tr -d ' '; }

case_sweep(){
  local rt P o r m1 m2
  for rt in node py; do
    P="$W/$rt"; mkp "$P"
    # (s1) at gate time EVERY criterion runs — gate-time-only included
    if [ "$rt" = node ]; then ( cd "$P" && bash .hb/gate.sh G1 >/dev/null 2>&1 && bash .hb/gate.sh G2 >/dev/null 2>&1 ) || fail "s1 ($rt): the gates did not pass"
    else PY gate G1 --dir "$P" >/dev/null 2>&1 && PY gate G2 --dir "$P" >/dev/null 2>&1 || fail "s1 ($rt): the gates did not pass"; fi
    [ "$(marks "$P" g1.ran)" = 1 ] && [ "$(marks "$P" g2.ran)" = 1 ] || fail "s1 ($rt): a gate-time-only criterion did not run at gate time"
    # (s2) the sweep does NOT re-run it, lists it, counts it, and names the gate with nothing left
    if [ "$rt" = node ]; then o=$( cd "$P" && bash .hb/gate.sh --all 2>&1 ); r=$?; else o=$(PY gate --all --dir "$P" 2>&1); r=$?; fi
    [ "$r" = 0 ] || fail "s2 ($rt): the sweep failed (exit $r): $o"
    [ "$(marks "$P" g1.ran)" = 1 ] && [ "$(marks "$P" g2.ran)" = 1 ] || fail "s2 ($rt): the sweep RE-RAN a gate-time-only criterion"
    [ "$rt" = py ] || echo "$o" | grep -q '✓ \[fast\]' || fail "s2 ($rt): the sweep did not re-run the ordinary criterion: $o"
    echo "$o" | grep -q '○ \[suite\].*gate-time only' && echo "$o" | grep -q '○ \[only\].*gate-time only' || fail "s2 ($rt): the sweep did not list each skipped criterion: $o"
    echo "$o" | grep -q '2 gate-time-only skipped' || fail "s2 ($rt): the verdict does not count the skipped criteria: $o"
    echo "$o" | grep -q 'G2 has no sweepable criteria' || fail "s2 ($rt): a gate with nothing left to re-verify was not named: $o"
    # (s3) an explicit --check still runs it
    if [ "$rt" = node ]; then ( cd "$P" && bash .hb/gate.sh --check G1 >/dev/null 2>&1 ) || fail "s3 ($rt): --check G1 failed"
    else PY gate G1 --check --dir "$P" >/dev/null 2>&1 || fail "s3 ($rt): --check G1 failed"; fi
    [ "$(marks "$P" g1.ran)" = 2 ] || fail "s3 ($rt): --check did not run the gate-time-only criterion"
  done
  # (s4) lint: a non-boolean sweep is an ERROR, identical bytes on both runtimes; true/false are clean
  local v on op rn rp
  for v in '"no"' 0 null; do
    python3 - "$W/node/.hb/dag.json" "$W/l.json" "$v" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d["gates"]["G1"]["criteria"][1]["sweep"] = json.loads(sys.argv[3]); json.dump(d, open(sys.argv[2], "w"))
EOF
    on=$(node "$ROOT/plugin/templates/hb-lint.js" "$W/l.json" --json 2>&1); rn=$?
    op=$(PY lint "$W/l.json" --json 2>&1); rp=$?
    [ "$rn" = 1 ] && [ "$rp" = 1 ] || fail "s4: sweep=$v must be a lint ERROR on both (node=$rn py=$rp)"
    [ "$(echo "$on" | python3 -c 'import json,sys; print(json.load(sys.stdin)["errors"])')" = "$(echo "$op" | python3 -c 'import json,sys; print(json.load(sys.stdin)["errors"])')" ] || fail "s4: sweep=$v error bytes differ: $on / $op"
    echo "$on" | grep -q 'sweep must be true or false' || fail "s4: the message does not name the field: $on"
  done
  node "$ROOT/plugin/templates/hb-lint.js" "$W/node/.hb/dag.json" >/dev/null 2>&1 && PY lint "$W/node/.hb/dag.json" >/dev/null 2>&1 || fail "s4: a boolean sweep must lint clean"
  # (s5) marking an ACCEPTED criterion sweep:false is not drift (the field is unpinned, like desc)
  P="$W/drift"; mkp "$P"
  python3 - "$P/.hb/dag.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d["gates"]["G1"]["criteria"][1].pop("sweep"); json.dump(d, open(sys.argv[1], "w"), indent=2)
EOF
  ( cd "$P" && bash .hb/gate.sh G1 >/dev/null 2>&1 ) || fail "s5: G1 did not pass"
  python3 - "$P/.hb/dag.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d["gates"]["G1"]["criteria"][1]["sweep"] = False; json.dump(d, open(sys.argv[1], "w"), indent=2)
EOF
  ( cd "$P" && node .hb/hb.js doctor >/dev/null 2>&1 ) || fail "s5: node doctor reports drift after marking an accepted criterion sweep:false"
  PY doctor --dir "$P" >/dev/null 2>&1 || fail "s5: python doctor reports drift after marking an accepted criterion sweep:false"
  echo "GATE-SWEEP-OK"
}

selftest(){
  local P o
  # st1: the node sweep guard stripped → the sweep re-runs the gate-time-only criterion
  P="$W/st1"; mkp "$P"; ( cd "$P" && bash .hb/gate.sh G1 >/dev/null 2>&1 )
  grep -q 'sweep-guard' "$P/.hb/gate.sh" || fail "selftest: no sweep-guard marker in gate.sh"
  sed -i '/sweep-guard/d' "$P/.hb/gate.sh"; bash -n "$P/.hb/gate.sh" || fail "selftest st1: stripped gate.sh no longer parses"
  ( cd "$P" && bash .hb/gate.sh --all >/dev/null 2>&1 )
  [ "$(marks "$P" g1.ran)" -ge 2 ] || fail "selftest st1: the gate-time-only criterion stayed skipped with the guard stripped (marker not load-bearing)"
  # st2: the python sweep guard stripped from a runtime COPY → same
  cp -r "$ROOT/py/src" "$W/py2"; grep -rl 'sweep-guard' "$W/py2" --include='*.py' | xargs -r sed -i '/sweep-guard/d'
  python3 -c "import sys; sys.path.insert(0, '$W/py2'); import heartbeat.gate" || fail "selftest st2: stripped gate.py no longer imports"
  P="$W/st2"; mkp "$P"; PY gate G1 --dir "$P" >/dev/null 2>&1
  HB_PY_SRC="$W/py2" PY gate --all --dir "$P" >/dev/null 2>&1
  [ "$(marks "$P" g1.ran)" -ge 2 ] || fail "selftest st2: the python gate-time-only criterion stayed skipped with the guard stripped"
  echo "GATE-SWEEP-SELFTEST-OK"
}

if [ "${1:-}" = "--selftest" ]; then selftest; else case_sweep; fi
