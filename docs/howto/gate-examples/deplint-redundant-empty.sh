#!/usr/bin/env bash
# Proof: deplint does NOT report REDUNDANT for a `requires` edge whose task has no resolved symbols
# (a spec-first / not-yet-existing file — the graph has no basis to judge), while a GENUINE redundant
# edge (both endpoints have symbols, no code dependency) is still reported. node ≡ python. Prints
# REDUNDANT-EMPTY-OK. Fails on the current engine (which flags BOTH) — spec-first.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
FX="$ROOT/plugin/adapters/code/fixtures"
DAG="$FX/redundant-empty.dag.json"; CM="$FX/redundant-empty.codemap.json"

jn="$(node "$ROOT/plugin/adapters/code/deplint.js" "$DAG" "$CM")"
py="$(PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.code.deplint "$DAG" "$CM")"

# genuine redundant (TC→TD: both have symbols, no edge) is KEPT
echo "$jn" | grep -q 'REDUNDANT: TC requires TD' || { echo "FAIL: genuine REDUNDANT TC→TD was dropped (over-fired)"; echo "$jn"; exit 1; }
# empty-symbol edge (TA→TB: TB has no symbols) is SUPPRESSED
echo "$jn" | grep -q 'REDUNDANT: TA requires TB' && { echo "FAIL: TA→TB reported REDUNDANT but TB has no symbols (no basis)"; echo "$jn"; exit 1; }
# node ≡ python
[ "$jn" = "$py" ] || { echo "FAIL: node != python"; printf 'NODE=%s\nPY=%s\n' "$jn" "$py"; exit 1; }

echo "REDUNDANT-EMPTY-OK"
