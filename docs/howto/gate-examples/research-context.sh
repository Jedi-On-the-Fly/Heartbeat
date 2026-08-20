#!/usr/bin/env bash
# Proof: `research-context` is the research Seam-2 provider — given an all-grounded evidence map and a
# section, it renders THAT section's claims (id + text + source url + verbatim excerpt) as the context
# block fed to the writer, and NOTHING from other sections. node ≡ python BYTE-identical. Prints
# RESEARCH-CONTEXT-OK. Fails before research-context.js exists (spec-first). Deterministic — no network.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
RC="$ROOT/plugin/adapters/research/research-context.js"
FX="$ROOT/plugin/adapters/research/fixtures/context/evidence.json"

out="$(node "$RC" "$FX" background)"
# both background claims, each with its text, source url, and » excerpt line
printf '%s' "$out" | grep -q 'Grounded evidence for background:' || { echo "FAIL: missing section header"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -q 'c_bg1: Water boils'   || { echo "FAIL: c_bg1 text missing"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -q 'c_bg2: Ice melts'     || { echo "FAIL: c_bg2 text missing"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -q 'source s1 https://example.org/thermo' || { echo "FAIL: source url missing"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -q '» water boils at 100 degrees Celsius at sea level' || { echo "FAIL: c_bg1 excerpt missing"; echo "$out"; exit 1; }
# the method-section claim must NOT leak into the background render
printf '%s' "$out" | grep -q 'METHOD-ONLY-EXCERPT' && { echo "FAIL: method-section claim leaked into background"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -q 'c_m1' && { echo "FAIL: c_m1 leaked into background"; echo "$out"; exit 1; }

# an empty / unknown section renders the explicit (none) marker
none="$(node "$RC" "$FX" nosuchsection)"
printf '%s' "$none" | grep -q '(none)' || { echo "FAIL: empty section should render (none)"; echo "$none"; exit 1; }

# node ≡ python, BYTE-identical
py="$(PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.adapters.research.research_context "$FX" background)"
[ "$out" = "$py" ] || { echo "FAIL: node vs python render differs"; printf 'NODE=%s\n----\nPY=%s\n' "$out" "$py"; exit 1; }

echo "RESEARCH-CONTEXT-OK"
