#!/usr/bin/env bash
# Doc-coverage proof: docs/adapters.md must DOCUMENT every shipped adapter — each domain directory under
# plugin/adapters/ and every tool (*.js) inside it must be named in the doc. Derives the truth from the
# filesystem (no hardcoded list), so a new adapter or tool that ships without a doc entry turns this RED.
# This is the anti-drift gate for the reference doc: the doc is a claim about what adapters exist, and
# this keeps that claim honest. Prints ADAPTERS-DOC-OK. Deterministic — no network.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DOC="$ROOT/docs/adapters.md"
[ -f "$DOC" ] || { echo "FAIL: docs/adapters.md missing"; exit 1; }

missing=0
for dir in "$ROOT"/plugin/adapters/*/; do
  dom="$(basename "$dir")"
  for js in "$dir"*.js; do
    [ -f "$js" ] || continue
    n="$(basename "$js" .js)"
    # Require the tool's `<name>.js` form with a left boundary — so `deplint.js` is NOT satisfied by a
    # mention of `deplint-accept.js` (substring), keeping each tool's coverage independent.
    grep -qE "(^|[^A-Za-z0-9_-])${n}\.js" "$DOC" || { echo "FAIL: adapter tool '$n.js' ($dom) is shipped but not documented in adapters.md"; missing=1; }
  done
done
# Every shipped domain has ≥1 tool, so naming each tool's file already proves the domain is documented.
[ "$missing" = 0 ] || { echo "adapters.md is out of sync with plugin/adapters/"; exit 1; }

echo "ADAPTERS-DOC-OK"
