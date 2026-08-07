#!/usr/bin/env bash
# Proof for "Turn a plan into a DAG": a well-authored DAG is a runnable contract, and the
# common mistake — a prompt-shaped DAG with a hollow gate — is caught before it runs. Prove:
#   1. a worked-example DAG is lint-clean AND audit-clean AND runs to completion,
#   2. the same phase with a hollow gate (test -f) is REJECTED by the auditor (hollow_gate).
# Prints DAG-AUTHORING-OK only when the good DAG is clean+runnable and the bad one is caught.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
LINT="$ROOT/plugin/templates/hb-lint.js"; AUDIT="$ROOT/plugin/templates/hb-audit.js"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
command -v node    >/dev/null 2>&1 || { echo "node absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
worker="$work/worker.sh"; printf '#!/usr/bin/env bash\ncat >/dev/null\necho ok > result.txt\necho '\''{"ok":true,"summary":"wrote result.txt"}'\''\n' > "$worker"; chmod +x "$worker"

# A GOOD worked-example DAG: a phase, a task, and a BEHAVIORAL gate (asserts content).
good="$work/good.json"
python3 -c 'import json,sys;json.dump({"phases":[{"id":"BUILD","gate_entry":None,"gate_exit":"GATE_BUILD","tasks":[{"id":"B1","title":"produce result.txt with ok"}]}],"gates":{"GATE_BUILD":{"desc":"the build produced a valid result","criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/result.txt\""}]}}},open(sys.argv[1],"w"))' "$good"
# A BAD prompt-shaped DAG: same phase, but the gate only checks the file EXISTS (hollow).
bad="$work/bad.json"
python3 -c 'import json,sys;json.dump({"phases":[{"id":"BUILD","gate_entry":None,"gate_exit":"GATE_BUILD","tasks":[{"id":"B1","title":"produce result.txt"}]}],"gates":{"GATE_BUILD":{"desc":"done","criteria":[{"id":"c","cmd":"test -f \"$PROJECT_DIR/result.txt\""}]}}},open(sys.argv[1],"w"))' "$bad"

# 1a. The good DAG is lint-clean and audit-clean.
node "$LINT" "$good" >/dev/null 2>&1 || fail "the worked-example DAG did not lint clean"
[ "$(node "$AUDIT" "$good" --json | node -pe 'const d=JSON.parse(require("fs").readFileSync(0));d.errors+d.warns')" = 0 ] \
  || fail "the worked-example DAG did not audit clean (0 errors+warns)"

# 1b. The good DAG actually runs to completion under a real worker.
p="$(mktemp -d)"; hb init "$p" >/dev/null 2>&1; cp "$good" "$p/.hb/dag.json"; hb rebuild --dir "$p" >/dev/null 2>&1
HB_EXEC_CMD="$worker" HB_EXEC_MAX_ITERS=25 hb exec run --dir "$p" >/dev/null 2>&1
hb state --dir "$p" | python3 -c "import sys,json;sys.exit(0 if 'BUILD' in json.load(sys.stdin).get('completed_phases',[]) else 1)" \
  || fail "the worked-example DAG did not run to completion"
rm -rf "$p"

# 2. The prompt-shaped DAG (hollow gate) is REJECTED by the auditor.
node "$AUDIT" "$bad" --json | node -pe 'JSON.parse(require("fs").readFileSync(0)).findings.map(x=>x.rule)' | grep -q hollow_gate \
  || fail "the hollow-gate DAG was NOT rejected by the auditor"
# Control: the auditor does NOT flag the good DAG as hollow.
node "$AUDIT" "$good" --json | node -pe 'JSON.parse(require("fs").readFileSync(0)).findings.map(x=>x.rule)' | grep -q hollow_gate \
  && fail "the auditor wrongly flagged the good DAG as hollow"

echo "DAG-AUTHORING-OK: the worked-example DAG lints, audits, and runs; a hollow-gate DAG is rejected."
