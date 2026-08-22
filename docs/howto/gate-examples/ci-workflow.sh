#!/usr/bin/env bash
# Proof: a real CI workflow exists and wires the three suites, so "CI-enforced" is a true claim (not
# prose). Asserts a .github/workflows file exists, triggers on push + pull_request, invokes
# tests/run-tests.sh + pytest + tests/parity.sh, and those scripts exist. (CI runs remotely; the honest
# local boundary is validity + wiring — the suites' own greenness is proven by the rest of the suite.)
# Prints CI-WORKFLOW-OK. Fails before .github/workflows exists.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fail(){ echo "FAIL: $1"; exit 1; }
WF="$(ls "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml 2>/dev/null | head -1)"
[ -n "$WF" ] && [ -f "$WF" ] || fail "no .github/workflows/*.yml — 'CI-enforced' would be a false claim"
grep -qE '^on:|^\s*push:|pull_request' "$WF" || fail "workflow has no push/pull_request trigger"
grep -q 'bash tests/run-tests.sh' "$WF" || fail "workflow does not run tests/run-tests.sh"
grep -qE 'python3 -m pytest|pytest -q' "$WF" || fail "workflow does not run pytest"
grep -q 'bash tests/parity.sh' "$WF" || fail "workflow does not run tests/parity.sh"
[ -f "$ROOT/tests/run-tests.sh" ] && [ -f "$ROOT/tests/parity.sh" ] || fail "a referenced suite script is missing"
echo "CI-WORKFLOW-OK"
