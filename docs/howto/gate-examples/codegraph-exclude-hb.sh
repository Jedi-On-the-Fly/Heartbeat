#!/usr/bin/env bash
# Proof: the exclude helper idempotently makes a project's codegraph.json exclude `.hb/` (so CodeGraph
# does not index HeartBeat's own scaffold), PRESERVING any existing config, node ≡ python. Prints
# EXCLUDE-HB-OK. Fails before the helper exists (spec-first). Deterministic — no CodeGraph needed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
NHELP="$ROOT/plugin/adapters/code/codegraph-exclude-hb.js"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# (1) fresh root: helper creates codegraph.json with `.hb/` in exclude
mkdir -p "$tmp/a"
node "$NHELP" "$tmp/a"
python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); sys.exit(0 if ".hb/" in c.get("exclude",[]) else 1)' "$tmp/a/codegraph.json" \
  || { echo "FAIL: .hb/ not added to exclude"; cat "$tmp/a/codegraph.json"; exit 1; }

# (2) idempotent: running again does not duplicate `.hb/`
node "$NHELP" "$tmp/a"
python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); e=c.get("exclude",[]); sys.exit(0 if e.count(".hb/")==1 else 1)' "$tmp/a/codegraph.json" \
  || { echo "FAIL: .hb/ duplicated on re-run (not idempotent)"; cat "$tmp/a/codegraph.json"; exit 1; }

# (3) preserves an existing config (include stays, exclude gains .hb/)
mkdir -p "$tmp/b"; printf '{\n  "include": ["src/"]\n}\n' > "$tmp/b/codegraph.json"
node "$NHELP" "$tmp/b"
python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); sys.exit(0 if c.get("include")==["src/"] and ".hb/" in c.get("exclude",[]) else 1)' "$tmp/b/codegraph.json" \
  || { echo "FAIL: existing config not preserved"; cat "$tmp/b/codegraph.json"; exit 1; }

# (4) node ≡ python: same resulting codegraph.json on a fresh root
mkdir -p "$tmp/n" "$tmp/p"
node "$NHELP" "$tmp/n"
PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.code.codegraph_exclude_hb "$tmp/p"
diff "$tmp/n/codegraph.json" "$tmp/p/codegraph.json" >/dev/null \
  || { echo "FAIL: node vs python produce different codegraph.json"; diff "$tmp/n/codegraph.json" "$tmp/p/codegraph.json"; exit 1; }

echo "EXCLUDE-HB-OK"
