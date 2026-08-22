#!/usr/bin/env bash
# Proof (C4): a gate PASS must not crash on a machine with no `git` binary — git is optional. Run a
# passing gate with git shadowed off PATH (keep python/node) and assert it exits cleanly and records the
# pass. Prints GATE-GITLESS-OK. Fails today (FileNotFoundError from a bare git subprocess). Deterministic.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail(){ echo "FAIL: $1"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
p="$tmp/proj"; HB_NO_GIT=1 python3 -m heartbeat.cli init "$p" >/dev/null 2>&1 || fail "init"
python3 - "$p/.hb/dag.json" <<'PY'
import json,sys
json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_G","tasks":[{"id":"T1","title":"t"}]}],
"gates":{"GATE_G":{"desc":"g","criteria":[{"id":"c","desc":"x","cmd":"true"}]}}},open(sys.argv[1],"w"))
PY
# clean bin: python3 + coreutils, NO git
cb="$tmp/bin"; mkdir -p "$cb"; for b in python3 bash cat rm mktemp env dirname sha256sum; do x="$(command -v $b 2>/dev/null)" && ln -sf "$x" "$cb/$b"; done
env PATH="$cb" bash -c 'command -v git' >/dev/null 2>&1 && fail "setup: git leaked into clean PATH"
out="$(env -u HB_NO_GIT PATH="$cb" PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli gate GATE_G --dir "$p" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "gate crashed/failed without git (rc=$rc): $out"
grep -q 'gate_passed' "$p/.hb/events.jsonl" || fail "gate pass not recorded without git"
echo "GATE-GITLESS-OK"
