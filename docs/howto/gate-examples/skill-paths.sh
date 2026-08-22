#!/usr/bin/env bash
# Proof (C6): adapter skills' RUNNABLE commands reference the plugin via ${CLAUDE_PLUGIN_ROOT} (like the
# main heartbeat skill), not a bare repo-relative `plugin/adapters/...` that 404s from an installed
# plugin. Prints SKILL-PATHS-OK. Fails today. Deterministic.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fail(){ echo "FAIL: $1"; exit 1; }
for sk in research-grounding code-aware-planning docs-authoring; do
  f="$ROOT/plugin/skills/$sk/SKILL.md"
  [ -f "$f" ] || fail "missing skill $sk"
  # a runnable command must not use a bare repo-relative plugin/adapters path
  grep -nE '(node|bash) +plugin/adapters/' "$f" && fail "$sk: runnable command uses bare 'plugin/adapters/...' (404 from an installed plugin — use \${CLAUDE_PLUGIN_ROOT})"
done
echo "SKILL-PATHS-OK"
