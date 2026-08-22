#!/usr/bin/env bash
# Proof (H2): every planning/*.dag.json example DAG lints clean (0 errors) and audits with 0 hollow gates
# — the 50+ example DAGs are the project's best evidence and must be gated. Prints EXAMPLE-DAGS-GATED-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
fail(){ echo "FAIL: $1"; exit 1; }
n=0
for f in "$ROOT"/planning/*.dag.json; do
  [ -f "$f" ] || continue
  n=$((n+1))
  node "$ROOT/plugin/templates/hb-lint.js" "$f" >/dev/null 2>&1 || fail "lint errors in $(basename "$f")"
  node "$ROOT/plugin/templates/hb-audit.js" "$f" >/dev/null 2>&1 || fail "hollow gate(s) in $(basename "$f")"
done
[ "$n" -ge 1 ] || fail "no planning/*.dag.json found"
echo "EXAMPLE-DAGS-GATED-OK ($n DAGs)"
