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

# v1.4: flags (any order after <project-dir>): --force (overwrite .hb), --no-git.
FORCE=""; NO_GIT=0
for a in "${@:2}"; do
  case "$a" in
    --force)  FORCE="--force";;
    --no-git) NO_GIT=1;;
  esac
done

if [ -d "$HB_DIR" ] && [ "$FORCE" != "--force" ]; then
  echo "⚠️  .hb/ already exists in $PROJECT_DIR"
  # v1.1: EOF-safe — in a non-interactive context (cron/agent) there is no tty, so
  # default to refusing instead of crashing under set -e. Use --force to overwrite.
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
for f in hb-lint.js hb-report.js hb-viz.js hb.js hb-exec.js hb-audit.js refuter_profiles.js; do
  [ -f "$TEMPLATES_DIR/$f" ] && cp "$TEMPLATES_DIR/$f" "$HB_DIR/$f"
done
# v1.8: pluggable Stage-B executor backends (claude-code / agno / crewai).
if [ -d "$TEMPLATES_DIR/executors" ]; then
  mkdir -p "$HB_DIR/executors"
  cp "$TEMPLATES_DIR/executors/"* "$HB_DIR/executors/" 2>/dev/null || true
fi
# Refuter profiles: seed the shipped library (JSON, lite .md, and canonical <name>/SKILL.md folders)
# into the project. COLLISION-SAFE — never seed a format for a name that already exists in the dest in
# ANY format, so a project's own refuter shadows the shipped one and re-bootstrap manufactures no
# same-name cross-format collision.
if [ -d "$TEMPLATES_DIR/refuters" ]; then
  mkdir -p "$HB_DIR/refuters"
  _hb_has_refuter() { [ -e "$HB_DIR/refuters/$1.json" ] || [ -e "$HB_DIR/refuters/$1.md" ] || [ -e "$HB_DIR/refuters/$1/SKILL.md" ]; }
  for _rf in "$TEMPLATES_DIR/refuters/"*.json "$TEMPLATES_DIR/refuters/"*.md; do
    [ -e "$_rf" ] || continue
    _bn="$(basename "$_rf")"; _n="${_bn%.*}"
    _hb_has_refuter "$_n" || cp "$_rf" "$HB_DIR/refuters/$_bn"
  done
  for _fd in "$TEMPLATES_DIR/refuters/"*/; do
    [ -e "$_fd/SKILL.md" ] || continue
    _n="$(basename "$_fd")"
    _hb_has_refuter "$_n" || cp -R "$TEMPLATES_DIR/refuters/$_n" "$HB_DIR/refuters/$_n"
  done
fi
# Validate the DAG at bootstrap — structural errors show up here, not at tick N.
node "$HB_DIR/hb-lint.js" "$HB_DIR/dag.json" || echo "!! hb-lint found errors in dag.json — fix them before scheduling the tick"

# Init state with timestamp
node -e "
  const s = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
  s.last_updated = new Date().toISOString();
  require('fs').writeFileSync(process.argv[2], JSON.stringify(s, null, 2));
" "$TEMPLATES_DIR/state.json" "$HB_DIR/state.json"

# Init events log
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "{\"ts\":\"$TS\",\"event\":\"initialized\",\"project\":\"$(basename "$PROJECT_DIR")\"}" > "$HB_DIR/events.jsonl"

# v1.3: state.json is a PROJECTION of the event log — seed it so state == projection
# from the very first tick (log is authoritative from here on).
node "$HB_DIR/hb.js" rebuild >/dev/null 2>&1 || true

# v1.7: write the pulse protocol into the project so it travels with the .hb/ tooling
# (version-matched, git-tracked) — the agent is never left guessing what a reason means.
node "$HB_DIR/hb.js" protocol --md > "$HB_DIR/PROTOCOL.md" 2>/dev/null || true

# Make scripts executable
chmod +x "$HB_DIR/tick.sh" "$HB_DIR/gate.sh" "$HB_DIR/hb-next-task.js" "$HB_DIR/hb.js"
[ -f "$HB_DIR/hb-exec.js" ] && chmod +x "$HB_DIR/hb-exec.js"
[ -d "$HB_DIR/executors" ] && chmod +x "$HB_DIR/executors/"*.sh 2>/dev/null || true

