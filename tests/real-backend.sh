#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# Live end-to-end test: drive a real HeartBeat project with a LOCAL model via the
# ollama backend. The model must WRITE CODE that a BEHAVIORAL gate then compiles and
# runs. Non-deterministic (depends on the model) → intentionally NOT part of the
# ratcheted suite (tests/run-tests.sh). Run it by hand:
#     bash tests/real-backend.sh [model]        # default: qwen2.5:7b-instruct
# ══════════════════════════════════════════════════════════════════════════════
set -uo pipefail
HB_SRC="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="${1:-qwen2.5:7b-instruct}"
HOST="${OLLAMA_HOST:-http://localhost:11434}"

curl -s "$HOST/api/tags" -m 3 >/dev/null 2>&1 || { echo "ollama not reachable at $HOST — skipping live test"; exit 0; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
P="$TMP/real"; bash "$HB_SRC/plugin/bootstrap.sh" "$P" >/dev/null 2>&1 </dev/null
H="$P/.hb"

# One phase, one task. The gate REQUIRES and RUNS the model-written module — it passes
# only if greet() actually composes the string correctly. No file-existence shortcut.
cat > "$H/dag.json" <<'DAGEOF'
{
  "phases": [
    { "id": "M0", "title": "model writes code", "gate_entry": null, "gate_exit": "GM0",
      "tasks": [ { "id": "M0T1", "title": "create greeting.js", "requires": [],
        "description": "Create a file greeting.js at the project root that exports a CommonJS function greet(name) returning the string \"Hello, \" concatenated with the name argument. Use exactly: module.exports = { greet };" } ] }
  ],
  "gates": {
    "GM0": { "desc": "greet composes the greeting", "criteria": [
      { "id": "g1", "desc": "greet('Ada') === 'Hello, Ada'",
        "cmd": "node -e \"const g=require('$PROJECT_DIR/greeting.js');process.exit(g.greet('Ada')==='Hello, Ada'?0:1)\"" } ] }
  }
}
DAGEOF
node "$H/hb.js" rebuild >/dev/null

echo "▶ Driving a real HeartBeat project with ollama model: $MODEL"
echo "  Task: write greeting.js  ·  Gate: node requires it and asserts greet('Ada')==='Hello, Ada'"
echo "────────────────────────────────────────────────────────────"
out=$(HB_EXEC_BACKEND=ollama HB_EXEC_MODEL="$MODEL" HB_EXEC_MAX_ITERS=8 node "$H/hb-exec.js" run 2>&1)
echo "$out"
echo "────────────────────────────────────────────────────────────"

if node -e "const s=require('$H/state.json');process.exit(s.completed_phases.includes('M0')?0:1)"; then
  echo "✅ REAL RUN PASSED — the local model wrote working code and the behavioral gate ran it green."
  echo "--- greeting.js (model output) ---"; cat "$P/greeting.js"
  exit 0
else
  echo "❌ REAL RUN did not complete — the model's output did not satisfy the behavioral gate."
  [ -f "$P/greeting.js" ] && { echo "--- greeting.js (model output) ---"; cat "$P/greeting.js"; }
  exit 1
fi
