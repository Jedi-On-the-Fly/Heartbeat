#!/usr/bin/env bash
# Proof: a refuter may be authored as an agent SKILL — a canonical folder `.hb/refuters/<name>/SKILL.md`
# OR a lite `.hb/refuters/<name>.md` (flat `---` frontmatter + persona body + a `## Checklist` bullet
# list) — and resolves to the SAME normalized {persona, questions[], model, provider, verdict} dict as
# the equivalent `<name>.json`, node ≡ python. `hb refuters` lists both skill-format refuters (a folder
# has no extension — it must not be dropped); a `references/`/`assets/` subdir without a SKILL.md is not
# a refuter; a same-NAME cross-format collision errors (fail-closed). Prints REFUTER-SKILL-OK.
# Fails before the .md/folder front-doors exist (spec-first, RED).
#
# The make-or-break rule is PARITY: the flat frontmatter is parsed by a shared minimal line-parser (no
# YAML), so node and python must agree on every divergence trap. `--selftest` proves that — a fake
# parser is mutated to diverge on ONE trap at a time, and the parity check must catch each; it also
# proves the listing checks (folder dropped / non-SKILL.md subdir enumerated) are load-bearing. SELFTEST-OK.
# `--seeding` (SEEDING-SAFE-OK): the shipped library defines no name in >1 format, a bootstrapped project
# resolves every seeded refuter incl. a folder one (full tree copy), and re-bootstrap manufactures no collision.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR DAG_FILE EVENTS_FILE HB_REFUTER 2>/dev/null || true
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
NODEMOD="$ROOT/plugin/templates/refuter_profiles.js"
fail() { echo "FAIL: $*" >&2; exit 1; }

# ── canonical resolve() through each runtime → canonical JSON of the normalized dict, or non-zero ──
py_resolve() { # <hbdir> <name>
  PYTHONPATH="$ROOT/py/src" python3 - "$1" "$2" <<'PY' 2>/dev/null
import sys, json
from heartbeat import refuter_profiles as r
print(json.dumps(r.resolve(sys.argv[1], sys.argv[2] or None), sort_keys=True, separators=(",", ":")))
PY
}
node_resolve() { # <hbdir> <name>
  node -e '
    const r = require(process.argv[1]);
    const canon = (x) => Array.isArray(x) ? "[" + x.map(canon).join(",") + "]"
      : (x && typeof x === "object") ? "{" + Object.keys(x).sort().map(k => JSON.stringify(k) + ":" + canon(x[k])).join(",") + "}"
      : JSON.stringify(x === undefined ? null : x);
    console.log(canon(r.resolve(process.argv[2], process.argv[3] || null)));
  ' "$NODEMOD" "$1" "$2" 2>/dev/null
}
node_refuters() { node "$1/.hb/hb.js" refuters 2>/dev/null; }
py_refuters()   { PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli refuters --dir "$1" 2>/dev/null; }

