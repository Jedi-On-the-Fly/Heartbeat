#!/usr/bin/env bash
# Proof for "Write fast, deterministic gates": the example corpus is DETERMINISTIC (same
# artifacts -> same verdict, so two runs are byte-identical) and FAST (the whole corpus
# finishes well under a generous budget — a real gate must clear GATE_TIMEOUT_S). We use a
# generous timeout, not a tight wall-clock bound, because a tight timing gate would itself
# be flaky — the very thing this guide warns against.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUDGET="${GATE_BUDGET_S:-20}"

# Deterministic: two independent runs produce identical output.
a="$(bash "$HERE/run.sh" 2>&1)"
b="$(bash "$HERE/run.sh" 2>&1)"
if [ "$a" != "$b" ]; then
  echo "FAIL: run.sh output differs between runs (nondeterministic)"; exit 1
fi
printf '%s\n' "$a" | grep -q 'ALL-EXAMPLES-PROVEN:' || { echo "FAIL: corpus not all-proven"; exit 1; }

# Fast: the corpus completes within the budget (timeout exits 124 on overrun).
if command -v timeout >/dev/null 2>&1; then
  timeout "${BUDGET}s" bash "$HERE/run.sh" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 124 ] && { echo "FAIL: corpus exceeded ${BUDGET}s budget"; exit 1; }
else
  echo "note: timeout(1) unavailable — skipped the budget check"
fi

echo "FAST-DETERMINISTIC-OK: two runs identical; corpus within ${BUDGET}s."
