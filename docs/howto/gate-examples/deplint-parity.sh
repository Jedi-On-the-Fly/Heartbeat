#!/usr/bin/env bash
# Parity proof: the code dep-lint engine is node ≡ python — BYTE-IDENTICAL stdout AND identical
# --strict exit codes on every fixture (incl. `multi`, which yields >=2 MISSING and >=2 COLLISION
# findings so emit ORDER is pinned). Fails before the Python module exists (spec-first).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
DLJ="$ROOT/plugin/adapters/code/deplint.js"
FX="$ROOT/plugin/adapters/code/fixtures"
pyd(){ PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.code.deplint "$@"; }

for fx in missing redundant collision clean transitive multi; do
  jn="$(node "$DLJ" "$FX/$fx.dag.json" "$FX/$fx.codemap.json")"
  py="$(pyd       "$FX/$fx.dag.json" "$FX/$fx.codemap.json")"
  [ "$jn" = "$py" ] || { echo "FAIL[$fx]: deplint stdout differs node vs python"; diff <(printf '%s' "$jn") <(printf '%s' "$py"); exit 1; }
  rn=0; node "$DLJ" "$FX/$fx.dag.json" "$FX/$fx.codemap.json" --strict >/dev/null 2>&1 || rn=$?
  rp=0; pyd       "$FX/$fx.dag.json" "$FX/$fx.codemap.json" --strict >/dev/null 2>&1 || rp=$?
  [ "$rn" = "$rp" ] || { echo "FAIL[$fx]: --strict exit differs (node=$rn python=$rp)"; exit 1; }
done
echo "DEPLINT-PARITY-OK"
