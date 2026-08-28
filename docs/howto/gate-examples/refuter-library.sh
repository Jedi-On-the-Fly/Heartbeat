#!/usr/bin/env bash
# Proof: refuters are SHAREABLE like domain adapters — a shipped library under plugin/templates/refuters/
# is seeded into a project's .hb/refuters/ by bootstrap (exactly as templates/executors/ is,
# bootstrap.sh:66-68), a project file SHADOWS a shipped one of the same name (seeding is no-clobber),
# `hb refuters` lists the project's available profiles IDENTICALLY in node and python, and every shipped
# refuter is VALID + RESOLVES (behavioral integrity — not `test -f`). Prints REFUTER-LIBRARY-OK.
# Fails before the shipped library / seeding / `hb refuters` command exist (spec-first, RED).
#
# `--selftest` proves each property is load-bearing on synthetic fixtures (seeding / override /
# discovery-parity / integrity), using the RS resolver — a project whose one property is broken must be
# rejected by exactly that property's check, and a good project must pass all. Prints SELFTEST-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# Hermetic: this proof bootstraps its OWN temp projects and drives their hb.js (which honors an
# ambient HB_DIR over its script location). A caller that exports HB_DIR/DAG_FILE — e.g. gate.sh —
# must not leak into the temp projects, so clear them.
unset HB_DIR DAG_FILE EVENTS_FILE 2>/dev/null || true
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
BOOT="$ROOT/plugin/bootstrap.sh"
NODEMOD="$ROOT/plugin/templates/refuter_profiles.js"

fail() { echo "FAIL: $*" >&2; exit 1; }

# resolve a profile's persona through each runtime (RS resolver; reads <hbdir>/refuters)
persona_py()   { PYTHONPATH="$ROOT/py/src" python3 -c 'import sys;from heartbeat import refuter_profiles as r;print(r.resolve(sys.argv[1], sys.argv[2] or None).get("persona",""))' "$1" "$2" 2>/dev/null; }
persona_node() { node -e 'const r=require(process.argv[1]);const p=r.resolve(process.argv[2],process.argv[3]||null);process.stdout.write(String(p.persona||""))' "$NODEMOD" "$1" "$2" 2>/dev/null; }

# `hb refuters` in each runtime (rl2 adds these — absent → non-zero → RED in the main run)
node_refuters() { node "$1/.hb/hb.js" refuters; }
py_refuters()   { PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli refuters --dir "$1"; }

# ── property checks (each takes a project dir; used by BOTH the main run and --selftest) ───────────
# seeding: a shipped `default` was copied into .hb/refuters/ and resolves to a real persona
p_seeded() {
  [ -f "$1/.hb/refuters/default.json" ] || return 1
  local per; per="$(persona_py "$1/.hb" default)" || return 1
  [ -n "$per" ] || return 1
}
# override: a project-authored .hb/refuters/<name>.json shadows the shipped one (resolver reads it),
# and it SURVIVES a re-bootstrap (no-clobber). The caller sets up the SHADOW-MARKER file.
p_shadow() {
  local per; per="$(persona_py "$1/.hb" default)" || return 1
  case "$per" in *SHADOW-MARKER*) return 0 ;; *) return 1 ;; esac
}
# discovery parity: node and python list the SAME profiles, and the list contains an expected name
check_discovery() { # <nodeList> <pyList> <mustContainName>
  [ "$1" = "$2" ] || return 1
  printf '%s\n' "$1" | grep -qx "$3" || return 1
}
# behavioral integrity: EVERY profile file in .hb/refuters/ resolves to a non-empty persona
p_integrity() {
  local f name per any=0
  # every refuter — json, lite .md, and canonical <name>/SKILL.md folder — must resolve to a persona
  for f in "$1"/.hb/refuters/*.json "$1"/.hb/refuters/*.md; do
    [ -e "$f" ] || continue
    any=1; name="$(basename "$f")"; name="${name%.*}"
    per="$(persona_py "$1/.hb" "$name")" || return 1
    [ -n "$per" ] || return 1
  done
  for f in "$1"/.hb/refuters/*/SKILL.md; do
    [ -e "$f" ] || continue
    any=1; name="$(basename "$(dirname "$f")")"
    per="$(persona_py "$1/.hb" "$name")" || return 1
    [ -n "$per" ] || return 1
  done
  [ "$any" = 1 ] || return 1
}

