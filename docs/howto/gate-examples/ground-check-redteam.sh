#!/usr/bin/env bash
# Red-team proof: a corpus that plants every MECHANICAL failure mode ground-check can catch
# (FABRICATED-QUOTE / UNGROUNDED×2 / MISSING-SOURCE / STALE) PLUS two GROUNDED-BUT-WRONG claims it
# cannot — c_drift (a real excerpt whose paraphrase overreaches) and c_context (a real excerpt from a
# non-primary source, quoted out of context). The gate must catch all the mechanical ones and stay
# SILENT on the two semantic ones (they report `grounded`): grounding is verified, truth is not.
# node ≡ python on the red-team corpus. Prints `RED-TEAM-OK grounded=3 issues=5`.
# Teeth: it characterizes existing ground-check — a regression that over/under-flags, or that starts
# judging truth, turns it RED. Deterministic — no network.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
GC="$ROOT/plugin/adapters/research/ground-check.js"
FX="$ROOT/plugin/adapters/research/fixtures/redteam"

out="$(node "$GC" "$FX/evidence.json" "$FX/sources")"

# exact tally: 3 grounded (c_ok, c_drift, c_context), 5 issues (the mechanical modes)
printf '%s' "$out" | grep -q 'grounded=3 issues=5' || { echo "FAIL: expected grounded=3 issues=5"; echo "$out"; exit 1; }

# every mechanical failure mode is classified correctly
printf '%s' "$out" | grep -qE 'FABRICATED-QUOTE:[[:space:]]*c_fab'  || { echo "FAIL: c_fab not FABRICATED-QUOTE";   echo "$out"; exit 1; }
printf '%s' "$out" | grep -qE 'UNGROUNDED:[[:space:]]*c_nosrc'      || { echo "FAIL: c_nosrc not UNGROUNDED";       echo "$out"; exit 1; }
printf '%s' "$out" | grep -qE 'UNGROUNDED:[[:space:]]*c_noex'       || { echo "FAIL: c_noex not UNGROUNDED";        echo "$out"; exit 1; }
printf '%s' "$out" | grep -qE 'MISSING-SOURCE:[[:space:]]*c_missing'|| { echo "FAIL: c_missing not MISSING-SOURCE";  echo "$out"; exit 1; }
printf '%s' "$out" | grep -qE 'STALE:[[:space:]]*c_stale'          || { echo "FAIL: c_stale not STALE";            echo "$out"; exit 1; }

# THE BOUNDARY: the two grounded-but-wrong claims are NOT flagged — the gate is silent on truth.
printf '%s' "$out" | grep -qE 'c_drift|c_context' && { echo "FAIL: a grounded-but-wrong claim was flagged (gate must stay silent on truth)"; echo "$out"; exit 1; }

# c_stale proves sha-before-excerpt: its excerpt IS present, yet STALE fires first (recorded sha wrong).
printf '%s' "$out" | grep -qE 'FABRICATED-QUOTE:[[:space:]]*c_stale' && { echo "FAIL: c_stale should be STALE, not FABRICATED (sha checked before excerpt)"; exit 1; }

# node ≡ python on the red-team corpus
py="$(PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.research.ground_check "$FX/evidence.json" "$FX/sources")"
[ "$out" = "$py" ] || { echo "FAIL: node vs python differ on the red-team corpus"; printf 'NODE=%s\n----\nPY=%s\n' "$out" "$py"; exit 1; }

echo "RED-TEAM-OK grounded=3 issues=5"