# ── the canonical shared parser (the SPEC af2 must implement byte-identically in py + node) ─────────
# Emitted to a temp dir for --selftest, where MUT diverges the PYTHON copy on one trap.
write_fakes() { # <dir>
  cat > "$1/skillparse.py" <<'PY'
import os, json
MUT = os.environ.get("MUT", "none")
def parse(text):
    lines = text.split("\n")
    if lines and lines[0][:1] == "﻿" and MUT != "bom": lines[0] = lines[0][1:]
    if MUT != "crlf": lines = [l[:-1] if l.endswith("\r") else l for l in lines]
    fm = {}; body_start = 0
    if lines and lines[0].strip() == "---":
        close = None
        for i in range(1, len(lines)):
            if lines[i].strip() == "---": close = i; break
        if close is None:
            if MUT == "noclose": close = len(lines)   # divergent: treat rest as frontmatter
        if close is not None:
            for l in lines[1:close]:
                if l.strip() == "":
                    if MUT == "blank": break
                    continue
                if ":" not in l: continue
                if MUT == "firstcolon": k, _, v = l.rpartition(":")
                else: k, _, v = l.partition(":")
                k = k.strip() if MUT == "keycase" else k.strip().lower()
                v = v if MUT == "trailws" else v.strip()
                if MUT == "hash" and "#" in v: v = v.split("#")[0].strip()
                if MUT != "quotes" and len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'": v = v[1:-1]
                if MUT == "dupkey" and k in fm: pass
                else: fm[k] = v
            body_start = (close + 1) if close < len(lines) else len(lines)
    body = "\n".join(lines[body_start:])
    bl = body.split("\n"); idx = None
    for i, l in enumerate(bl):
        hit = (l.strip() == "## Checklist") if MUT == "checklistcase" else (l.strip().lower() == "## checklist")
        if hit: idx = i; break
    if idx is None:
        persona = body if MUT == "personatrim" else body.strip(); questions = []
    else:
        persona = "\n".join(bl[:idx]) if MUT == "personatrim" else "\n".join(bl[:idx]).strip()
        questions = []
        for l in bl[idx + 1:]:
            ls = l.strip()
            if ls.startswith("## "): break
            mark = (ls[:1] == "-") if MUT == "bullet" else (ls[:1] in ("-", "*"))
            if mark: questions.append(ls[1:].strip())
    verdict = None
    if "panel" in fm: verdict = {"panel": int(fm["panel"]), "refute_if": fm.get("refute_if", "majority")}
    return {"persona": persona, "questions": questions, "model": fm.get("model"),
            "provider": fm.get("provider"), "verdict": verdict}
if __name__ == "__main__":
    import sys
    print(json.dumps(parse(open(sys.argv[1], encoding="utf-8").read()), sort_keys=True, separators=(",", ":")))
PY
  cat > "$1/skillparse.js" <<'JS'
const fs = require("fs");
function parse(text) {
  let lines = text.split("\n");
  if (lines.length && lines[0][0] === "﻿") lines[0] = lines[0].slice(1);
  lines = lines.map(l => l.endsWith("\r") ? l.slice(0, -1) : l);
  const fm = {}; let bodyStart = 0;
  if (lines.length && lines[0].trim() === "---") {
    let close = null;
    for (let i = 1; i < lines.length; i++) if (lines[i].trim() === "---") { close = i; break; }
    if (close !== null) {
      for (const l of lines.slice(1, close)) {
        if (l.trim() === "") continue;
        if (!l.includes(":")) continue;
        const ci = l.indexOf(":"); let k = l.slice(0, ci).trim().toLowerCase(); let v = l.slice(ci + 1).trim();
        if (v.length >= 2 && v[0] === v[v.length - 1] && (v[0] === '"' || v[0] === "'")) v = v.slice(1, -1);
        fm[k] = v;
      }
      bodyStart = close + 1;
    }
  }
  const body = lines.slice(bodyStart).join("\n");
  const bl = body.split("\n"); let idx = null;
  for (let i = 0; i < bl.length; i++) if (bl[i].trim().toLowerCase() === "## checklist") { idx = i; break; }
  let persona, questions = [];
  if (idx === null) { persona = body.trim(); }
  else {
    persona = bl.slice(0, idx).join("\n").trim();
    for (const l of bl.slice(idx + 1)) {
      const ls = l.trim();
      if (ls.startsWith("## ")) break;
      if (ls[0] === "-" || ls[0] === "*") questions.push(ls.slice(1).trim());
    }
  }
  let verdict = null;
  if ("panel" in fm) verdict = { panel: parseInt(fm.panel, 10), refute_if: fm.refute_if || "majority" };
  return { persona, questions, model: fm.model === undefined ? null : fm.model,
           provider: fm.provider === undefined ? null : fm.provider, verdict };
}
const canon = (x) => Array.isArray(x) ? "[" + x.map(canon).join(",") + "]"
  : (x && typeof x === "object") ? "{" + Object.keys(x).sort().map(k => JSON.stringify(k) + ":" + canon(x[k])).join(",") + "}"
  : JSON.stringify(x === undefined ? null : x);
console.log(canon(parse(fs.readFileSync(process.argv[2], "utf8"))));
JS
}

