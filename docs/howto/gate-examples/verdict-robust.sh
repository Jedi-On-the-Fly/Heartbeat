#!/usr/bin/env bash
# Proof (C2): the python backends decide REFUTED/CLEAR from the reply's FINAL token via a shared helper,
# so prose that merely mentions the word "REFUTED" but ends CLEAR is NOT scored as a refutation (mirrors
# the node claude-exec.sh fix). Prints VERDICT-ROBUST-OK. Fails before the helper exists.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
python3 - <<'PY' || { echo "FAIL: verdict helper not robust"; exit 1; }
from heartbeat.backends import verdict_refuted as v
assert v("I looked hard; the instructions say end with REFUTED or CLEAR. CLEAR") is False
assert v("Found a hollow test — this is not done. REFUTED") is True
assert v("earlier I wrote CLEAR ... final verdict: REFUTED") is True
assert v("earlier I wrote REFUTED ... final verdict: CLEAR") is False
assert v("no verdict token here") is False
PY
# completeness: NO backend (in-process registry OR executor template) still decides by grep-anywhere
if grep -rqE '"REFUTED" in|grep -q .REFUTED.' "$ROOT/py/src/heartbeat/backends" "$ROOT/plugin/templates/executors"; then
  echo "FAIL: a backend still greps-anywhere for REFUTED (parity gap)"; exit 1
fi
echo "VERDICT-ROBUST-OK"
