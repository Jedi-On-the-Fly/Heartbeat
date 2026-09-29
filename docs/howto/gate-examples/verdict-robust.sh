#!/usr/bin/env bash
# Proof (C2): the python backends decide REFUTED/CLEAR via a shared helper by one contract
# (py/tests/verdict_cases.json): the reply's last non-empty line is ONLY the verdict, and the line
# before it does not begin with one — so prose that merely mentions "REFUTED" is not a refutation, and
# anything else is no verdict (None → the backend returns an error, fail-closed; mirrors the node
# adapters). Prints VERDICT-ROBUST-OK. Fails before the helper exists.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
python3 - "$ROOT/py/tests/verdict_cases.json" <<'PY' || { echo "FAIL: verdict helper not robust"; exit 1; }
import json, sys
from heartbeat.backends import verdict_of as v
cases = json.load(open(sys.argv[1]))          # the contract: the last non-empty line is ONLY the verdict
# the original trap: prose that mentions REFUTED, then a CLEAR verdict line, is not a refutation
assert v("I looked hard; the instructions say end with REFUTED or CLEAR.\n\nCLEAR") is False
assert v("Found a hollow test — this is not done.\nREFUTED") is True
for want, key in ((True, "true"), (False, "false"), (None, "none")):
    for c in cases[key]:
        assert v(c) is want, (c, v(c), want)
PY
# completeness: NO backend (in-process registry OR executor template) still decides by grep-anywhere
if grep -rqE '"REFUTED" in|grep -q .REFUTED.' "$ROOT/py/src/heartbeat/backends" "$ROOT/plugin/templates/executors"; then
  echo "FAIL: a backend still greps-anywhere for REFUTED (parity gap)"; exit 1
fi
echo "VERDICT-ROBUST-OK"