# a fixture that exercises a given trap (frontmatter line + a checklist)
trap_fixture() { # <trap> <file>
  local t="$1" line
  case "$t" in
    firstcolon) line='model: a:b:c' ;;
    quotes)     line='model: "M1"' ;;
    trailws)    line='model: M1   ' ;;
    hash)       line='model: M1 # note' ;;
    keycase)    line='Model: M1' ;;
    dupkey)     printf -- '---\nmodel: A\nmodel: B\n---\nP\n\n## Checklist\n- q\n' > "$2"; return ;;
    bom)        printf '\xEF\xBB\xBF---\nmodel: M1\n---\nP\n\n## Checklist\n- q\n' > "$2"; return ;;
    crlf)       printf -- '---\r\nmodel: M1\r\n---\r\nP\r\n\r\n## Checklist\r\n- q\r\n' > "$2"; return ;;
    blank)      printf -- '---\nmodel: M1\n\nprovider: P1\n---\nP\n\n## Checklist\n- q\n' > "$2"; return ;;
    noclose)    printf -- '---\nmodel: M1\nP body no close\n' > "$2"; return ;;
    checklistcase) printf -- '---\nmodel: M1\n---\nP\n\n## checklist\n- q\n' > "$2"; return ;;
    bullet)     printf -- '---\nmodel: M1\n---\nP\n\n## Checklist\n* q\n' > "$2"; return ;;
    personatrim) printf -- '---\nmodel: M1\n---\n   P spaced   \n\n## Checklist\n- q\n' > "$2"; return ;;
    *)          line='model: M1' ;;
  esac
  printf -- '---\n%s\n---\nP\n\n## Checklist\n- q\n' "$line" > "$2"
}
TRAPS="firstcolon quotes trailws hash keycase dupkey bom crlf blank noclose checklistcase bullet personatrim"
# CRLF/BOM are handled by the parser's strip-everywhere design (no divergence to catch) — they are
# asserted as MAIN per-trap PARITY fixtures only; the --selftest divergence set is the traps a naive
# parser genuinely splits on.
TRAPS_MUT="firstcolon quotes trailws hash keycase dupkey blank noclose checklistcase bullet personatrim"

# ── selftest: parity-comparison + listing checks are load-bearing ───────────────────────────────────
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  write_fakes "$d"
  pj() { MUT="${MUT:-none}" python3 "$d/skillparse.py" "$1"; }
  nj() { node "$d/skillparse.js" "$1"; }
  # clean fake: every trap fixture parses IDENTICALLY node ≡ python
  for t in $TRAPS; do
    f="$d/f.md"; trap_fixture "$t" "$f"
    a="$(MUT=none pj "$f")"; b="$(nj "$f")"
    [ -n "$a" ] && [ "$a" = "$b" ] || { echo "SELFTEST FAIL: clean parser diverged on trap '$t' (a=$a b=$b)" >&2; exit 1; }
  done
  # each divergence trap: mutate the PYTHON parser to diverge on THAT trap → the parity check must CATCH it
  for t in $TRAPS_MUT; do
    f="$d/f.md"; trap_fixture "$t" "$f"
    a="$(MUT="$t" pj "$f")"; b="$(nj "$f")"
    [ "$a" != "$b" ] || { echo "SELFTEST FAIL: mutant '$t' did NOT diverge — that trap's parity check is not load-bearing" >&2; exit 1; }
  done
  # listing teeth: a checker that lists refuter NAMES from a dir (json + md + <name>/SKILL.md)
  lst() { # <dir>  (reference listing: extensions + folders-with-SKILL.md)
    { for f in "$1"/*.json "$1"/*.md; do [ -e "$f" ] && basename "$f" | sed -E 's/\.(json|md)$//'; done
      for s in "$1"/*/SKILL.md; do [ -e "$s" ] && basename "$(dirname "$s")"; done; } 2>/dev/null | sort -u
  }
  w="$d/proj/refuters"; mkdir -p "$w/folder1" "$w/refs"
  printf '{}' > "$w/lite1.md"; printf 'x' > "$w/folder1/SKILL.md"; printf 'y' > "$w/refs/notes.md"
  out="$(lst "$w")"
  printf '%s\n' "$out" | grep -qx folder1 || { echo "SELFTEST FAIL: listing dropped a folder refuter" >&2; exit 1; }
  printf '%s\n' "$out" | grep -qx lite1   || { echo "SELFTEST FAIL: listing dropped a lite .md refuter" >&2; exit 1; }
  printf '%s\n' "$out" | grep -qx refs    && { echo "SELFTEST FAIL: listing mis-enumerated a non-SKILL.md subdir" >&2; exit 1; }
  echo "SELFTEST-OK"; exit 0
