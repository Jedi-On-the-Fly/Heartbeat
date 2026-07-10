#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# HeartBeat bootstrap.sh
# Initialize a new HeartBeat project from templates.
#
# Usage: bash bootstrap.sh <project-dir> [--force]
#
# Example:
#   bash bootstrap.sh ~/projects/my-project
#
# Creates .hb/ inside the project dir with all HeartBeat files ready to go.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

TEMPLATES_DIR="$(cd "$(dirname "$0")/templates" && pwd)"
PROJECT_DIR="${1:-}"

if [ -z "$PROJECT_DIR" ]; then
  echo "Usage: bash bootstrap.sh <project-dir>"
  echo ""
  echo "Example:"
  echo "  bash bootstrap.sh ~/projects/my-project"
  exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
  echo "Creating project directory: $PROJECT_DIR"
  mkdir -p "$PROJECT_DIR"
fi

HB_DIR="$PROJECT_DIR/.hb"

FORCE="${2:-}"

if [ -d "$HB_DIR" ] && [ "$FORCE" != "--force" ]; then
  echo "⚠️  .hb/ already exists in $PROJECT_DIR"
  # v1.1: EOF-safe — en contexte non-interactif (cron/agent), pas de tty =
  # refus par defaut au lieu d'un crash sous set -e. --force pour ecraser.
  read -p "Overwrite? (y/N) " -n 1 -r REPLY || REPLY="n"
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted. (use: bootstrap.sh <project-dir> --force to overwrite)"
    exit 0
  fi
fi

mkdir -p "$HB_DIR"

# Copy templates
cp "$TEMPLATES_DIR/tick.sh"         "$HB_DIR/tick.sh"
cp "$TEMPLATES_DIR/gate.sh"         "$HB_DIR/gate.sh"
cp "$TEMPLATES_DIR/hb-next-task.js" "$HB_DIR/hb-next-task.js"
cp "$TEMPLATES_DIR/dag.json"        "$HB_DIR/dag.json"
for f in hb-lint.js hb-report.js hb-viz.js hb.js; do
  [ -f "$TEMPLATES_DIR/$f" ] && cp "$TEMPLATES_DIR/$f" "$HB_DIR/$f"
done
# v1.2: valider le DAG des le bootstrap (les erreurs de structure se voient ici, pas au tick N)
node "$HB_DIR/hb-lint.js" "$HB_DIR/dag.json" || echo "!! hb-lint a detecte des erreurs dans dag.json — corrigez avant de planifier le tick"

# Init state with timestamp
node -e "
  const s = JSON.parse(require('fs').readFileSync('$TEMPLATES_DIR/state.json','utf8'));
  s.last_updated = new Date().toISOString();
  require('fs').writeFileSync('$HB_DIR/state.json', JSON.stringify(s, null, 2));
"

# Init events log
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "{\"ts\":\"$TS\",\"event\":\"initialized\",\"project\":\"$(basename "$PROJECT_DIR")\"}" > "$HB_DIR/events.jsonl"

# v1.3: state.json is a PROJECTION of the event log — seed it so state == projection
# from the very first tick (log is authoritative from here on).
node "$HB_DIR/hb.js" rebuild >/dev/null 2>&1 || true

# Make scripts executable
chmod +x "$HB_DIR/tick.sh" "$HB_DIR/gate.sh" "$HB_DIR/hb-next-task.js" "$HB_DIR/hb.js"

echo ""
echo "✅ HeartBeat initialized in $HB_DIR"
echo ""
echo "Next steps:"
echo "  1. Edit $HB_DIR/dag.json — define your phases, tasks, and gate criteria"
echo "  2. Edit $HB_DIR/tick.sh  — set WATCH_PATHS if you want drift detection"
echo "  3. Test tick: bash $HB_DIR/tick.sh"
echo "  4. Schedule: use nanoclaw schedule_task with the tick.sh as the script"
echo ""
echo "Files created:"
ls -1 "$HB_DIR/"
