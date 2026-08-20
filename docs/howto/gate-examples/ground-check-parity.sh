#!/usr/bin/env bash
# Parity proof: ground-check is node ≡ python — BYTE-identical grounding report on the same evidence
# map. Fails before the Python twin exists (spec-first).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
FX="$ROOT/plugin/adapters/research/fixtures/evidence"

jn="$(node "$ROOT/plugin/adapters/research/ground-check.js" "$FX/evidence.json" "$FX/sources")"
py="$(PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.research.ground_check "$FX/evidence.json" "$FX/sources")"
[ "$jn" = "$py" ] || { echo "FAIL: node vs python grounding report differs"; printf 'NODE=%s\n----\nPY=%s\n' "$jn" "$py"; exit 1; }

echo "GROUND-CHECK-PARITY-OK"
