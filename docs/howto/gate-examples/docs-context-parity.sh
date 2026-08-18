#!/usr/bin/env bash
# Parity proof: docs-context is node ≡ python — BYTE-IDENTICAL rendered cited-section text, for a
# task citing TWO sections (intro -> background + method, pins render order) AND one citing one
# (results -> method). Fails before the Python module exists (spec-first).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
FX="$ROOT/plugin/adapters/docs/fixtures"
DCJ="$ROOT/plugin/adapters/docs/docs-context.js"
pyc(){ PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.docs.docs_context "$@"; }

# intro cites 2 sections (order), results cites 1, background cites NOTHING (the empty branch)
for task in intro results background; do
  jn="$(node "$DCJ" "$FX/corpus" "$FX/docs.codemap.json" "$task")"
  py="$(pyc            "$FX/corpus" "$FX/docs.codemap.json" "$task")"
  [ "$jn" = "$py" ] || { echo "FAIL[$task]: docs-context text differs node vs python"; diff <(printf '%s' "$jn") <(printf '%s' "$py"); exit 1; }
done

# a task citing a section whose file is MISSING -> both must render '(section text unavailable)'
tmpc="$(mktemp)"; trap 'rm -f "$tmpc"' EXIT
printf '{"edges":[["orphan","ghost"]],"tasks":{"orphan":["orphan"]}}' > "$tmpc"
jn="$(node "$DCJ" "$FX/corpus" "$tmpc" orphan)"; py="$(pyc "$FX/corpus" "$tmpc" orphan)"
[ "$jn" = "$py" ] || { echo "FAIL[missing-file]: docs-context differs node vs python"; diff <(printf '%s' "$jn") <(printf '%s' "$py"); exit 1; }

echo "DOCS-CONTEXT-PARITY-OK"