fi

# ── seeding safety (real shipped library + bootstrap) ───────────────────────────────────────────────
if [ "${1:-}" = "--seeding" ]; then
  SH="$ROOT/plugin/templates/refuters"
  # no name defined in more than one format
  names="$( { for f in "$SH"/*.json "$SH"/*.md; do [ -e "$f" ] && basename "$f" | sed -E 's/\.(json|md)$//'; done
             for s in "$SH"/*/SKILL.md; do [ -e "$s" ] && basename "$(dirname "$s")"; done; } 2>/dev/null | sort )"
  dup="$(printf '%s\n' "$names" | uniq -d)"
  [ -z "$dup" ] || fail "shipped library defines a name in >1 format: $dup"
  work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
  p="$work/p"; bash "$ROOT/plugin/bootstrap.sh" "$p" >/dev/null 2>&1 </dev/null
  # every seeded refuter resolves; and at least ONE is a folder form (full tree copy)
  seeded_folder=0
  for s in "$p"/.hb/refuters/*/SKILL.md; do [ -e "$s" ] || continue; seeded_folder=1
    n="$(basename "$(dirname "$s")")"; [ -n "$(py_resolve "$p/.hb" "$n")" ] || fail "seeded folder refuter '$n' does not resolve"; done
  [ "$seeded_folder" = 1 ] || fail "no folder-form refuter was seeded (folder seeding not implemented / no folder starter shipped)"
  for f in "$p"/.hb/refuters/*.json "$p"/.hb/refuters/*.md; do [ -e "$f" ] || continue
    n="$(basename "$f" | sed -E 's/\.(json|md)$//')"; [ -n "$(py_resolve "$p/.hb" "$n")" ] || fail "seeded refuter '$n' does not resolve"; done
  # re-bootstrap must not drop a shipped format beside a project's own folder of the same name
  onlyname="$(basename "$(dirname "$(ls "$p"/.hb/refuters/*/SKILL.md 2>/dev/null | head -1)")")"
  bash "$ROOT/plugin/bootstrap.sh" "$p" >/dev/null 2>&1 </dev/null
  [ ! -e "$p/.hb/refuters/$onlyname.json" ] && [ ! -e "$p/.hb/refuters/$onlyname.md" ] \
    || fail "re-bootstrap dropped a shipped format beside the project's own '$onlyname/' folder (collision manufactured)"
  echo "SEEDING-SAFE-OK"; exit 0
fi

# ── main: the REAL resolver over folder + lite + json (RED before af2) ──────────────────────────────
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
HB="$work/.hb"; mkdir -p "$HB/refuters/asfolder" "$HB/refuters/asfolder/references"
# the SAME content in three forms, under three distinct names
printf '%s' '{"persona":"PERSONA body hunts things.","questions":["q-one","q-two"],"model":"M1","provider":"PR1","verdict":{"panel":3,"refute_if":"majority"}}' > "$HB/refuters/asjson.json"
SKILL=$'---\nname: x\ndescription: d\nmodel: M1\nprovider: PR1\npanel: 3\nrefute_if: majority\n---\nPERSONA body hunts things.\n\n## Checklist\n- q-one\n- q-two\n'
printf '%s' "$SKILL" > "$HB/refuters/aslite.md"
printf '%s' "$SKILL" > "$HB/refuters/asfolder/SKILL.md"
printf 'ref' > "$HB/refuters/asfolder/references/extra.md"    # a sidecar; the dir is a refuter via SKILL.md

