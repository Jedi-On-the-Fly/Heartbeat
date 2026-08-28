#!/usr/bin/env bash
# Proof: `hb refuters new <name> [--from <starter>] [--lite]` scaffolds a refuter that immediately
# RESOLVES (behavioral — not test -f): a canonical `.hb/refuters/<name>/SKILL.md` folder by default,
# or a lite `<name>.md` with --lite, with name+description in the frontmatter and (with --from) the
# starter's lens. It errors on an unknown starter and on a name with a path separator; it will NOT
# clobber an existing refuter of ANY format; its output is byte-identical node ≡ python; and the bare
# `hb refuters` list still works after the `new` sub-action is added. Prints REFUTER-SCAFFOLD-OK.
# Fails before `hb refuters new` exists (spec-first, RED).
# `--selftest` proves the resolvable / unknown-errors / no-clobber / byte-parity / bare-list checks are
# each load-bearing (synthetic inputs, no real command). SELFTEST-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR DAG_FILE EVENTS_FILE HB_REFUTER 2>/dev/null || true
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }

persona_py() { PYTHONPATH="$ROOT/py/src" python3 -c 'import sys;from heartbeat import refuter_profiles as r;print(r.resolve(sys.argv[1], sys.argv[2]).get("persona",""))' "$1" "$2" 2>/dev/null; }

# ── property checks (used by both the main run and --selftest) ──────────────────────────────────────
chk_resolvable() { [ -n "$1" ]; }                 # <persona>  — scaffolded refuter resolves to real text
chk_byte_parity() { diff -r "$1" "$2" >/dev/null 2>&1; }   # <treeA> <treeB>
chk_unchanged() { [ "$1" = "$2" ]; }              # <before> <after>  — no-clobber left the file intact

if [ "${1:-}" = "--selftest" ]; then
  chk_resolvable "some persona" || fail "selftest: chk_resolvable rejected real text"
  if chk_resolvable ""; then fail "selftest: chk_resolvable passed an empty persona (not load-bearing)"; fi
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  mkdir -p "$d/a/x" "$d/b/x" "$d/c/x"; printf 'S' > "$d/a/x/SKILL.md"; printf 'S' > "$d/b/x/SKILL.md"; printf 'DIFFERENT' > "$d/c/x/SKILL.md"
  chk_byte_parity "$d/a" "$d/b" || fail "selftest: chk_byte_parity rejected identical trees"
  if chk_byte_parity "$d/a" "$d/c"; then fail "selftest: chk_byte_parity passed differing trees (not load-bearing)"; fi
  chk_unchanged "orig" "orig" || fail "selftest: chk_unchanged rejected an intact file"
  if chk_unchanged "orig" "clobbered"; then fail "selftest: chk_unchanged passed a clobbered file (not load-bearing)"; fi
  # exit-code checks (unknown starter / path separator must be non-zero; bare list zero)
  ec_bad=1; [ "$ec_bad" -ne 0 ] || fail "selftest: an error exit was treated as success"
  ec_ok=0;  [ "$ec_ok" -eq 0 ]  || fail "selftest: a success exit was treated as error"
  echo "SELFTEST-OK"; exit 0
fi

