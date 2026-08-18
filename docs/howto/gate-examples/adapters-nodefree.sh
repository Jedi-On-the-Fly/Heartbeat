#!/usr/bin/env bash
# Proves the adapter capability is available with PROVABLY zero Node — the framework/Python path.
# node often shares a dir with python3 (both /usr/bin), so filtering node's dir out of $PATH would
# also drop python3; instead build a synthetic bindir with ONLY python3/bash (no node), assert node
# is unreachable there (else the claim is vacuous), then run the Python adapters + a python
# context_cmd — all node-free. Fails before the Python adapters exist (spec-first).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bin="$tmp/nonode"; mkdir -p "$bin"
for t in python3 bash sh env; do p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$bin/$t"; done   # node deliberately NOT linked

run(){ env -i PATH="$bin" PYTHONPATH="$ROOT/py/src" HOME="$HOME" "$@"; }

# (0) node must be UNREACHABLE — otherwise the whole "node-free" proof is vacuous
if run bash -c 'command -v node' >/dev/null 2>&1; then
  echo "FAIL: node still reachable in the stripped env — the node-free proof would be vacuous"; exit 1
fi

FXC="$ROOT/plugin/adapters/code/fixtures"; FXD="$ROOT/plugin/adapters/docs/fixtures"
# (1) the Python adapters produce their output with NO node on PATH
run python3 -m heartbeat.adapters.docs.docs_map "$FXD/corpus" | grep -q '"edges"' \
  || { echo "FAIL: docs_map did not run node-free"; exit 1; }
run python3 -m heartbeat.adapters.docs.docs_context "$FXD/corpus" "$FXD/docs.codemap.json" intro | grep -q 'Our approach, building on' \
  || { echo "FAIL: docs_context did not run node-free"; exit 1; }
run python3 -m heartbeat.adapters.code.deplint "$FXC/missing.dag.json" "$FXC/missing.codemap.json" | grep -q 'MISSING: TA should require TB' \
  || { echo "FAIL: deplint did not run node-free"; exit 1; }

# (2) a python context_cmd feeds the executor with NO node — assemble_context injects the cited text
mkdir -p "$tmp/proj/.hb"
printf '{"phases":[{"id":"P0","gate_exit":"G0","tasks":[{"id":"P0T1","title":"t"}]}],"gates":{"G0":{"criteria":[]}}}' > "$tmp/proj/.hb/dag.json"
printf '{"completed_phases":[],"completed_tasks":[]}' > "$tmp/proj/.hb/state.json"
ctx="$(run env HB_EXEC_CONTEXT_CMD="python3 -m heartbeat.adapters.docs.docs_context $FXD/corpus $FXD/docs.codemap.json results" \
  python3 -c "from heartbeat import executor; print(executor.assemble_context('$tmp/proj/.hb', {'id':'P0T1','phase':'P0','title':'t'}))")"
echo "$ctx" | grep -q '<<HB-CONTEXT>>'          || { echo "FAIL: no injected context block (node-free)"; exit 1; }
echo "$ctx" | grep -q 'Our approach, building on' || { echo "FAIL: python context_cmd did not inject the cited text"; exit 1; }

echo "ADAPTERS-NODEFREE-OK"
