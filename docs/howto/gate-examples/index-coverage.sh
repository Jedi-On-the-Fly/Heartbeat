#!/usr/bin/env bash
# Proof (anti-drift, the T116 pattern generalized): the how-to index and the dev-tests T-table are
# DERIVED-consistent with reality — every docs/howto/*.md guide is linked in howto-list.md, and every
# `grp "Tnn` group in run-tests.sh appears in the dev-tests.md table. A new guide or suite group that
# ships without a doc entry turns this RED. Prints INDEX-COVERAGE-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
missing=0
for f in "$ROOT"/docs/howto/*.md; do
  b="$(basename "$f")"; case "$b" in README.md|howto-list.md) continue;; esac
  grep -Fq "($b)" "$ROOT/docs/howto/howto-list.md" || { echo "  unlisted guide: $b"; missing=1; }
done
for t in $(grep -oE 'grp "T[0-9]+' "$ROOT/tests/run-tests.sh" | grep -oE 'T[0-9]+' | sort -u); do
  grep -qE "\| ${t} " "$ROOT/docs/dev-tests.md" || { echo "  suite group ${t} missing from dev-tests.md table"; missing=1; }
done
[ "$missing" = 0 ] || { echo "index/table drifted from source"; exit 1; }
echo "INDEX-COVERAGE-OK"
