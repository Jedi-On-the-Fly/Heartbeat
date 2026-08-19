#!/usr/bin/env bash
# Proof: `deplint-accept` is the plan-acceptance wrapper around dep-lint. It RESOLVES the codemap
# conditionally and DELEGATES to the real deplint (identical report), advisory by default, --strict
# blocks, and it SKIPS cleanly when there is no codemap and no CodeGraph index. Prints
# CODE-DEPLINT-ACCEPT-OK. Fails before deplint-accept.js exists (spec-first).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
ACC="$ROOT/plugin/adapters/code/deplint-accept.js"
FX="$ROOT/plugin/adapters/code/fixtures"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# (1) codemap.json present in the dir -> runs deplint, delegated report is BYTE-IDENTICAL to deplint
mkdir -p "$tmp/hit"; cp "$FX/missing.codemap.json" "$tmp/hit/codemap.json"
acc="$(node "$ACC" --dir "$tmp/hit" --dag "$FX/missing.dag.json")"
direct="$(node "$ROOT/plugin/adapters/code/deplint.js" "$FX/missing.dag.json" "$FX/missing.codemap.json")"
[ "$acc" = "$direct" ] || { echo "FAIL: accept report != direct deplint (delegation drift)"; printf 'ACC=%s\nDIR=%s\n' "$acc" "$direct"; exit 1; }
echo "$acc" | grep -q 'HB-CODE-DEPLINT: missing=1' || { echo "FAIL: no deplint header"; exit 1; }
echo "$acc" | grep -q 'MISSING: TA should require TB' || { echo "FAIL: missing finding not surfaced"; exit 1; }

# (2) advisory by default -> exit 0 even with a finding
node "$ACC" --dir "$tmp/hit" --dag "$FX/missing.dag.json" >/dev/null || { echo "FAIL: advisory run should exit 0"; exit 1; }
# (3) --strict -> nonzero exit on a MISSING finding
if node "$ACC" --dir "$tmp/hit" --dag "$FX/missing.dag.json" --strict >/dev/null; then echo "FAIL: --strict should block (nonzero) on a finding"; exit 1; fi

# (4) no codemap.json and no .codegraph -> clean SKIP, exit 0
mkdir -p "$tmp/skip"
skip="$(node "$ACC" --dir "$tmp/skip" --dag "$FX/missing.dag.json")"
echo "$skip" | grep -q 'DEPLINT-ACCEPT-SKIP' || { echo "FAIL: empty dir should skip"; exit 1; }
node "$ACC" --dir "$tmp/skip" --dag "$FX/missing.dag.json" >/dev/null || { echo "FAIL: skip should exit 0"; exit 1; }

echo "CODE-DEPLINT-ACCEPT-OK"
