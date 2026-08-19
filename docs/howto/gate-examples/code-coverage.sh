#!/usr/bin/env bash
# Proof: codegraph-coverage reports each task's symbol coverage and explicitly LISTS the GRAPH-BLIND
# tasks — those with zero resolved symbols (not-yet-existing / dynamic-framework code the graph can't
# model → read manually) — without mislabelling a covered task. node ≡ python. Prints CODE-COVERAGE-OK.
# Fails before codegraph-coverage exists (spec-first).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
FX="$ROOT/plugin/adapters/code/fixtures"
CM="$FX/coverage.codemap.json"; DAG="$FX/coverage.dag.json"

out="$(node "$ROOT/plugin/adapters/code/codegraph-coverage.js" "$CM" "$DAG")"

# TA is covered (2 symbols) and must NOT be blind
printf '%s' "$out" | grep -qE 'TA[^0-9]*2'                    || { echo "FAIL: TA should show 2 symbols"; echo "$out"; exit 1; }
# TB (empty symbols) and TC (absent from codemap.tasks) are BOTH graph-blind
blind="$(printf '%s' "$out" | grep -i 'GRAPH-BLIND')"
printf '%s' "$blind" | grep -q 'TB' && printf '%s' "$blind" | grep -q 'TC' || { echo "FAIL: TB and TC must be listed GRAPH-BLIND"; echo "$out"; exit 1; }
printf '%s' "$blind" | grep -q 'TA' && { echo "FAIL: covered TA wrongly listed GRAPH-BLIND"; echo "$out"; exit 1; }

# node ≡ python byte-identical
py="$(PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.code.codegraph_coverage "$CM" "$DAG")"
[ "$out" = "$py" ] || { echo "FAIL: node != python"; printf 'NODE=%s\n----\nPY=%s\n' "$out" "$py"; exit 1; }

echo "CODE-COVERAGE-OK"
