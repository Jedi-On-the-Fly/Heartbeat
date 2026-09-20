#!/usr/bin/env bash
# Parity of the GATE RUNNER: node gate.sh and python hb gate must reach the same verdict on the
# same criteria. Compares EXIT CODES (0=pass, non-0=block — the reliable cross-runtime signal;
# the human text differs by design) across pass / fail / the zero-criteria hollow floor / timeout.
# Prints GATE-PARITY-OK only when every gate agrees across runtimes.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

HB_NO_GIT=1 bash "$ROOT/plugin/bootstrap.sh" "$tmp/proj" >/dev/null 2>&1 </dev/null
DAG='{"phases":[
  {"id":"P0","gate_entry":null,"gate_exit":"G_PASS","tasks":[{"id":"T0","title":"t","requires":[]}]},
  {"id":"P1","gate_entry":"G_PASS","gate_exit":"G_FAIL","tasks":[{"id":"T1","title":"t","requires":[]}]},
  {"id":"P2","gate_entry":"G_FAIL","gate_exit":"G_HOLLOW","tasks":[{"id":"T2","title":"t","requires":[]}]},
  {"id":"P3","gate_entry":"G_HOLLOW","gate_exit":"G_TIMEOUT","tasks":[{"id":"T3","title":"t","requires":[]}]}],
 "gates":{
  "G_PASS":{"desc":"p","criteria":[{"id":"c","desc":"d","cmd":"true"}]},
  "G_FAIL":{"desc":"f","criteria":[{"id":"c","desc":"d","cmd":"false"}]},
  "G_HOLLOW":{"desc":"h","criteria":[]},
  "G_TIMEOUT":{"desc":"to","criteria":[{"id":"c","desc":"d","cmd":"sleep 2"}]},
  "G_CRIT_WIN":{"desc":"cw","criteria":[{"id":"c","desc":"per-criterion timeout_s beats the env default","timeout_s":5,"cmd":"sleep 2"}]},
  "G_CRIT_BAD":{"desc":"cb","criteria":[{"id":"c","desc":"invalid timeout_s fails LOUD, cmd never absolves it","timeout_s":"abc","cmd":"true"}]},
  "G_SLURP":{"desc":"sl","criteria":[{"id":"s1","desc":"slurps stdin","cmd":"cat >/dev/null"},{"id":"s2","desc":"must still run and fail","cmd":"false"}]}}}'
printf '%s' "$DAG" > "$tmp/proj/.hb/dag.json"
node "$tmp/proj/.hb/hb.js" rebuild >/dev/null 2>&1

verdict() { [ "$1" -eq 0 ] && echo pass || echo block; }

cmp_gate() { # gate
  GATE_TIMEOUT_S=1 HB_NO_GIT=1 bash "$tmp/proj/.hb/gate.sh" "$1" >/dev/null 2>&1; local n=$?
  GATE_TIMEOUT_S=1 HB_NO_GIT=1 PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli gate "$1" --dir "$tmp/proj" >/dev/null 2>&1; local p=$?
  local nn pp; nn=$(verdict "$n"); pp=$(verdict "$p")
  [ "$nn" = "$pp" ] || { echo "FAIL: [$1] node=$nn python=$pp"; exit 1; }
  echo "  ok [$1] both=$nn"
}

cmp_gate G_PASS
cmp_gate G_FAIL
cmp_gate G_HOLLOW
cmp_gate G_TIMEOUT
cmp_gate G_CRIT_WIN   # criterion timeout_s=5 under env GATE_TIMEOUT_S=1: BOTH must pass (criterion wins)
cmp_gate G_CRIT_BAD   # timeout_s "abc": BOTH must block (invalid timeout is a loud runtime failure)
cmp_gate G_SLURP      # a slurping criterion must not eat its successor: BOTH must block on s2
GATE_TIMEOUT_S=1 HB_NO_GIT=1 bash "$tmp/proj/.hb/gate.sh" --check G_SLURP >/dev/null 2>&1 \
  && { echo "FAIL: G_SLURP passed — the slurper ate the failing criterion (stdin leak)"; exit 1; }
# And the direction of G_CRIT_WIN must be PASS (not merely agreeing on block):
GATE_TIMEOUT_S=1 HB_NO_GIT=1 bash "$tmp/proj/.hb/gate.sh" --check G_CRIT_WIN >/dev/null 2>&1 \
  || { echo "FAIL: G_CRIT_WIN blocked — per-criterion timeout_s did not override the env default"; exit 1; }
echo "GATE-PARITY-OK: node ≡ python gate runner (pass / fail / hollow-floor / timeout / criterion-timeout override / invalid-timeout floor / stdin-slurper immunity)."
