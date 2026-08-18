#!/usr/bin/env bash
# ON-DEMAND / harness-first — NOT in the gated suite (CodeGraph is not vendored). Proves the
# live-DB read of the code adapter against a REAL CodeGraph index: readCodegraphDb / read_codegraph_db
# must (1) read CodeGraph's actual schema (nodes.file_path, edges.source/target/kind — the columns
# renamed in CodeGraph 1.5.0), (2) keep every resolved dependency edge (calls/imports/extends/
# instantiates/…) while dropping structural containment, and (3) be node ≡ python. Skips cleanly
# when codegraph/sqlite3 are absent.
#   usage: bash tests/real-codegraph-map.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node     >/dev/null 2>&1 || { echo "SKIP: node absent"; exit 0; }
command -v python3  >/dev/null 2>&1 || { echo "SKIP: python3 absent"; exit 0; }
command -v sqlite3  >/dev/null 2>&1 || { echo "SKIP: sqlite3 absent"; exit 0; }
command -v codegraph >/dev/null 2>&1 || { echo "SKIP: codegraph CLI absent (harness-first)"; exit 0; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# Sample exercising four dependency kinds + structural containment:
#   main imports Dog (imports), main constructs Dog (instantiates), Dog extends Animal (extends),
#   Animal.describe calls Animal.speak (calls); files contain their symbols (contains, must drop).
mkdir -p "$tmp/pkg"
cat > "$tmp/pkg/base.py" <<'EOF'
from abc import ABC, abstractmethod

class Animal(ABC):
    @abstractmethod
    def speak(self): ...
    def describe(self):
        return self.speak()
EOF
cat > "$tmp/pkg/dog.py" <<'EOF'
from pkg.base import Animal

class Dog(Animal):
    def speak(self):
        return "woof"
EOF
cat > "$tmp/main.py" <<'EOF'
from pkg.dog import Dog

def make():
    d = Dog()
    return d.describe()
EOF

( cd "$tmp" && codegraph init . >/dev/null 2>&1 </dev/null ) || { echo "SKIP: codegraph init failed"; exit 0; }
DB="$tmp/.codegraph/codegraph.db"
[ -f "$DB" ] || { echo "SKIP: no codegraph.db produced"; exit 0; }

MAP_JS="$ROOT/plugin/adapters/code/codegraph-map.js"

# (1) both runtimes read the live DB without erroring (OLD SQL referenced dropped columns → threw)
jn="$(node "$MAP_JS" "$DB" --db)" || { echo "FAIL: node readCodegraphDb errored on a real CodeGraph DB"; exit 1; }
py="$(PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.code.codegraph_map "$DB" --db)" \
  || { echo "FAIL: python read_codegraph_db errored on a real CodeGraph DB"; exit 1; }

# (2) node ≡ python (edge set)
python3 -c '
import sys, json
a=json.loads(sys.argv[1]); b=json.loads(sys.argv[2])
sys.exit(0 if set(map(tuple,a.get("edges",[])))==set(map(tuple,b.get("edges",[]))) else 1)
' "$jn" "$py" || { echo "FAIL: node vs python edge sets differ"; printf 'NODE=%s\nPY=%s\n' "$jn" "$py"; exit 1; }

got_pairs() { node -e 'process.stdout.write(JSON.parse(process.argv[1]).edges.map(e=>e[0]+"|"+e[1]).join("\n"))' "$jn"; }

# (3) INDEPENDENT oracle: for each dependency kind, a representative resolved edge MUST survive.
#     The expected pair is read straight from CodeGraph by kind — NOT derived from the adapter's
#     own filter — so dropping any of these kinds fails the proof (this is what caught `instantiates`).
for kind in calls imports extends instantiates; do
  pair="$(sqlite3 -separator '|' "$DB" \
    "SELECT s.qualified_name, t.qualified_name FROM edges e JOIN nodes s ON e.source=s.id JOIN nodes t ON e.target=t.id WHERE e.kind='$kind' LIMIT 1;")"
  [ -n "$pair" ] || { echo "FAIL: sample produced no '$kind' edge (cannot prove it survives)"; exit 1; }
  got_pairs | grep -qxF "$pair" || { echo "FAIL: '$kind' dependency dropped: $pair"; echo "got:"; got_pairs; exit 1; }
done

# (4) structural containment MUST be dropped: a representative 'contains' pair must be absent.
cpair="$(sqlite3 -separator '|' "$DB" \
  "SELECT s.qualified_name, t.qualified_name FROM edges e JOIN nodes s ON e.source=s.id JOIN nodes t ON e.target=t.id WHERE e.kind='contains' AND NOT EXISTS (SELECT 1 FROM edges e2 WHERE e2.source=e.source AND e2.target=e.target AND e2.kind<>'contains') LIMIT 1;")"
[ -n "$cpair" ] || { echo "FAIL: sample produced no pure-'contains' edge to test the filter"; exit 1; }
got_pairs | grep -qxF "$cpair" && { echo "FAIL: structural 'contains' edge survived: $cpair"; exit 1; }

# (5) count matches every resolved non-containment edge (both endpoints known)
exp="$(sqlite3 "$DB" "SELECT count(*) FROM edges e JOIN nodes s ON e.source=s.id JOIN nodes t ON e.target=t.id WHERE e.kind<>'contains';")"
gotn="$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).edges.length))' "$jn")"
[ "$gotn" = "$exp" ] || { echo "FAIL: emitted $gotn dependency edges, DB holds $exp non-contains resolved edges"; exit 1; }

echo "REAL-CODEGRAPH-MAP-OK (codegraph $(codegraph --version 2>/dev/null | head -1)): live schema, calls/imports/extends/instantiates kept, contains dropped, node ≡ python."
