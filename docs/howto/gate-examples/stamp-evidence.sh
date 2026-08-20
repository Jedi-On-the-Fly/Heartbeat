#!/usr/bin/env bash
# Proof: `stamp-evidence` records HONEST sha256s — for each source it computes the sha of the STORED
# file bytes and stamps it into evidence.json. That recorded sha is what gives `ground-check` its teeth:
# it re-derives the sha and flags STALE if the source was edited after stamping. So a correct stamp
# makes ground-check report GROUNDED with no STALE; a bogus/constant sha (or a later edit) makes it
# STALE. node ≡ python produce the SAME stamped map. Prints STAMP-EVIDENCE-OK. Fails before
# stamp-evidence.js exists (spec-first). Deterministic — no network.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
SE="$ROOT/plugin/adapters/research/stamp-evidence.js"
GC="$ROOT/plugin/adapters/research/ground-check.js"
FX="$ROOT/plugin/adapters/research/fixtures/unstamped"

# the input source is shaless (nothing recorded to verify against yet)
grep -q 'sha256' "$FX/evidence.json" && { echo "FAIL: fixture should start shaless"; exit 1; }

stamped="$(node "$SE" "$FX/evidence.json" "$FX/sources")"
# a real sha was stamped for s1 (64 hex chars), not empty / not a constant of zeros
printf '%s' "$stamped" | grep -qE '"sha256"[[:space:]]*:[[:space:]]*"[0-9a-f]{64}"' || { echo "FAIL: no 64-hex sha stamped"; echo "$stamped"; exit 1; }
printf '%s' "$stamped" | grep -q '0000000000000000000000000000000000000000000000000000000000000000' && { echo "FAIL: stamped a constant zero sha"; exit 1; }

# the stamped sha is HONEST: ground-check re-derives it and reports GROUNDED with no STALE / no issues
gc="$(node "$GC" <(printf '%s' "$stamped") "$FX/sources")"
printf '%s' "$gc" | grep -q 'grounded=1' || { echo "FAIL: stamped map not GROUNDED"; echo "$gc"; exit 1; }
printf '%s' "$gc" | grep -q 'issues=0'   || { echo "FAIL: stamped map has issues"; echo "$gc"; exit 1; }
printf '%s' "$gc" | grep -q 'STALE'      && { echo "FAIL: honest stamp should not be STALE"; echo "$gc"; exit 1; }

# TEETH — the recorded sha actually detects a later edit: tamper a COPY, ground-check must go STALE
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp -R "$FX/sources" "$tmp/sources"
printf '%s' "$stamped" > "$tmp/evidence.json"
printf 'TAMPERED\n' >> "$tmp/sources/s1.txt"
node "$GC" "$tmp/evidence.json" "$tmp/sources" | grep -q 'STALE' || { echo "FAIL: recorded sha did not catch a later edit (STALE)"; exit 1; }

# node ≡ python produce the SAME stamped map (parsed-equal — canonicalized, not byte-compared)
canon() { python3 -c "import sys,json;print(json.dumps(json.load(sys.stdin),sort_keys=True,ensure_ascii=True))"; }
jn="$(printf '%s' "$stamped" | canon)"
pystamp="$(PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.research.stamp_evidence "$FX/evidence.json" "$FX/sources" | canon)"
[ "$jn" = "$pystamp" ] || { echo "FAIL: node vs python stamped map differs"; printf 'NODE=%s\n----\nPY=%s\n' "$jn" "$pystamp"; exit 1; }

echo "STAMP-EVIDENCE-OK"
