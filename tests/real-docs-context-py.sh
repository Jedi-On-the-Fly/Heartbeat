#!/usr/bin/env bash
# ON-DEMAND / harness-first — NOT gated. The node-free framework path end-to-end: the PYTHON docs
# context provider feeds a real ollama model via the generic context hook, no Node involved. Needs
# ollama + a model; skips cleanly otherwise. (The mechanism is gated deterministically by
# adapters-nodefree.sh + T89/T95; this shows a real model consuming it with zero Node.)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="${HB_EXEC_MODEL:-llama3.2:3b}"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 absent"; exit 0; }
curl -s --max-time 2 "${OLLAMA_HOST:-http://127.0.0.1:11434}/api/tags" >/dev/null 2>&1 \
  || { echo "SKIP: ollama not reachable"; exit 0; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/p/.hb"
printf '{"phases":[{"id":"P0","gate_exit":"G0","tasks":[{"id":"P0T1","title":"write results"}]}],"gates":{"G0":{"criteria":[]}}}' > "$tmp/p/.hb/dag.json"
printf '{"completed_phases":[],"completed_tasks":[]}' > "$tmp/p/.hb/state.json"
FXD="$ROOT/plugin/adapters/docs/fixtures"
CTX="python3 -m heartbeat.adapters.docs.docs_context $FXD/corpus $FXD/docs.codemap.json results"

# (1) deterministic: the python context_cmd injects the cited text (no node)
ctx="$(HB_EXEC_CONTEXT_CMD="$CTX" PYTHONPATH="$ROOT/py/src" python3 -c "
from heartbeat import executor
print(executor.assemble_context('$tmp/p/.hb', {'id':'P0T1','phase':'P0','title':'write results'}))")"
echo "$ctx" | grep -q 'Our approach, building on' || { echo "FAIL: python context provider did not inject the cited text"; exit 1; }

# (2) real: drive one task against the ollama model with the PYTHON context provider (node-free)
out="$(HB_EXEC_BACKEND=ollama HB_EXEC_MODEL="$MODEL" HB_EXEC_CONTEXT_CMD="$CTX" HB_EXEC_MAX_ITERS=1 HB_NO_GIT=1 \
  PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli exec run --dir "$tmp/p" 2>&1)" || true
echo "$out" | grep -qiE 'HB-EXEC|done|task' || { echo "FAIL: ollama run produced no driver output"; echo "$out" | tail -3; exit 1; }

echo "REAL-DOCS-CONTEXT-PY-OK ($MODEL): a Python (node-free) context provider fed a real model."
