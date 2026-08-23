#!/usr/bin/env bash
# Proof (VD): the docs reflect the CURRENT code after the critical-fixes + critical-fixes-2 waves. Its teeth
# come from POSITIVE current-state assertions that are FALSE until the vd3 sweep runs (grep-for-absence
# alone is weak — it's already true and paraphrase-defeatable), plus NEGATIVE regression guards.
# Prints DOCS-CURRENT-OK. --selftest proves it goes RED on a planted stale path AND on a missing positive.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fail(){ echo "FAIL: $1"; exit 1; }

DP="$ROOT/docs/dev-python.md"; DT="$ROOT/docs/dev-tests.md"

check_all(){
  local root="$1"
  # (a) POSITIVE — dev docs describe mechanisms the sweep must add (each FALSE before vd3):
  grep -q 'accept_review' "$root/docs/dev-python.md" && grep -q 'review_policy' "$root/docs/dev-python.md" \
    || { echo "MISSING-POSITIVE: dev-python.md must describe review_policy.accept_review (single review-acceptance source)"; return 1; }
  grep -q 'GROUPS-SKIPPED' "$root/docs/dev-tests.md" \
    || { echo "MISSING-POSITIVE: dev-tests.md must describe the GROUPS-SKIPPED coverage-floor honesty marker"; return 1; }
  # (b) NEGATIVE regression guards — the moved fixtures left no stale path (outside historical reviews/):
  local stale
  # scan docs + code, not the historical plan files (*.dag.json describe the move in past tense) or
  # the preserved refutation artifacts (reviews/) or this proof itself.
  stale="$(grep -rIl -e 'planning/audit-fixtures' -e 'planning/parity-fixtures' "$root" \
            --exclude-dir=.git --exclude-dir=reviews --exclude='*.dag.json' --exclude='docs-currency.sh' 2>/dev/null || true)"
  [ -z "$stale" ] || { echo "STALE-PATH: moved-fixture path still referenced in: $stale"; return 1; }
  # review acceptance is single-sourced: policy module defines it; the callers don't re-enter cli.main
  grep -q 'def accept_review' "$root/py/src/heartbeat/review_policy.py" \
    || { echo "MISSING: review_policy.accept_review not defined"; return 1; }
  grep -qE 'cli\.main\(\[.review' "$root/py/src/heartbeat/executor.py" "$root/py/src/heartbeat/mcp_server.py" \
    && { echo "STALE-CODE: executor/mcp still scrape cli.main([\"review\"...])"; return 1; } || true
  # (c) STATUS carries a v1.28 entry:
  grep -qE 'v?1\.28' "$root/STATUS.md" || { echo "MISSING: STATUS.md has no v1.28 entry"; return 1; }
  # (d) plugin.json version == marketplace version (consistency):
  python3 - "$root" <<'PY' || return 1
import json, sys
r = sys.argv[1]
p = json.load(open(f"{r}/plugin/.claude-plugin/plugin.json"))["version"]
mk = json.load(open(f"{r}/.claude-plugin/marketplace.json"))
m = [x["version"] for x in mk["plugins"] if x["name"] == "heartbeat"][0]
assert p == m, f"plugin {p} != marketplace {m}"
PY
  return 0
}

if [ "${1:-}" = "--selftest" ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  # a minimal mirror that currently PASSES, then plant faults and require RED
  mkdir -p "$tmp/docs" "$tmp/py/src/heartbeat" "$tmp/plugin/.claude-plugin" "$tmp/.claude-plugin"
  echo "uses review_policy.accept_review as the single source" > "$tmp/docs/dev-python.md"
  echo "emits GROUPS-SKIPPED for the coverage floor" > "$tmp/docs/dev-tests.md"
  echo "def accept_review(): pass" > "$tmp/py/src/heartbeat/review_policy.py"
  echo "# clean" > "$tmp/py/src/heartbeat/executor.py"; echo "# clean" > "$tmp/py/src/heartbeat/mcp_server.py"
  echo "v1.28 shipped" > "$tmp/STATUS.md"
  echo '{"version":"1.28.0"}' > "$tmp/plugin/.claude-plugin/plugin.json"
  echo '{"plugins":[{"name":"heartbeat","version":"1.28.0"}]}' > "$tmp/.claude-plugin/marketplace.json"
  check_all "$tmp" >/dev/null 2>&1 || fail "selftest baseline should pass"
  # fault 1: planted stale path
  echo "see planning/audit-fixtures/hollow.json" >> "$tmp/docs/dev-tests.md"
  check_all "$tmp" >/dev/null 2>&1 && fail "selftest did NOT catch a planted stale audit-fixtures path" || true
  # fault 2: missing positive token
  echo "emits GROUPS-SKIPPED for the coverage floor" > "$tmp/docs/dev-tests.md"   # reset fault 1
  echo "no policy module described here" > "$tmp/docs/dev-python.md"              # drop the positive
  check_all "$tmp" >/dev/null 2>&1 && fail "selftest did NOT catch a missing positive mechanism token" || true
  echo "SELFTEST-OK: docs-currency goes RED on a planted stale path AND on a missing positive token"
  exit 0
fi

out="$(check_all "$ROOT")" || fail "${out:-docs-currency check failed}"
echo "DOCS-CURRENT-OK"
