#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# HeartBeat — fallback installer (no plugin, no marketplace)
#
# Installs the /heartbeat skill and the HeartBeat tooling into the user's
# ~/.claude directory so it works on Claude Code without the plugin system.
#
# Usage:
#   bash scripts/install.sh              # install (idempotent)
#   bash scripts/install.sh --uninstall  # remove what this installer created
#
# Respects $HOME (set HOME=/tmp/sandbox for a dry sandbox install).
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"          # repo root
PLUGIN="$SRC/plugin"                              # bundled plugin (bootstrap + templates + skill)
CLAUDE_DIR="${HOME}/.claude"
HEARTBEAT_HOME="${CLAUDE_DIR}/heartbeat"          # tooling: bootstrap + templates
SKILL_DIR="${CLAUDE_DIR}/skills/heartbeat"        # the /heartbeat skill

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$HEARTBEAT_HOME" "$SKILL_DIR"
  echo "✅ HeartBeat uninstalled (removed $HEARTBEAT_HOME and $SKILL_DIR)"
  exit 0
fi

command -v node >/dev/null 2>&1 || { echo "❌ node (v18+) is required." >&2; exit 1; }

echo "Installing HeartBeat from: $SRC"

# 1. Tooling: bootstrap.sh + templates (bootstrap derives templates from its own dir)
mkdir -p "$HEARTBEAT_HOME"
cp "$PLUGIN/bootstrap.sh" "$HEARTBEAT_HOME/bootstrap.sh"
rm -rf "$HEARTBEAT_HOME/templates"
cp -R "$PLUGIN/templates" "$HEARTBEAT_HOME/templates"
chmod +x "$HEARTBEAT_HOME/bootstrap.sh"

# 2. Skill: copy with ${CLAUDE_PLUGIN_ROOT} rewritten to the install location,
#    since the plugin env var is not set on the script-install path.
mkdir -p "$SKILL_DIR"
sed "s#\${CLAUDE_PLUGIN_ROOT}#${HEARTBEAT_HOME}#g" \
  "$PLUGIN/skills/heartbeat/SKILL.md" > "$SKILL_DIR/SKILL.md"

echo ""
echo "✅ HeartBeat installed:"
echo "   • Skill    → $SKILL_DIR/SKILL.md   (use /heartbeat)"
echo "   • Tooling  → $HEARTBEAT_HOME/"
echo ""
echo "Optional: append the system-integration snippet to your CLAUDE.md:"
echo "   $SRC/CLAUDE-MD-SNIPPET.md"

# 3. Smoke test: bootstrap a throwaway project and confirm .hb/ is created.
SMOKE="$(mktemp -d)"
trap 'rm -rf "$SMOKE"' EXIT
if bash "$HEARTBEAT_HOME/bootstrap.sh" "$SMOKE/proj" >/dev/null 2>&1 </dev/null \
   && [ -d "$SMOKE/proj/.hb" ]; then
  echo ""
  echo "✅ Smoke test passed — bootstrap creates a working .hb/"
else
  echo ""
  echo "❌ Smoke test FAILED — bootstrap did not create .hb/" >&2
  exit 1
fi

echo ""
echo "Next: /heartbeat init <your-project-dir>"
