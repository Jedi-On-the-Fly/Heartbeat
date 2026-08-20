#!/usr/bin/env bash
# Scale proof: on a LARGE, messy generated corpus (60 sources, 200 claims, unicode, line-wraps,
# multi-claim-per-source, 4 sections) the research adapter stays node ≡ python — the parity divergences
# a 3-claim fixture hides (encoding of non-ASCII bytes, sort order over many ids). Asserts:
#   • ground-check node ≡ python BYTE-identical, reporting grounded=160 issues=40
#   • research-context node ≡ python BYTE-identical for each of the 4 sections
#   • stamp-evidence node ≡ python produce the SAME map (canonicalized, since JSON serialization differs)
# The runs are wrapped in `timeout` as an anti-hang backstop (a runtime that deadlocks/loops fails the
# proof instead of blocking the suite) — a coarse ceiling, NOT a fine-grained perf-divergence check.
# Prints `SCALE-PARITY-OK sources=60 claims=200 grounded=160 issues=40`. Fails before the generator
# exists (spec-first). The generation (mktemp) lives HERE, in the proof — never in a gate criterion.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
GEN="$ROOT/plugin/adapters/research/fixtures/scale/gen.js"
GC="$ROOT/plugin/adapters/research/ground-check.js"
RC="$ROOT/plugin/adapters/research/research-context.js"
SE="$ROOT/plugin/adapters/research/stamp-evidence.js"
PP="$ROOT/py/src"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
node "$GEN" "$tmp"                       # writes $tmp/evidence.json + $tmp/sources/*.txt (deterministic)
EV="$tmp/evidence.json"; SRC="$tmp/sources"

# ground-check: node ≡ python byte-identical, honest counts, wrapped in timeout (anti-hang backstop)
jn="$(timeout 20 node "$GC" "$EV" "$SRC")"
py="$(timeout 20 env PYTHONPATH="$PP" python3 -m heartbeat.adapters.research.ground_check "$EV" "$SRC")"
[ "$jn" = "$py" ] || { echo "FAIL: ground-check node vs python differ at scale"; diff <(printf '%s' "$jn") <(printf '%s' "$py") | head; exit 1; }
printf '%s' "$jn" | grep -q 'grounded=160 issues=40' || { echo "FAIL: unexpected scale counts"; printf '%s\n' "$jn" | head -1; exit 1; }

# research-context: node ≡ python byte-identical for every section (unicode + many claims)
for sec in background method results discussion; do
  a="$(node "$RC" "$EV" "$sec")"
  b="$(PYTHONPATH="$PP" python3 -m heartbeat.adapters.research.research_context "$EV" "$sec")"
  [ "$a" = "$b" ] || { echo "FAIL: research-context node vs python differ for section $sec"; exit 1; }
done

# stamp-evidence: node ≡ python SAME map (canonicalized parsed-equal — JSON.stringify vs json.dumps differ)
canon() { python3 -c "import sys,json;print(json.dumps(json.load(sys.stdin),sort_keys=True,ensure_ascii=True))"; }
sjn="$(node "$SE" "$EV" "$SRC" | canon)"
spy="$(PYTHONPATH="$PP" python3 -m heartbeat.adapters.research.stamp_evidence "$EV" "$SRC" | canon)"
[ "$sjn" = "$spy" ] || { echo "FAIL: stamp-evidence node vs python map differ at scale"; exit 1; }

echo "SCALE-PARITY-OK sources=60 claims=200 grounded=160 issues=40"
