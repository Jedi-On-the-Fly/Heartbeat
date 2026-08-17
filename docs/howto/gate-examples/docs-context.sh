#!/usr/bin/env bash
# Proof: the docs Seam-2 provider renders the TEXT of the sections a task DIRECTLY cites — not the
# whole corpus, not an echo, not a 2-hop citation. Fixture: task 'results' directly cites 'method'
# (edge results->method); 'method' cites 'background' (so background is 2-hop from results). So the
# rendered block must contain method's body, and must NOT contain background's body (2-hop) nor
# results' own body (a section does not cite itself). Fails before docs-context.js exists.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
CC="$ROOT/plugin/adapters/docs/docs-context.js"
FX="$ROOT/plugin/adapters/docs/fixtures"

out="$(node "$CC" "$FX/corpus" "$FX/docs.codemap.json" results)"
echo "$out" | grep -q 'Our approach, building on'          || { echo "FAIL: direct-cited section (method) text missing"; exit 1; }
echo "$out" | grep -q 'The problem domain and prior work'  && { echo "FAIL: 2-hop section (background) text leaked"; exit 1; } || true
echo "$out" | grep -q 'The findings produced by'           && { echo "FAIL: the task's own section body leaked (self)"; exit 1; } || true

echo "DOCS-CONTEXT-OK"