j="$(py_resolve "$HB" asjson)"; [ -n "$j" ] || fail "baseline json did not resolve"
# folder + lite resolve to the SAME normalized dict as json, both runtimes
for name in aslite asfolder; do
  pj="$(py_resolve "$HB" "$name")"; nj="$(node_resolve "$HB" "$name")"
  [ -n "$pj" ] || fail "$name did not resolve (python) — skill-format front-door missing (expected RED before af2)"
  [ "$pj" = "$j" ] || fail "$name resolved to a DIFFERENT dict than the equivalent json (python): $pj != $j"
  [ "$pj" = "$nj" ] || fail "$name resolves differently node vs python (parity): py=$pj node=$nj"
done

# per-trap parity: each trap fixture resolves IDENTICALLY node ≡ python (RED before af2: empty)
for t in $TRAPS; do
  trap_fixture "$t" "$HB/refuters/trap_$t.md"
  pj="$(py_resolve "$HB" "trap_$t")"; nj="$(node_resolve "$HB" "trap_$t")"
  [ -n "$pj" ] || fail "trap '$t' did not resolve (python) — parser missing (expected RED before af2)"
  [ "$pj" = "$nj" ] || fail "trap '$t' diverges node vs python: py=$pj node=$nj"
done

# hb refuters lists the lite + folder refuters; the references/ subdir is NOT a refuter
cp "$ROOT/plugin/templates/hb.js" "$ROOT/plugin/templates/hb-lint.js" "$ROOT/plugin/templates/hb-next-task.js" \
   "$ROOT/plugin/templates/hb-audit.js" "$ROOT/plugin/templates/refuter_profiles.js" "$HB/"
ls_out="$(node_refuters "$work")"
printf '%s\n' "$ls_out" | grep -qx aslite   || fail "hb refuters dropped the lite .md refuter"
printf '%s\n' "$ls_out" | grep -qx asfolder || fail "hb refuters dropped the folder SKILL.md refuter"
printf '%s\n' "$ls_out" | grep -qx references && fail "hb refuters mis-enumerated a non-SKILL.md subdir"
[ "$(node_refuters "$work")" = "$(py_refuters "$work")" ] || fail "hb refuters differs node vs python"

# same-NAME cross-format collision errors (fail-closed)
printf '{}' > "$HB/refuters/dup.json"; printf '%s' "$SKILL" > "$HB/refuters/dup.md"
if py_resolve   "$HB" dup >/dev/null 2>&1; then fail "python did NOT error on a same-name json+md collision"; fi
if node_resolve "$HB" dup >/dev/null 2>&1; then fail "node did NOT error on a same-name json+md collision"; fi

# a MALFORMED panel value must be REJECTED by BOTH runtimes — no lenient node parseInt (int-parse parity)
printf -- '---\npanel: notanint\n---\nP\n\n## Checklist\n- q\n' > "$HB/refuters/badpanel.md"
if py_resolve   "$HB" badpanel >/dev/null 2>&1; then fail "python did NOT reject a malformed panel value"; fi
if node_resolve "$HB" badpanel >/dev/null 2>&1; then fail "node did NOT reject a malformed panel value (lenient parseInt — parity break)"; fi

# a panel BEYOND the safe-integer range must be rejected by BOTH (node parseInt float vs python int bigint would otherwise diverge)
printf -- '---\npanel: 9007199254740993\n---\nP\n\n## Checklist\n- q\n' > "$HB/refuters/bigpanel.md"
if py_resolve   "$HB" bigpanel >/dev/null 2>&1; then fail "python did NOT reject an out-of-safe-range panel"; fi
if node_resolve "$HB" bigpanel >/dev/null 2>&1; then fail "node did NOT reject an out-of-safe-range panel (int vs parseInt precision divergence)"; fi

echo "REFUTER-SKILL-OK"
