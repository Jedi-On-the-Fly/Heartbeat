#!/usr/bin/env bash
# ON-DEMAND / harness-first — NOT in the gated suite. Seam 2 end-to-end with a REAL local ollama
# model: the code-context provider feeds a task's subgraph into the model's prompt via the generic
# context hook. Needs ollama + a model; skips cleanly otherwise. Non-deterministic (a real model),
# so it is not gated — the injection MECHANISM is gated deterministically by T88/T89.
#   usage: bash tests/real-context.sh            (HB_EXEC_MODEL overrides the default model)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="${HB_EXEC_MODEL:-llama3.2:3b}"
command -v node    >/dev/null 2>&1 || { echo "SKIP: node absent"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 absent"; exit 0; }
curl -s --max-time 2 "${OLLAMA_HOST:-http://127.0.0.1:11434}/api/tags" >/dev/null 2>&1 \
  || { echo "SKIP: ollama not reachable"; exit 0; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
HB_NO_GIT=1 bash "$ROOT/plugin/bootstrap.sh" "$tmp/p" >/dev/null 2>&1 </dev/null
HB="$tmp/p/.hb"

# a codemap mapping the real first task (P0T1) to a symbol with neighbors
cat > "$tmp/codemap.json" <<'EOF'
{ "edges": [["parseArgs","readConfig"],["main","parseArgs"]], "tasks": { "P0T1": ["parseArgs"] } }
EOF
# context_cmd wrapper: hand the executor's HB_TASK_ID to the code provider
printf '#!/usr/bin/env bash\nnode "%s/plugin/adapters/code/codegraph-context.js" "%s/codemap.json" "$HB_TASK_ID"\n' \
  "$ROOT" "$tmp" > "$tmp/ctx.sh"; chmod +x "$tmp/ctx.sh"

# (1) deterministic: the context the executor assembles actually carries the code subgraph
ctx="$(HB_EXEC_CONTEXT_CMD="bash $tmp/ctx.sh" PYTHONPATH="$ROOT/py/src" python3 -c "
from heartbeat import executor
print(executor.assemble_context('$HB', {'id':'P0T1','phase':'P0','title':'parse args'}))")"
echo "$ctx" | grep -q '<<HB-CONTEXT>>' || { echo "FAIL: no injected context block"; exit 1; }
echo "$ctx" | grep -q 'parseArgs'     || { echo "FAIL: touched symbol not in context"; exit 1; }
echo "$ctx" | grep -q 'readConfig'    || { echo "FAIL: neighbor not in context"; exit 1; }

# (2) real: drive ONE task against the ollama model with the context hook active
out="$(HB_EXEC_BACKEND=ollama HB_EXEC_MODEL="$MODEL" HB_EXEC_CONTEXT_CMD="bash $tmp/ctx.sh" \
  HB_EXEC_MAX_ITERS=1 HB_NO_GIT=1 PYTHONPATH="$ROOT/py/src" \
  python3 -m heartbeat.cli exec run --dir "$tmp/p" 2>&1)" || true
echo "$out" | grep -qiE 'HB-EXEC|done|task' || { echo "FAIL: ollama run produced no driver output"; echo "$out" | tail -3; exit 1; }

echo "REAL-CONTEXT-OK ($MODEL): code subgraph injected into the prompt; a real model was driven one task."
