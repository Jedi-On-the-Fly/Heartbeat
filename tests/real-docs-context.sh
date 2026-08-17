#!/usr/bin/env bash
# ON-DEMAND / harness-first — NOT in the gated suite. Docs Seam-2 end-to-end with a REAL local ollama
# model: docs-context feeds a task's directly-cited section TEXT into the model's prompt via the same
# generic context hook the code adapter uses. Needs ollama + a model; skips cleanly otherwise.
# Non-deterministic — the injection MECHANISM is gated deterministically (T89 parity, T91 provider).
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
FX="$ROOT/plugin/adapters/docs/fixtures"

# context_cmd wrapper: hand the executor's task to docs-context over the fixture corpus+codemap.
# (map the bootstrap's first task id to a fixture section so there is cited text to inject.)
printf '#!/usr/bin/env bash\nnode "%s/plugin/adapters/docs/docs-context.js" "%s/corpus" "%s/docs.codemap.json" results\n' \
  "$ROOT" "$FX" "$FX" > "$tmp/ctx.sh"; chmod +x "$tmp/ctx.sh"

# (1) deterministic: the assembled context carries the directly-cited section's text
ctx="$(HB_EXEC_CONTEXT_CMD="bash $tmp/ctx.sh" PYTHONPATH="$ROOT/py/src" python3 -c "
from heartbeat import executor
print(executor.assemble_context('$HB', {'id':'P0T1','phase':'P0','title':'write results'}))")"
echo "$ctx" | grep -q '<<HB-CONTEXT>>'          || { echo "FAIL: no injected context block"; exit 1; }
echo "$ctx" | grep -q 'Our approach, building on' || { echo "FAIL: cited section text not injected"; exit 1; }

# (2) real: drive ONE task against the ollama model with the docs context hook active
out="$(HB_EXEC_BACKEND=ollama HB_EXEC_MODEL="$MODEL" HB_EXEC_CONTEXT_CMD="bash $tmp/ctx.sh" \
  HB_EXEC_MAX_ITERS=1 HB_NO_GIT=1 PYTHONPATH="$ROOT/py/src" \
  python3 -m heartbeat.cli exec run --dir "$tmp/p" 2>&1)" || true
echo "$out" | grep -qiE 'HB-EXEC|done|task' || { echo "FAIL: ollama run produced no driver output"; echo "$out" | tail -3; exit 1; }

echo "REAL-DOCS-CONTEXT-OK ($MODEL): cited-section text injected into the prompt; a real model was driven one task."
