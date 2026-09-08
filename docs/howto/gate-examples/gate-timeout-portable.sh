#!/usr/bin/env bash
# Proof (bug follow-up to bootstrap-noninteractive-hang: gate.sh unbounded without timeout(1)): the gate
# runner must bound EVERY criterion even when neither `timeout` nor `gtimeout` is installed — stock macOS
# ships no coreutils, so both are absent, and there the old runner ran criteria UNBOUNDED (a hanging
# criterion hangs the tick/suite instead of blocking the gate). Under a curated PATH with both binaries
# absent, a criterion that sleeps past GATE_TIMEOUT_S must be KILLED → gate blocks (✗), returning fast;
# a quick criterion still passes. This matches the python runner (always bounded via subprocess timeout).
# Portable: carries its own run_bounded (no timeout(1)). Prints GATE-TIMEOUT-PORTABLE-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GATESH="$ROOT/plugin/templates/gate.sh"
BASH_ABS="$(command -v bash)"

# run_bounded <secs> <cmd...> → the cmd's exit, or 124 if it had to be killed past the bound.
run_bounded() {
  local secs="$1"; shift
  "$@" & local p=$!
  local i=0 n=$(( secs * 10 ))
  while kill -0 "$p" 2>/dev/null; do
    i=$((i + 1)); if [ "$i" -ge "$n" ]; then kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null; return 124; fi
    sleep 0.1
  done
  wait "$p"
}

# a PATH dir with what gate.sh needs (bash, node, sleep) but deliberately WITHOUT timeout/gtimeout.
make_no_timeout_path() {
  local bd; bd="$(mktemp -d)"
  for t in bash node sleep dirname date; do ln -s "$(command -v "$t")" "$bd/$t"; done
  echo "$bd"
}

setup_project() {  # → a .hb dir carrying gate.sh + a dag with a hanging gate and a fast gate
  local hb; hb="$(mktemp -d)/.hb"; mkdir -p "$hb"
  cp "$GATESH" "$hb/gate.sh"
  cat > "$hb/dag.json" <<'JSON'
{ "phases": [], "gates": {
  "GHANG": { "desc": "hangs", "criteria": [ { "id": "h", "desc": "sleeps past the bound", "cmd": "sleep 30" } ] },
  "GFAST": { "desc": "fast",  "criteria": [ { "id": "f", "desc": "returns immediately", "cmd": "true" } ] }
} }
JSON
  echo "$hb"
}

run_gate() {  # <bindir> <hb> <gate> → gate.sh --check exit code, itself outer-bounded so a real hang shows as 124
  local bd="$1" hb="$2" g="$3"
  ( export PATH="$bd" GATE_TIMEOUT_S=1 HB_NO_GIT=1
    run_bounded 8 "$BASH_ABS" "$hb/gate.sh" --check "$g" )
}

check_all() {
  local bd hb rc bad=""
  bd="$(make_no_timeout_path)"; hb="$(setup_project)"
  # exercising the RIGHT branch: the curated PATH must truly lack timeout/gtimeout yet keep the essentials
  PATH="$bd" command -v timeout  >/dev/null 2>&1 && bad="$bad; timeout-leaked-into-PATH"
  PATH="$bd" command -v gtimeout >/dev/null 2>&1 && bad="$bad; gtimeout-leaked-into-PATH"
  for t in bash node sleep dirname date; do PATH="$bd" command -v "$t" >/dev/null 2>&1 || bad="$bad; curated-PATH-missing-$t"; done

  # GHANG: sleep 30 under GATE_TIMEOUT_S=1 and no timeout binary must be KILLED → gate blocks (rc 1), fast.
  #   rc 1   = correct (bounded → criterion killed → blocked)
  #   rc 124 = ran UNBOUNDED, outer harness had to kill it (the bug)
  #   rc 0   = criterion "passed" (sleep completed unbounded — also the bug)
  run_gate "$bd" "$hb" GHANG; rc=$?
  case "$rc" in
    1)   ;;
    124) bad="$bad; GHANG-ran-UNBOUNDED(outer-kill)";;
    0)   bad="$bad; GHANG-passed(criterion-not-bounded)";;
    *)   bad="$bad; GHANG-unexpected-rc=$rc";;
  esac

  # GFAST: a quick criterion still passes under the same no-binary bound (the bound must not false-kill).
  run_gate "$bd" "$hb" GFAST; rc=$?
  [ "$rc" -eq 0 ] || bad="$bad; GFAST-rc=$rc(false-killed?)"

  [ -z "$bad" ] || { echo "FAIL:$bad"; return 1; }
  return 0
}

if [ "${1:-}" = "--selftest" ]; then
  bad=""
  run_bounded 1 sleep 30; [ $? -eq 124 ] || bad="$bad; run_bounded-missed-a-hang"
  run_bounded 3 true;     [ $? -eq 0   ] || bad="$bad; run_bounded-false-killed-a-quick-cmd"
  bd="$(make_no_timeout_path)"
  PATH="$bd" command -v timeout  >/dev/null 2>&1 && bad="$bad; timeout-in-curated-PATH"
  PATH="$bd" command -v gtimeout >/dev/null 2>&1 && bad="$bad; gtimeout-in-curated-PATH"
  for t in bash node sleep dirname date; do PATH="$bd" command -v "$t" >/dev/null 2>&1 || bad="$bad; curated-PATH-missing-$t"; done
  [ -z "$bad" ] || { echo "SELFTEST-FAIL:$bad"; exit 1; }
  echo "SELFTEST-OK: run_bounded flags a hang AND clears a quick cmd; curated PATH excludes timeout/gtimeout, keeps bash/node/sleep"
  exit 0
fi

check_all || exit 1
echo "GATE-TIMEOUT-PORTABLE-OK"
