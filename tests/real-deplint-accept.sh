#!/usr/bin/env bash
# ON-DEMAND / harness-first — NOT gated (CodeGraph is not vendored). Proves the db-build resolution
# branch of deplint-accept: with NO codemap.json present, the wrapper auto-builds a provisional
# codemap from a REAL .codegraph/codegraph.db (CodeGraph edges + fuzzy task→symbol) and dep-lints
# it — node ≡ python. Skips cleanly when codegraph/sqlite3 are absent. Prints REAL-DEPLINT-ACCEPT-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node     >/dev/null 2>&1 || { echo "SKIP: node absent"; exit 0; }
command -v python3  >/dev/null 2>&1 || { echo "SKIP: python3 absent"; exit 0; }
command -v sqlite3  >/dev/null 2>&1 || { echo "SKIP: sqlite3 absent"; exit 0; }
command -v codegraph >/dev/null 2>&1 || { echo "SKIP: codegraph CLI absent (harness-first)"; exit 0; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/proj/pkg"
cat > "$tmp/proj/pkg/base.py" <<'EOF'
class Animal:
    def speak(self):
        return "..."
EOF
cat > "$tmp/proj/pkg/dog.py" <<'EOF'
from pkg.base import Animal

class Dog(Animal):
    def speak(self):
        return "woof"
EOF
( cd "$tmp/proj" && codegraph init . >/dev/null 2>&1 </dev/null ) || { echo "SKIP: codegraph init failed"; exit 0; }
[ -f "$tmp/proj/.codegraph/codegraph.db" ] || { echo "SKIP: no codegraph.db produced"; exit 0; }

# A dag whose task text names symbols so the fuzzy task→symbol mapping is non-empty. NO codemap.json.
cat > "$tmp/dag.json" <<'EOF'
{ "phases": [ { "tasks": [
  { "id": "T1", "title": "define Animal base", "description": "Animal.speak", "requires": [] },
  { "id": "T2", "title": "add Dog", "description": "Dog extends Animal", "requires": [] }
] } ] }
EOF

jn="$(node "$ROOT/plugin/adapters/code/deplint-accept.js" --dir "$tmp/proj" --dag "$tmp/dag.json")"
py="$(PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.code.deplint_accept --dir "$tmp/proj" --dag "$tmp/dag.json")"

# (1) it took the db-build branch, NOT the skip branch
printf '%s' "$jn" | grep -q 'DEPLINT-ACCEPT-SKIP' && { echo "FAIL: wrapper skipped instead of building from .codegraph"; exit 1; }
printf '%s' "$jn" | grep -q 'provisional codemap' || { echo "FAIL: no provisional-codemap NOTE (db-build not taken)"; echo "$jn"; exit 1; }
printf '%s' "$jn" | grep -q 'HB-CODE-DEPLINT' || { echo "FAIL: no dep-lint report from the auto-built codemap"; echo "$jn"; exit 1; }
# (2) node ≡ python on the auto-built codemap
[ "$jn" = "$py" ] || { echo "FAIL: node != python on db-build"; printf 'NODE=%s\nPY=%s\n' "$jn" "$py"; exit 1; }

echo "REAL-DEPLINT-ACCEPT-OK (codegraph $(codegraph --version 2>/dev/null | head -1)): auto-built codemap from .codegraph, node ≡ python."
