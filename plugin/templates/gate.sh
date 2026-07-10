#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# HeartBeat gate.sh — Generic gate runner (v1.1)
# Usage: bash gate.sh <GATE_ID>
# Exit 0 = gate passed | 1 = gate blocked | 2 = usage / unknown gate
#
# v1.1 :
#   - PROJECT_DIR et HB_DIR définis + exportés (les cmd des critères peuvent
#     les utiliser — le template dag.json en dépend)
#   - Chaque critère est évalué en SOUS-SHELL : une variable inconnue ou une
#     erreur d'expansion = critère ✗ affiché, plus jamais un crash silencieux
#   - Parsing des critères en UN seul appel node (séparateur \x1f)
#   - GATE_ID passé en argv à node (plus d'interpolation dans le code)
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

HB_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$HB_DIR")"
export HB_DIR PROJECT_DIR

GATE="${1:-}"
DAG_FILE="$HB_DIR/dag.json"
EVENTS_FILE="$HB_DIR/events.jsonl"

# v1.3 (#4): each criterion runs under a timeout so a hanging/slow cmd blocks the
# gate (✗) instead of hanging the tick. dag.json is TRUSTED input (criteria are
# eval'd) — keep cmd deterministic and one-line. GATE_TIMEOUT_S overridable.
GATE_TIMEOUT_S="${GATE_TIMEOUT_S:-5}"
if   command -v timeout  >/dev/null 2>&1; then TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN="gtimeout"
else TIMEOUT_BIN=""; fi   # no timeout binary → run without (documented fallback)
run_criterion() {   # $1 = cmd string; inherits exported PROJECT_DIR/HB_DIR
  if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "${GATE_TIMEOUT_S}s" bash -c "$1"
  else bash -c "$1"; fi
}

if [ -z "$GATE" ]; then
  echo "Usage: gate.sh <GATE_ID>"
  echo "Available gates:"
  node -e "
    const dag = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    Object.keys(dag.gates).forEach(g => console.log('  ' + g + ' — ' + (dag.gates[g].desc||'')));
  " "$DAG_FILE"
  exit 2
fi

# Validate gate exists
node -e "
  const dag = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
  if (!dag.gates[process.argv[2]]) { console.error('Unknown gate: ' + process.argv[2]); process.exit(2); }
" "$DAG_FILE" "$GATE" || exit 2

PASS=0
FAIL=0

echo "=== Gate: $GATE ==="
echo ""

# Un seul appel node — chaque critère sur une ligne : id \x1f desc \x1f cmd
# (les cmd doivent tenir sur une ligne — déjà requis par la convention HB)
while IFS=$'\x1f' read -r ID DESC CMD; do
  if run_criterion "$CMD" >/dev/null 2>&1; then
    echo "  ✓ [$ID] $DESC"
    PASS=$((PASS + 1))
  else
    echo "  ✗ [$ID] $DESC"
    echo "      cmd: $CMD"
    FAIL=$((FAIL + 1))
  fi
done < <(node -e "
  const dag = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
  for (const c of dag.gates[process.argv[2]].criteria) {
    console.log([c.id, c.desc, c.cmd].join('\x1f'));
  }
" "$DAG_FILE" "$GATE")

echo ""
echo "=== Result: $PASS passed, $FAIL failed ==="

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# v1.3: after logging, reproject so the phase advances (pass) or gate.errors is
# set (fail) with no hand-edited state. hb.js is the sole state mutator.
reproject() { [ -f "$HB_DIR/hb.js" ] && node "$HB_DIR/hb.js" rebuild >/dev/null 2>&1 || true; }
if [ "$FAIL" -eq 0 ]; then
  echo "{\"ts\":\"$TS\",\"event\":\"gate_passed\",\"gate\":\"$GATE\",\"pass\":$PASS,\"fail\":0}" >> "$EVENTS_FILE"
  reproject
  echo ""
  # v1.4 (#3): if this gate requires an adversarial review, the phase does NOT
  # advance yet — a second agent must try to refute completion, then: hb review.
  if node -e "process.exit((JSON.parse(require('fs').readFileSync('$DAG_FILE','utf8')).gates['$GATE']||{}).review?0:1)" 2>/dev/null; then
    echo "🧪 DETERMINISTIC GATE PASSED — adversarial review required."
    echo "   Spawn a skeptical reviewer to REFUTE completion, then run:"
    echo "     node $HB_DIR/hb.js review $GATE pass    (could not refute)"
    echo "     node $HB_DIR/hb.js review $GATE fail \"<findings>\"   (found holes)"
    exit 0
  fi
  echo "✅ GATE PASSED — proceed to next phase."
  exit 0
else
  echo "{\"ts\":\"$TS\",\"event\":\"gate_failed\",\"gate\":\"$GATE\",\"pass\":$PASS,\"fail\":$FAIL}" >> "$EVENTS_FILE"
  reproject
  echo ""
  echo "❌ GATE BLOCKED — fix $FAIL failing criteria before proceeding."
  exit 1
fi
