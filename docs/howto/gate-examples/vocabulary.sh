#!/usr/bin/env bash
# Proof: the vocabulary in docs/vocabulary.md is real, not aspirational.
#   (1) `hb pulse` is a true alias of `hb tick` (python): same decision on the same fresh project.
#   (2) `keepalive` refreshes a task lease on BOTH runtimes (python `hb keepalive`, node `hb.js keepalive`),
#       and the legacy spellings (`heartbeat` on both, `beat` on node) still work — nothing breaks.
#   (3) both runtimes title the rendered protocol "pulse protocol" (node ≡ python).
#   (4) README defines **pulse** before its first use of "tick", and every term in the vocabulary table
#       appears in README — the glossary and the front door agree.
# Prints VOCABULARY-OK. RED before the aliases / the definition exist.
# `--selftest` proves the checks load-bearing: an unknown alias is rejected, a README that uses "tick"
# before defining pulse is caught, a glossary term absent from README is caught. SELFTEST-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }
hb() { PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli "$@"; }
HBJS="$ROOT/plugin/templates/hb.js"

# ── README checks (pure functions of a file, so the selftest can feed them a bad one) ──
# first line that defines the term (bold **pulse**) must precede the first line using the word tick
readme_defines_pulse_first() {   # $1 = readme path
  local def use
  def="$(grep -n '\*\*pulse\*\*' "$1" | head -1 | cut -d: -f1)"
  use="$(grep -n -i '\btick' "$1" | head -1 | cut -d: -f1)"
  [ -n "$def" ] || return 1
  [ -z "$use" ] || [ "$def" -lt "$use" ]
}
# every `**term**` in the first column of the glossary table appears (case-insensitively) in the readme
glossary_terms_in_readme() {     # $1 = vocabulary.md, $2 = readme
  local t missing=0
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    grep -qi -- "$t" "$2" || { echo "  glossary term not in README: $t" >&2; missing=1; }
  done < <(grep -oE '^\| \*\*[^*]+\*\*' "$1" | sed -E 's/^\| \*\*//; s/\*\*$//')
  [ "$missing" = 0 ]
}

if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  # an unknown alias is rejected → the alias checks below discriminate
  hb pulsate --dir "$d" >/dev/null 2>&1 && fail "selftest: an unknown command was accepted (alias check not discriminating)"
  # a README that says tick before defining pulse is caught
  printf 'run a tick\n\nthe **pulse** is defined late\n' > "$d/bad.md"
  readme_defines_pulse_first "$d/bad.md" && fail "selftest: tick-before-pulse README not caught"
  printf 'no definition at all\n' > "$d/none.md"
  readme_defines_pulse_first "$d/none.md" && fail "selftest: README with no pulse definition not caught"
  # a glossary term missing from the README is caught
  printf '| **pulse** | x |\n| **zebrafish** | y |\n' > "$d/vocab.md"
  printf 'the **pulse**\n' > "$d/readme.md"
  glossary_terms_in_readme "$d/vocab.md" "$d/readme.md" 2>/dev/null && fail "selftest: missing glossary term not caught"
  echo "SELFTEST-OK"; exit 0
fi

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# (1) pulse ≡ tick — two fresh identical projects, one decision each, same decision
hb init "$work/a" >/dev/null 2>&1 || fail "hb init a"
hb init "$work/b" >/dev/null 2>&1 || fail "hb init b"
norm() { python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["wakeAgent"], d["data"]["reason"], d["data"].get("next_task",{}).get("id"), sorted(d["data"].keys()))'; }
t="$(hb tick  --dir "$work/a" | norm)" || fail "hb tick"
p="$(hb pulse --dir "$work/b" | norm)" || fail "hb pulse (alias missing?)"
[ "$t" = "$p" ] || fail "hb pulse ≠ hb tick on the same fresh project: [$t] vs [$p]"
echo "$p" | grep -q "next_task P0T1" || fail "unexpected first decision: $p"

# (2) keepalive refreshes a lease — python
hb start P0T1 --dir "$work/a" >/dev/null 2>&1 || fail "hb start"
lease="$work/a/.hb/leases/P0T1"; [ -d "$lease" ] || fail "no lease dir after start"
rm -f "$lease/beat"
hb keepalive P0T1 --dir "$work/a" >/dev/null 2>&1 || fail "hb keepalive (alias missing?)"
[ -f "$lease/beat" ] || fail "python keepalive did not refresh the lease"
rm -f "$lease/beat"
hb heartbeat P0T1 --dir "$work/a" >/dev/null 2>&1 || fail "legacy `hb heartbeat` broke"
[ -f "$lease/beat" ] || fail "legacy python heartbeat did not refresh the lease"

# (2) keepalive refreshes a lease — node (hb.js works on any .hb dir with a lease present)
mkdir -p "$work/n/.hb/leases/T1"
for spelling in keepalive heartbeat beat; do
  rm -f "$work/n/.hb/leases/T1/beat"
  HB_DIR="$work/n/.hb" node "$HBJS" "$spelling" T1 >/dev/null 2>&1 || fail "node hb.js $spelling failed"
  [ -f "$work/n/.hb/leases/T1/beat" ] || fail "node $spelling did not refresh the lease"
done

# (3) the rendered protocol is the pulse protocol on both runtimes
node "$HBJS" protocol --md | grep -q "pulse protocol" || fail "node protocol --md is not titled 'pulse protocol'"
hb protocol --md            | grep -q "pulse protocol" || fail "python protocol --md is not titled 'pulse protocol'"

# (4) the front door defines the word before using the legacy one, and carries every glossary term
readme_defines_pulse_first "$ROOT/README.md" || fail "README uses 'tick' before defining **pulse**"
glossary_terms_in_readme "$ROOT/docs/vocabulary.md" "$ROOT/README.md" || fail "glossary terms missing from README"

echo "VOCABULARY-OK"
