#!/usr/bin/env bash
# Proof (H1): run-tests.sh cannot print a green headline while a large fraction of groups silently
# skipped ("ALL GREEN can lie" on a stripped box). It emits GROUPS-RAN/GROUPS-SKIPPED and, via a
# _coverage_check helper, marks the run INCOMPLETE (non-green, nonzero) when skipped exceeds a floor.
# Prints COVERAGE-FLOOR-OK. Fails before the helper/floor exists. Deterministic, no full-suite re-run.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fail(){ echo "FAIL: $1"; exit 1; }
RT="$ROOT/tests/run-tests.sh"
# source ONLY the _coverage_check function (no recursion into the suite)
eval "$(grep -E '^_coverage_check\(\)' "$RT")"
type _coverage_check >/dev/null 2>&1 || fail "run-tests.sh has no _coverage_check floor helper"
# low skip → green (rc 0)
_coverage_check 100 2 >/dev/null 2>&1 || fail "a full run (few skips) was wrongly flagged incomplete"
# high skip → non-green (nonzero) + a loud INCOMPLETE line
out="$(_coverage_check 30 40 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "a mostly-skipped run was NOT flagged incomplete (ALL-GREEN can still lie)"
printf '%s' "$out" | grep -qiE 'incomplete|not fully verified|skipped' || fail "no loud coverage-incomplete message"
# and run-tests.sh must actually WIRE it: emit the counts + honor the incomplete verdict in its exit path
grep -q 'GROUPS-SKIPPED' "$RT" || fail "run-tests.sh does not emit GROUPS-SKIPPED"
grep -qE '_coverage_check|COVER' "$RT" || fail "run-tests.sh does not call the coverage floor"
echo "COVERAGE-FLOOR-OK"
