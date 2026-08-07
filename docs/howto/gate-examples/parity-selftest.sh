#!/usr/bin/env bash
# Proof for "Keep the two runtimes in parity": prove tests/parity.sh actually FLAGS a
# node<->python divergence — not just that it passes when the two agree. We inject a real
# divergence into a throwaway copy of the Python runtime (a phantom lint error) and run the
# REAL parity harness against it via the HB_PY_SRC seam; the alarm must fire, on the lint
# surface. Prints PARITY-SELFTEST-CAUGHT only when it does.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }

# 1. Baseline: parity is green with the real runtime (nothing injected).
bash "$ROOT/tests/parity.sh" >/dev/null 2>&1 && base=ok || base=fail
[ "$base" = ok ] || { echo "FAIL: baseline parity is not green — cannot self-test"; exit 1; }

# 2. Copy the Python runtime and inject a deliberate divergence: make lint return an extra
#    error that the node linter does not. (A real behavioral change, not a crash.)
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp -r "$ROOT/py/src" "$tmp/src"
cat >> "$tmp/src/heartbeat/lint.py" <<'PY'

_orig_lint = lint
def lint(dag):
    r = dict(_orig_lint(dag))
    r["errors"] = list(r["errors"]) + ["ZZZ-parity-selftest-divergence"]
    return r
PY

# Sanity: the mutated runtime still runs and emits valid output (divergence, not breakage).
# Note lint exits non-zero here BECAUSE it found the injected error — that is the point —
# so check it produces parseable JSON, not its exit code.
PYTHONPATH="$tmp/src" python3 -m heartbeat.cli lint "$ROOT/planning/audit-fixtures/good.json" --json 2>/dev/null \
  | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null \
  || { echo "FAIL: mutated runtime does not emit valid output — that would trip parity for the wrong reason"; exit 1; }

# 3. Run the REAL parity harness against the mutated Python. The alarm must fire (non-zero)
#    and name the diverging surface (lint).
out="$(HB_PY_SRC="$tmp/src" bash "$ROOT/tests/parity.sh" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "PARITY-SELFTEST-ESCAPED: parity.sh did NOT catch an injected divergence"; exit 1
fi
printf '%s' "$out" | grep -q '✗ lint' || {
  echo "PARITY-SELFTEST-ESCAPED: parity failed but not on the injected (lint) surface"; exit 1; }

echo "PARITY-SELFTEST-CAUGHT: parity.sh flags an injected node<->python lint divergence (exit $rc)."