# ── selftest: every property is load-bearing (synthetic fixtures, RS resolver, no real CLI) ────────
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  mk() { mkdir -p "$1/.hb/refuters"; }

  # a GOOD synthetic project: default seeded, an override marker, all files valid
  good="$d/good"; mk "$good"
  printf '%s' '{"persona":"shipped default persona"}' > "$good/.hb/refuters/default.json"
  p_seeded    "$good" || { echo "SELFTEST FAIL: good project failed p_seeded" >&2; exit 1; }
  p_integrity "$good" || { echo "SELFTEST FAIL: good project failed p_integrity" >&2; exit 1; }

  # seeding teeth: NO default.json → p_seeded must fail
  noseed="$d/noseed"; mk "$noseed"
  if p_seeded "$noseed"; then echo "SELFTEST FAIL: p_seeded passed with no seeded default (not load-bearing)" >&2; exit 1; fi

  # override teeth: the project file was clobbered back to shipped (no marker) → p_shadow must fail;
  # with the marker it must pass
  ovr="$d/ovr"; mk "$ovr"; printf '%s' '{"persona":"SHADOW-MARKER project override"}' > "$ovr/.hb/refuters/default.json"
  p_shadow "$ovr" || { echo "SELFTEST FAIL: p_shadow rejected a real override" >&2; exit 1; }
  printf '%s' '{"persona":"shipped default persona"}' > "$ovr/.hb/refuters/default.json"
  if p_shadow "$ovr"; then echo "SELFTEST FAIL: p_shadow passed when the override was clobbered (not load-bearing)" >&2; exit 1; fi

  # integrity teeth: a BROKEN (invalid JSON) profile → p_integrity must fail
  brk="$d/brk"; mk "$brk"; printf '%s' '{"persona":"ok"}' > "$brk/.hb/refuters/default.json"
  printf '%s' '{not valid json' > "$brk/.hb/refuters/broken.json"
  if p_integrity "$brk"; then echo "SELFTEST FAIL: p_integrity passed with a broken shipped refuter (not load-bearing)" >&2; exit 1; fi
  # integrity teeth (2): a VALID-JSON profile with an empty/missing persona is also not resolvable-to-substance
  brk2="$d/brk2"; mk "$brk2"; printf '%s' '{"persona":"ok"}' > "$brk2/.hb/refuters/default.json"
  printf '%s' '{"questions":[]}' > "$brk2/.hb/refuters/nopersona.json"
  if p_integrity "$brk2"; then echo "SELFTEST FAIL: p_integrity passed a valid-JSON profile with no persona (not load-bearing)" >&2; exit 1; fi

  # discovery-parity teeth: identical lists containing the name pass; divergent or missing fail
  check_discovery $'default\nsecurity' $'default\nsecurity' 'default' || { echo "SELFTEST FAIL: check_discovery rejected identical lists" >&2; exit 1; }
  if check_discovery $'default\nsecurity' $'default' 'default'; then echo "SELFTEST FAIL: check_discovery passed divergent node/python lists (not load-bearing)" >&2; exit 1; fi
  if check_discovery $'default' $'default' 'security';           then echo "SELFTEST FAIL: check_discovery passed a missing expected name (not load-bearing)" >&2; exit 1; fi

  echo "SELFTEST-OK"
  exit 0
fi

# ── main run: the REAL library, bootstrap seeding, and `hb refuters` (RED before rl2) ──────────────
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
proj="$work/proj"
bash "$BOOT" "$proj" >/dev/null 2>&1 || fail "bootstrap failed"

p_seeded "$proj"    || fail "shipped refuters were NOT seeded into .hb/refuters/ by bootstrap (or default does not resolve)"
p_integrity "$proj" || fail "a shipped/seeded refuter is invalid or does not resolve (behavioral integrity)"

# discovery parity: node ≡ python listing, includes the shipped default
nl="$(node_refuters "$proj")" || fail "node 'hb refuters' failed (command missing?)"
pl="$(py_refuters "$proj")"   || fail "python 'hb refuters' failed (command missing?)"
check_discovery "$nl" "$pl" "default" || fail "hb refuters differs node vs python, or omits 'default' — node=[$nl] py=[$pl]"

# project shadow + no-clobber: author an override, confirm the resolver reads it, then re-bootstrap
# and confirm the override SURVIVES (a shipped file never clobbers a project one of the same name)
printf '%s' '{"persona":"SHADOW-MARKER project override of default"}' > "$proj/.hb/refuters/default.json"
p_shadow "$proj" || fail "resolver did not read the project override of a shipped refuter"
bash "$BOOT" "$proj" >/dev/null 2>&1 || fail "re-bootstrap failed"
p_shadow "$proj" || fail "re-bootstrap CLOBBERED a project refuter (seeding must be no-clobber so project shadows shipped)"

# node twin can also resolve the seeded default (both runtimes, not just python)
[ -n "$(persona_node "$proj/.hb" default)" ] || fail "node resolver could not resolve the seeded default"

echo "REFUTER-LIBRARY-OK"
