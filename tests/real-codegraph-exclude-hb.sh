#!/usr/bin/env bash
# ON-DEMAND / harness-first — NOT gated (CodeGraph not vendored). Proves the REAL indexing effect of
# the exclude helper: after it writes codegraph.json, a fresh `codegraph init` indexes ZERO nodes under
# `.hb/` (vs a nonzero baseline without it). Skips cleanly without codegraph/sqlite3. Prints
# REAL-EXCLUDE-HB-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node     >/dev/null 2>&1 || { echo "SKIP: node absent"; exit 0; }
command -v sqlite3  >/dev/null 2>&1 || { echo "SKIP: sqlite3 absent"; exit 0; }
command -v codegraph >/dev/null 2>&1 || { echo "SKIP: codegraph CLI absent (harness-first)"; exit 0; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/proj/.hb"
printf 'def app():\n    return 1\n' > "$tmp/proj/app.py"
printf 'function orchestrate(){return 2}\nmodule.exports={orchestrate}\n' > "$tmp/proj/.hb/hb.js"

# baseline: NO helper -> .hb is indexed (nonzero)
( cd "$tmp/proj" && codegraph init . >/dev/null 2>&1 </dev/null ) || { echo "SKIP: codegraph init failed"; exit 0; }
base="$(sqlite3 "$tmp/proj/.codegraph/codegraph.db" "SELECT count(*) FROM nodes WHERE file_path LIKE '.hb/%' OR file_path LIKE '%/.hb/%';")"
[ "${base:-0}" -gt 0 ] || { echo "SKIP: baseline did not index .hb (nothing to prove)"; exit 0; }

# with the helper -> fresh init indexes ZERO .hb nodes
rm -rf "$tmp/proj/.codegraph"
node "$ROOT/plugin/adapters/code/codegraph-exclude-hb.js" "$tmp/proj"
( cd "$tmp/proj" && codegraph init . >/dev/null 2>&1 </dev/null ) || { echo "FAIL: re-init failed"; exit 1; }
after="$(sqlite3 "$tmp/proj/.codegraph/codegraph.db" "SELECT count(*) FROM nodes WHERE file_path LIKE '.hb/%' OR file_path LIKE '%/.hb/%';")"
[ "${after:-1}" -eq 0 ] || { echo "FAIL: .hb still indexed after exclude ($after nodes)"; exit 1; }

echo "REAL-EXCLUDE-HB-OK (codegraph $(codegraph --version 2>/dev/null | head -1)): .hb/ nodes $base -> 0 after exclude."
