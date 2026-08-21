#!/usr/bin/env bash
# Parity proof: a node-bootstrapped project (bootstrap.sh) AND a python-init project (hb init) each
# install a pre-push hook that BLOCKS iff gate re-verification fails — BEHAVIORAL parity (the hook body
# is runtime-specific: node calls `gate.sh --all`, python calls `hb gate --all`, so assert behavior, not
# bytes). For each runtime: the hook's exit matches the real gate-reverify's exit (blocks iff gates
# fail), and HB_NO_HOOK=1 bypasses. Prints PRE-PUSH-PARITY-OK. Fails before the installs exist.
set -u
unset HB_NO_GIT HB_NO_HOOK   # the suite exports HB_NO_GIT=1; this proof tests git-hook install in isolated temp repos
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v git     >/dev/null 2>&1 || { echo "git absent";     exit 1; }
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail(){ echo "FAIL: $1"; exit 1; }
run_hook(){ ( cd "$1" && "${@:2}" bash .git/hooks/pre-push origin fake://x </dev/null >/dev/null 2>&1 ); }

# $1 = project dir ; $2.. = the real gate-reverify command (run inside the project)
check_runtime(){
  local p="$1"; shift
  [ -x "$p/.git/hooks/pre-push" ] || fail "$p: pre-push not installed / not executable"
  ( cd "$p" && "$@" >/dev/null 2>&1 ); local ge=$?
  run_hook "$p"; local he=$?
  if [ "$ge" -eq 0 ]; then
    [ "$he" -eq 0 ] || fail "$p: gate re-verify passes (ge=0) but the hook blocked (he=$he)"
  else
    [ "$he" -ne 0 ] || fail "$p: gate re-verify fails (ge=$ge) but the hook allowed the push (he=0)"
  fi
  run_hook "$p" env HB_NO_HOOK=1 || fail "$p: HB_NO_HOOK=1 did not bypass the hook"
}

# node runtime
pn="$tmp/node"; mkdir -p "$pn"
bash "$ROOT/plugin/bootstrap.sh" "$pn" >/dev/null 2>&1 || fail "node bootstrap failed"
check_runtime "$pn" bash .hb/gate.sh --all

# python runtime (its `true` seed gate PASSES → check_runtime exercises the ALLOW direction)
pp="$tmp/py"
PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli init "$pp" >/dev/null 2>&1 || fail "python init failed"
check_runtime "$pp" env PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli gate --all --dir "$pp"

# python BLOCK teeth: force a failing gate (the seed passes), then the hook MUST block — so a hollow
# python hook (always exit 0) fails here, not just the node side.
python3 - "$pp" <<'PY'
import json, sys
p = sys.argv[1] + "/.hb/dag.json"
d = json.load(open(p))
next(iter(d["gates"].values()))["criteria"][0]["cmd"] = "false"
json.dump(d, open(p, "w"))
PY
( cd "$pp" && env PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli gate --all --dir "$pp" >/dev/null 2>&1 ) \
  && fail "python: forced-fail gate still passed gate --all"
run_hook "$pp" && fail "python: hook allowed the push despite a failing gate"

echo "PRE-PUSH-PARITY-OK"
