#!/usr/bin/env bash
# Proof: the confident claims are honest. A LICENSE file exists and says MIT (declared in 5 places); no
# doc presents an unpublished `pip install heartbeat-hb` as an install line (the package is unpublished —
# quickstarts use the real local install). Prints CLAIM-HONESTY-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fail(){ echo "FAIL: $1"; exit 1; }
[ -f "$ROOT/LICENSE" ] || fail "no LICENSE file (MIT is declared in plugin.json/marketplace/pyproject/README)"
grep -qi 'MIT' "$ROOT/LICENSE" || fail "LICENSE does not say MIT"
hits="$(grep -rl --include=*.md "pip install heartbeat-hb" "$ROOT/docs" "$ROOT/README.md" "$ROOT/INSTALL.md" "$ROOT/SECURITY.md" "$ROOT/release" 2>/dev/null || true)"
[ -z "$hits" ] || fail "unpublished 'pip install heartbeat-hb' presented as an install line in: $hits"
echo "CLAIM-HONESTY-OK"
