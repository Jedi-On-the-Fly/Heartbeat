#!/usr/bin/env bash
# Parity proof: deplint-accept is node ≡ python — byte-identical for the delegated report AND the
# skip message — and the ported resolveTaskSymbols / resolve_task_symbols agree (the fuzzy matcher,
# previously node-only). Prints DEPLINT-ACCEPT-PARITY-OK. Fails before the python twin exists.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
FX="$ROOT/plugin/adapters/code/fixtures"
export PYTHONPATH="$ROOT/py/src"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/hit"; cp "$FX/missing.codemap.json" "$tmp/hit/codemap.json"; mkdir -p "$tmp/skip"

# (1) delegated report byte-identical
jn="$(node "$ROOT/plugin/adapters/code/deplint-accept.js" --dir "$tmp/hit" --dag "$FX/missing.dag.json")"
py="$(python3 -m heartbeat.adapters.code.deplint_accept --dir "$tmp/hit" --dag "$FX/missing.dag.json")"
[ "$jn" = "$py" ] || { echo "FAIL: report differs node vs python"; printf 'NODE=%s\nPY=%s\n' "$jn" "$py"; exit 1; }
# (2) skip message byte-identical
sn="$(node "$ROOT/plugin/adapters/code/deplint-accept.js" --dir "$tmp/skip" --dag "$FX/missing.dag.json")"
sp="$(python3 -m heartbeat.adapters.code.deplint_accept --dir "$tmp/skip" --dag "$FX/missing.dag.json")"
[ "$sn" = "$sp" ] || { echo "FAIL: skip message differs node vs python"; printf 'NODE=%s\nPY=%s\n' "$sn" "$sp"; exit 1; }

# (3) resolveTaskSymbols == resolve_task_symbols on a NON-TRIVIAL dag+nodes (fuzzy leaf-name match)
dag='{"phases":[{"tasks":[{"id":"T1","title":"Add Login flow","description":""},{"id":"T2","title":"wire Query cache","description":"uses Query"}]}]}'
nodes='[{"qualified_name":"auth.go::Login"},{"qualified_name":"db.go::Query"},{"qualified_name":"util.go::Helper"}]'
rn="$(node -e 'const {resolveTaskSymbols}=require(process.argv[1]); process.stdout.write(JSON.stringify(resolveTaskSymbols(JSON.parse(process.argv[2]),JSON.parse(process.argv[3]))))' "$ROOT/plugin/adapters/code/codegraph-map.js" "$dag" "$nodes")"
rp="$(python3 -c 'import sys,json; from heartbeat.adapters.code.codegraph_map import resolve_task_symbols as r; print(json.dumps(r(json.loads(sys.argv[1]),json.loads(sys.argv[2]))))' "$dag" "$nodes")"
python3 -c 'import sys,json; sys.exit(0 if json.loads(sys.argv[1])==json.loads(sys.argv[2]) else 1)' "$rn" "$rp" \
  || { echo "FAIL: resolveTaskSymbols differs node vs python"; printf 'NODE=%s\nPY=%s\n' "$rn" "$rp"; exit 1; }
# sanity: the match is non-trivial (T1 -> Login, T2 -> Query, Helper unmatched)
echo "$rn" | grep -q 'auth.go::Login' || { echo "FAIL: resolve fixture too trivial (no match)"; exit 1; }

echo "DEPLINT-ACCEPT-PARITY-OK"
