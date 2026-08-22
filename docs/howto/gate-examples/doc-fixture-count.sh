#!/usr/bin/env bash
# Proof (H3/H4): the audit-fixture count stated in the docs equals the number parity.sh actually iterates
# (derived, not hardcoded). Prints DOC-FIXTURE-COUNT-OK. Fails today (docs say 4, parity uses 5).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fail(){ echo "FAIL: $1"; exit 1; }
# n = number of audit fixtures parity.sh iterates (its `for f in ...` audit loop)
n="$(grep -oE 'for f in [a-z_-]+( [a-z_-]+)*' "$ROOT/tests/parity.sh" | head -1 | sed 's/for f in //' | wc -w)"
[ "$n" -ge 1 ] || fail "could not derive parity.sh audit-fixture count"
for d in "$ROOT/planning/parity-notes.md" "$ROOT/docs/dev-tests.md"; do
  # the doc must state the correct count, and must NOT state a different one for 'fixtures'
  grep -qE "\b$n\b.{0,20}fixtures|on $n fixtures|$n audit fixtures" "$d" || fail "$(basename "$d") does not state $n audit fixtures"
  wrong="$(grep -oE '\b[0-9]+\b (audit )?fixtures|on [0-9]+ fixtures' "$d" | grep -oE '[0-9]+' | grep -vx "$n" | head -1 || true)"
  [ -z "$wrong" ] || fail "$(basename "$d") states $wrong fixtures but parity.sh uses $n"
done
# enumeration teeth: every audit fixture parity.sh iterates is named in dev-tests.md (not just the count)
for fx in $(grep -oE 'for f in [a-z_ -]+' "$ROOT/tests/parity.sh" | head -1 | sed 's/for f in //'); do
  grep -q "$fx" "$ROOT/docs/dev-tests.md" || fail "dev-tests.md enumeration omits the '$fx' audit fixture"
done
echo "DOC-FIXTURE-COUNT-OK (n=$n)"