# v1.4: init git so each gate pass is a restore point (commit-on-gate-pass).
# Skips if: HB_NO_GIT set, --no-git, git absent, or already a repo.
GIT_MSG=""
if [ -z "${HB_NO_GIT:-}" ] && [ "$NO_GIT" != "1" ] && command -v git >/dev/null 2>&1 \
   && ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$PROJECT_DIR" init -q 2>/dev/null; then
    GI="$PROJECT_DIR/.gitignore"
    if ! grep -q "HeartBeat runtime" "$GI" 2>/dev/null; then
      {
        echo "# HeartBeat runtime (ephemeral — never source)"
        echo ".hb/.lock"; echo ".hb/.wlock"; echo ".hb/leases/"
        echo ".hb/.stuck-alerted"; echo ".hb/.noprogress-alerted"
        echo ".hb/.all-done-alerted"; echo ".hb/.deadlock-alerted"
        echo ".hb/.gate-notified"; echo ".hb/.drift-notified"
        echo ".hb/.review-stuck-alerted"; echo ".hb/.rot-alerted"; echo ".hb/.gate-blocked-ticks"
        echo ".hb/*.tmp"; echo ".hb/dag-view.html"
      } >> "$GI"
    fi
    # v1.6: pre-commit rot guard — block a commit that deletes/moves a file a
    # COMPLETED phase's gate depends on. Bypass with `git commit --no-verify` or
    # HB_NO_HOOK=1. HeartBeat's own commits already pass --no-verify.
    HOOK="$PROJECT_DIR/.git/hooks/pre-commit"
    if [ ! -e "$HOOK" ]; then
      cat > "$HOOK" <<'HOOKEOF'
#!/usr/bin/env bash
[ -n "${HB_NO_HOOK:-}" ] && exit 0
DIR="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -f "$DIR/.hb/hb.js" ] || exit 0
OUT="$(node "$DIR/.hb/hb.js" doctor 2>&1 || true)"
if echo "$OUT" | grep -q "no longer reproducible"; then
  echo "✗ HeartBeat rot guard: this commit breaks a completed gate:"
  echo "$OUT" | grep "no longer reproducible" | sed 's/^/    /'
  echo "  Fix the gate/file, or bypass: git commit --no-verify"
  exit 1
fi
exit 0
HOOKEOF
      chmod +x "$HOOK"
    fi
    git -C "$PROJECT_DIR" add -A >/dev/null 2>&1 || true
    # Fallback identity + --no-verify so init works even if git user isn't configured.
    git -c user.name='HeartBeat' -c user.email='heartbeat@local' \
        -C "$PROJECT_DIR" commit -q --no-verify -m "chore(heartbeat): initialize project" >/dev/null 2>&1 || true
    GIT_MSG="git initialized (+ rot pre-commit hook) — gate passes committed & tagged (HB_NO_GIT=1 to disable)"
  fi
fi

# Pre-push gate guard: before a push, RE-VERIFY every gate and BLOCK if any regressed. Installs into any
# git work tree (fresh OR existing), never clobbering an existing pre-push. The hook is bypassable at push
# time (`git push --no-verify` or HB_NO_HOOK=1); HeartBeat never auto-pushes, so it only fires on a human push.
if [ -z "${HB_NO_GIT:-}" ] && [ "$NO_GIT" != "1" ] && command -v git >/dev/null 2>&1 \
   && git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  PPHOOK="$PROJECT_DIR/.git/hooks/pre-push"
  if [ ! -e "$PPHOOK" ]; then
    mkdir -p "$(dirname "$PPHOOK")"
    cat > "$PPHOOK" <<'HOOKEOF'
#!/usr/bin/env bash
[ -n "${HB_NO_HOOK:-}" ] && exit 0
DIR="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -x "$DIR/.hb/gate.sh" ] || exit 0
if ! bash "$DIR/.hb/gate.sh" --all >/dev/null 2>&1; then
  echo "✗ HeartBeat gate guard: push blocked — a gate no longer verifies."
  echo "  Re-verify: bash .hb/gate.sh --all    ·    bypass: git push --no-verify"
  exit 1
fi
exit 0
HOOKEOF
    chmod +x "$PPHOOK"
  fi
fi

echo ""
echo "✅ HeartBeat initialized in $HB_DIR"
[ -n "$GIT_MSG" ] && echo "   $GIT_MSG"
echo ""
echo "Next steps:"
echo "  1. Edit $HB_DIR/dag.json — define your phases, tasks, and gate criteria"
echo "  2. Edit $HB_DIR/tick.sh  — set WATCH_PATHS if you want drift detection"
echo "  3. Test tick: bash $HB_DIR/tick.sh"
echo "  4. Schedule: use nanoclaw schedule_task with the tick.sh as the script"
echo ""
echo "Files created:"
ls -1 "$HB_DIR/"
