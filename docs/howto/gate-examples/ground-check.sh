#!/usr/bin/env bash
# Proof: `ground-check` verifies OFFLINE that every claim in an evidence map is GROUNDED in a stored
# source — a verbatim (whitespace-normalized) excerpt is present, the source's sha matches (STALE
# detection). It catches a FABRICATED-QUOTE (excerpt not in source), an UNGROUNDED claim (undeclared
# source / no excerpt), and a STALE source (edited after fetch). Advisory; --strict blocks. Prints
# GROUND-CHECK-OK. Fails before ground-check.js exists (spec-first). Deterministic — no network.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
GC="$ROOT/plugin/adapters/research/ground-check.js"
FX="$ROOT/plugin/adapters/research/fixtures/evidence"

out="$(node "$GC" "$FX/evidence.json" "$FX/sources")"
# exactly one grounded claim (c_ok, whose excerpt spans a line-wrap in the source → normalization works)
printf '%s' "$out" | grep -q 'grounded=1'                 || { echo "FAIL: expected grounded=1"; echo "$out"; exit 1; }
# a fabricated quote (excerpt not in source) is caught
printf '%s' "$out" | grep -qE 'FABRICATED-QUOTE:[^A-Za-z]*c_fab' || { echo "FAIL: c_fab not flagged FABRICATED-QUOTE"; echo "$out"; exit 1; }
# undeclared source + empty excerpt are UNGROUNDED
printf '%s' "$out" | grep -qE 'UNGROUNDED:[^A-Za-z]*c_nosrc' || { echo "FAIL: c_nosrc not UNGROUNDED"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -qE 'UNGROUNDED:[^A-Za-z]*c_empty' || { echo "FAIL: c_empty not UNGROUNDED"; echo "$out"; exit 1; }

# advisory exits 0; --strict exits nonzero (issues present)
node "$GC" "$FX/evidence.json" "$FX/sources" >/dev/null || { echo "FAIL: advisory run should exit 0"; exit 1; }
if node "$GC" "$FX/evidence.json" "$FX/sources" --strict >/dev/null; then echo "FAIL: --strict should block (nonzero) on issues"; exit 1; fi

# STALE: edit a COPY of the source so its sha no longer matches the recorded one
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp -R "$FX/." "$tmp/"
printf 'TAMPERED\n' >> "$tmp/sources/s1.txt"
node "$GC" "$tmp/evidence.json" "$tmp/sources" | grep -q 'STALE' || { echo "FAIL: an edited source (sha mismatch) was not reported STALE"; exit 1; }

echo "GROUND-CHECK-OK"
