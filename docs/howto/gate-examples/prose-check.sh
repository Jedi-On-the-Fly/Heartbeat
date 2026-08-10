#!/usr/bin/env bash
# Integrity checker for prose how-tos. Prose can't carry a mechanism proof, but it has
# verifiable properties — and a doc that rots or points at a command that doesn't exist is a
# real defect. For each doc arg this asserts: substantive (>= 15 non-blank lines), no
# placeholder (TODO/TBD/FIXME/'fill in'/lorem ipsum), every relative markdown link resolves
# (relative to the doc's dir), and every backticked `hb <sub>` names a REAL subcommand derived
# from py/src/heartbeat/cli.py. Prints PROSE-OK:<file> per doc and ALL-PROSE-OK:<n> at the end.
# `--selftest` proves the checker: a good doc passes, and broken-link / placeholder / fake-command
# docs are each rejected -> PROSE-CHECK-SELFTEST-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CLI="$ROOT/py/src/heartbeat/cli.py"

# Real subcommands: add_parser("x") names + the start/done/fail/heartbeat loop. Derived, not hardcoded.
_subcommands(){
  { grep -oE 'add_parser\("[a-z-]+"' "$CLI" | grep -oE '"[a-z-]+"' | tr -d '"'
    printf '%s\n' start done fail heartbeat; } | sort -u
}
SUBS="$(_subcommands)"

# check_doc <file> -> 0 if the doc is clean; prints the first defect otherwise.
check_doc(){
  local f="$1" dir; dir="$(cd "$(dirname "$f")" && pwd)"
  [ -f "$f" ] || { echo "  missing: $f"; return 1; }
  [ "$(grep -cvE '^[[:space:]]*$' "$f")" -ge 15 ] || { echo "  too thin: $f"; return 1; }
  # placeholder MARKERS only — a real "TODO:" / standalone TODO / stock filler, not the word
  # TODO used as prose or inside `code` (strip inline-code spans first to avoid false alarms).
  if sed 's/`[^`]*`//g' "$f" | grep -qiE '(TODO|TBD|FIXME):|\b(fill in|lorem ipsum)\b|^[[:space:]]*(TODO|TBD|FIXME)[[:space:]]*$'; then echo "  placeholder in: $f"; return 1; fi
  # relative links resolve
  local t base
  grep -oE '\]\([^)]+\)' "$f" | sed -E 's/^\]\(//; s/\)$//' | while read -r t; do
    case "$t" in http*|\#*|mailto:*) continue;; esac
    base="${t%%#*}"; [ -z "$base" ] && continue
    [ -e "$dir/$base" ] || { echo "  broken link in $f: $base"; exit 3; }
  done || return 1
  # every backticked `hb <sub>` is a real subcommand
  local sub
  grep -oE '`hb [a-z-]+' "$f" | sed -E 's/^`hb //' | sort -u | while read -r sub; do
    printf '%s\n' "$SUBS" | grep -qx "$sub" || { echo "  unknown hb command in $f: hb $sub"; exit 3; }
  done || return 1
  return 0
}

if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  body(){ for i in $(seq 1 20); do echo "Line $i of substantive content about gates and phases."; done; }
  # good doc: substantive, a resolving link to a real sibling, real commands
  : > "$d/sibling.md"
  { body; echo "See [sibling](sibling.md). Run \`hb init\`, then \`hb exec\` and \`hb gate\`."; } > "$d/good.md"
  check_doc "$d/good.md" >/dev/null || { echo "SELFTEST FAIL: a good doc was rejected"; exit 1; }
  # good: TODO used as prose / inside `code` is NOT a placeholder marker (regression guard)
  { body; echo "A plan is a \`TODO\` list — you mention a TODO, a spec; that is not a placeholder."; } > "$d/good_todo_prose.md"
  check_doc "$d/good_todo_prose.md" >/dev/null || { echo "SELFTEST FAIL: TODO-as-prose was wrongly rejected"; exit 1; }
  # bad: broken link
  { body; echo "See [missing](does-not-exist.md)."; } > "$d/bad_link.md"
  check_doc "$d/bad_link.md" >/dev/null && { echo "SELFTEST FAIL: a broken link was accepted"; exit 1; }
  # bad: placeholder
  { body; echo "TODO: write this section."; } > "$d/bad_todo.md"
  check_doc "$d/bad_todo.md" >/dev/null && { echo "SELFTEST FAIL: a placeholder was accepted"; exit 1; }
  # bad: fake command
  { body; echo "Run \`hb frobnicate\` to win."; } > "$d/bad_cmd.md"
  check_doc "$d/bad_cmd.md" >/dev/null && { echo "SELFTEST FAIL: a fake hb command was accepted"; exit 1; }
  echo "PROSE-CHECK-SELFTEST-OK: good doc passes; broken-link, placeholder, and fake-command docs rejected."
  exit 0
fi

[ "$#" -ge 1 ] || { echo "usage: prose-check.sh <doc.md> [more.md ...] | --selftest"; exit 2; }
n=0
for f in "$@"; do
  if check_doc "$f"; then echo "PROSE-OK:$(basename "$f")"; n=$((n + 1)); else echo "PROSE-FAIL:$f"; exit 1; fi
done
echo "ALL-PROSE-OK:$n"
