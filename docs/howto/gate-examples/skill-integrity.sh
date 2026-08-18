#!/usr/bin/env bash
# Every domain adapter under plugin/adapters/ must SHIP A SKILL: a SKILL.md under plugin/skills/ that
# DECLARES it with a `HB-ADAPTER: <domain>` marker (an anchored declaration, NOT a loose path mention
# — a skill that merely references another adapter's path does not count) AND names at least one
# gate-examples/<name>.sh proof, and every named proof must EXIST and be WIRED (its basename appears
# in tests/run-tests.sh). Per-adapter — one adapter's proofs do not "cover" another. Prints
# SKILL-INTEGRITY-OK. `--selftest` proves the teeth (missing-skill, unwired-proof, and no leakage).
#   usage: skill-integrity.sh [<adaptersDir> <skillsDir> <runTests> <gateExamplesDir>]   (defaults: repo)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# audit <adaptersDir> <skillsDir> <runTests> <gateExamplesDir>
#   stdout: "<domains> <proofs> <findings>"   stderr: one FINDING line per problem
audit() {
  local ad="$1" sd="$2" rt="$3" gx="$4" domains=0 proofs=0 findings=0 d dom skills sk pr base named
  for d in "$ad"/*/; do
    [ -d "$d" ] || continue
    dom="$(basename "$d")"; domains=$((domains + 1))
    # a skill is FOR this adapter only if it DECLARES it (anchored) — a path mention does not count,
    # and 'code' must not match 'codeXYZ'
    pat='HB-ADAPTER:[[:space:]]*'"$dom"'([^A-Za-z0-9_-]|$)'
    skills="$(grep -rlE "$pat" "$sd" 2>/dev/null || true)"
    if [ -z "$skills" ]; then echo "  FINDING: no skill for adapter $dom" >&2; findings=$((findings + 1)); continue; fi
    named=0
    for sk in $skills; do
      for pr in $(grep -oE 'gate-examples/[a-z0-9_-]+\.sh' "$sk" | sort -u); do
        named=$((named + 1)); proofs=$((proofs + 1)); base="$(basename "$pr")"
        [ -f "$gx/$base" ]     || { echo "  FINDING: proof missing: $pr (adapter $dom)" >&2;   findings=$((findings + 1)); }
        grep -qF "$base" "$rt" || { echo "  FINDING: proof not wired: $pr (adapter $dom)" >&2; findings=$((findings + 1)); }
      done
    done
    [ "$named" -gt 0 ] || { echo "  FINDING: adapter $dom skill names no proof" >&2; findings=$((findings + 1)); }
  done
  echo "$domains $proofs $findings"
}

if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  mkdir -p "$d/adapters/good" "$d/adapters/goo" "$d/adapters/noskill" "$d/adapters/badproof" \
           "$d/adapters/leaked" "$d/skills/g" "$d/skills/b" "$d/gx"
  printf 'good.sh is wired here\n' > "$d/rt.sh"                                   # run-tests naming good.sh
  : > "$d/gx/good.sh"; : > "$d/gx/unwired.sh"                                     # both proofs exist...
  # good skill: DECLARES good, names a wired proof, and merely PATH-mentions adapters/leaked
  printf 'HB-ADAPTER: good\nuses gate-examples/good.sh and references plugin/adapters/leaked/x.js\n' > "$d/skills/g/SKILL.md"
  # bad skill: DECLARES badproof, names an UNWIRED proof
  printf 'HB-ADAPTER: badproof\nuses gate-examples/unwired.sh\n' > "$d/skills/b/SKILL.md"
  # noskill: nothing declares it. goo: only 'good' is declared (substring must NOT match). leaked:
  # only path-mentioned by the good skill, never DECLARED.
  audit "$d/adapters" "$d/skills" "$d/rt.sh" "$d/gx" >"$d/counts" 2>"$d/err" || true
  grep -q 'no skill for adapter noskill' "$d/err" || { echo "SELFTEST FAIL: missing-skill not caught"; exit 1; }
  grep -q 'no skill for adapter goo'     "$d/err" || { echo "SELFTEST FAIL: substring leak (goo matched good)"; exit 1; }
  grep -q 'no skill for adapter leaked'  "$d/err" || { echo "SELFTEST FAIL: a path mention wrongly covered an adapter (leakage)"; exit 1; }
  grep -q 'proof not wired'              "$d/err" || { echo "SELFTEST FAIL: unwired-proof not caught"; exit 1; }
  [ "$(awk '{print $3}' "$d/counts")" -gt 0 ]     || { echo "SELFTEST FAIL: a bad tree was not flagged"; exit 1; }
  rm -rf "$d/adapters/goo" "$d/adapters/noskill" "$d/adapters/badproof" "$d/adapters/leaked" "$d/skills/b"
  audit "$d/adapters" "$d/skills" "$d/rt.sh" "$d/gx" >"$d/counts2" 2>/dev/null   # leave only good adapter+skill
  [ "$(awk '{print $3}' "$d/counts2")" -eq 0 ]     || { echo "SELFTEST FAIL: a good tree was flagged"; exit 1; }
  echo "SKILL-INTEGRITY-SELFTEST-OK: missing-skill, substring-leak, path-leakage, and unwired-proof all caught; a good tree passes."
  exit 0
fi

AD="${1:-$ROOT/plugin/adapters}"; SD="${2:-$ROOT/plugin/skills}"
RT="${3:-$ROOT/tests/run-tests.sh}"; GX="${4:-$ROOT/docs/howto/gate-examples}"
errf="$(mktemp)"; trap 'rm -f "$errf"' EXIT
counts="$(audit "$AD" "$SD" "$RT" "$GX" 2>"$errf")"
domains="$(echo "$counts" | awk '{print $1}')"; proofs="$(echo "$counts" | awk '{print $2}')"; findings="$(echo "$counts" | awk '{print $3}')"
if [ "${domains:-0}" -lt 1 ] || [ "${findings:-1}" -ne 0 ]; then
  cat "$errf" >&2
  echo "SKILL-INTEGRITY: $domains adapter(s), $findings finding(s)"; exit 1
fi
echo "SKILL-INTEGRITY-OK: $domains adapters, $proofs wired proof reference(s), 0 findings."