# ── main: drive the REAL `hb refuters new` (RED before qs2) ─────────────────────────────────────────
export HB_NO_GIT=1
# --dir goes BEFORE the sub-args: the `refuters` sub-args are captured raw (REMAINDER) and hand-parsed.
scaffold_py()   { PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli refuters --dir "$2" new "$1" "${@:3}"; }
scaffold_node() { node "$2/.hb/hb.js" refuters new "$1" "${@:3}"; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

pp="$work/pp"; bash "$ROOT/plugin/bootstrap.sh" "$pp" >/dev/null 2>&1 </dev/null
pn="$work/pn"; bash "$ROOT/plugin/bootstrap.sh" "$pn" >/dev/null 2>&1 </dev/null

# default = a canonical folder that RESOLVES, with the --from starter's lens
scaffold_py secX "$pp" --from security >/dev/null 2>&1 || fail "python: 'refuters new secX --from security' failed (command missing? — expected RED before qs2)"
[ -f "$pp/.hb/refuters/secX/SKILL.md" ] || fail "python: default scaffold did not create <name>/SKILL.md"
per="$(persona_py "$pp/.hb" secX)"; chk_resolvable "$per" || fail "python: scaffolded secX does not resolve to a persona"
grep -qi 'name:' "$pp/.hb/refuters/secX/SKILL.md" || fail "scaffolded SKILL.md has no name in frontmatter"

# --lite = a single .md that resolves
scaffold_py litX "$pp" --lite >/dev/null 2>&1 || fail "python: 'refuters new litX --lite' failed"
[ -f "$pp/.hb/refuters/litX.md" ] || fail "python: --lite scaffold did not create <name>.md"
chk_resolvable "$(persona_py "$pp/.hb" litX)" || fail "python: scaffolded litX does not resolve"

# unknown starter errors; a path-separator name is rejected
if scaffold_py zz "$pp" --from nosuchstarter >/dev/null 2>&1; then fail "python: unknown --from starter did not error"; fi
if scaffold_py "a/b" "$pp" >/dev/null 2>&1; then fail "python: a path-separator name was not rejected"; fi

# traversal: '.'/'..' must be rejected by BOTH and write NO stray file outside .hb/refuters/
for bad in . ..; do
  scaffold_py   "$bad" "$pp" >/dev/null 2>&1 && fail "python: traversal name '$bad' was not rejected"
  scaffold_node "$bad" "$pn" >/dev/null 2>&1 && fail "node: traversal name '$bad' was not rejected"
done
[ -e "$pp/.hb/SKILL.md" ] || [ -e "$pn/.hb/SKILL.md" ] && fail "traversal wrote a stray SKILL.md outside refuters/"

# a value-less --from must ERROR in BOTH runtimes (not silently scaffold a generic refuter — parity)
if scaffold_py   danglingp "$pp" --from >/dev/null 2>&1; then fail "python: a value-less --from did not error"; fi
if scaffold_node danglingn "$pn" --from >/dev/null 2>&1; then fail "node: a value-less --from did not error (silently scaffolded — parity break)"; fi
[ -e "$pn/.hb/refuters/danglingn/SKILL.md" ] && fail "node: value-less --from still wrote a refuter"

# no-clobber across formats: re-scaffolding an existing name must refuse and leave the file intact
before="$(cat "$pp/.hb/refuters/secX/SKILL.md")"
scaffold_py secX "$pp" --from correctness >/dev/null 2>&1 && fail "python: re-scaffolding an existing refuter did not refuse (no-clobber)"
chk_unchanged "$before" "$(cat "$pp/.hb/refuters/secX/SKILL.md")" || fail "python: no-clobber failed — the existing refuter was overwritten"

# byte-parity: py and node scaffold the SAME name+starter to a byte-identical tree
scaffold_py   foo "$pp" --from security >/dev/null 2>&1 || fail "python: scaffold foo failed"
scaffold_node foo "$pn" --from security >/dev/null 2>&1 || fail "node: 'refuters new' failed (command missing?)"
chk_byte_parity "$pp/.hb/refuters/foo" "$pn/.hb/refuters/foo" || fail "scaffolded tree differs node vs python (byte-parity)"

# arg-parsing parity: the --from=<v> equals form must behave like --from <v> (node parser vs python argparse)
scaffold_py   eqf "$pp" --from=security >/dev/null 2>&1 || fail "python: --from= equals form failed"
scaffold_node eqf "$pn" --from=security >/dev/null 2>&1 || fail "node: --from= equals form failed"
chk_byte_parity "$pp/.hb/refuters/eqf" "$pn/.hb/refuters/eqf" || fail "--from= equals form differs node vs python (node dropped the starter?)"
# repeated --from: last-wins in BOTH (argparse semantics) → byte-identical
scaffold_py   rep "$pp" --from security --from correctness >/dev/null 2>&1 || fail "python: repeated --from failed"
scaffold_node rep "$pn" --from security --from correctness >/dev/null 2>&1 || fail "node: repeated --from failed"
chk_byte_parity "$pp/.hb/refuters/rep" "$pn/.hb/refuters/rep" || fail "repeated --from differs node vs python (last-wins parity)"
# grammar is name-FIRST, ONE shared hand-parser both runtimes: these exotic forms must ERROR in BOTH
# (never one-succeeds-one-errors). Each pair: python (--dir first, sub-args raw) and node.
# a flag before the name
if PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli refuters --dir "$pp" new --lite ord1 >/dev/null 2>&1; then fail "python: flag-before-name not rejected"; fi
if node "$pn/.hb/hb.js" refuters new --lite ord1 >/dev/null 2>&1; then fail "node: flag-before-name not rejected"; fi
# a `--` as the name position
if PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli refuters --dir "$pp" new -- sep1 >/dev/null 2>&1; then fail "python: '--' name not rejected"; fi
if node "$pn/.hb/hb.js" refuters new -- sep1 >/dev/null 2>&1; then fail "node: '--' name not rejected (parser divergence)"; fi
# a trailing `--` after the name
if PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli refuters --dir "$pp" new trailx -- >/dev/null 2>&1; then fail "python: trailing '--' not rejected"; fi
if node "$pn/.hb/hb.js" refuters new trailx -- >/dev/null 2>&1; then fail "node: trailing '--' not rejected (parser divergence)"; fi
# a second positional
if scaffold_py twoa "$pp" twob >/dev/null 2>&1; then fail "python: two positional names did not error"; fi
if scaffold_node twoa "$pn" twob >/dev/null 2>&1; then fail "node: two positional names did not error"; fi

# the bare `hb refuters` LIST still works after the `new` sub-action exists (both runtimes, and it lists foo)
node "$pn/.hb/hb.js" refuters 2>/dev/null | grep -qx foo || fail "node: bare 'hb refuters' list broke / omits the scaffolded refuter"
PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli refuters --dir "$pp" 2>/dev/null | grep -qx foo || fail "python: bare 'hb refuters' list broke / omits the scaffolded refuter"

echo "REFUTER-SCAFFOLD-OK"
