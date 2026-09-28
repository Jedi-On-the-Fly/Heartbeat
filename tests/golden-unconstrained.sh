#!/usr/bin/env bash
# golden-unconstrained.sh — freeze the review surfaces of an UNCONSTRAINED gate.
#
# Constraint-first review (1.32.0) must leave every gate without plan-time constraints
# byte-for-byte as it was. There is no older release tag to diff against, so the
# pre-change behaviour is captured once into tests/fixtures/golden-unconstrained/ and
# every later tree is compared to it:
#   - `refute-prompt <gate>` text, node and python, for a no-profile gate and each
#     shipped refuter profile;
#   - `refute-prompt <gate> --json`, restricted to the five keys that existed at capture
#     (prompt, model, provider, panel, refute_if) — keys added later are outside the golden;
#   - the verdict (exit code + output) of `hb review` for crafted artifacts.
#
#   bash tests/golden-unconstrained.sh            # compare → GOLDEN-UNCONSTRAINED-OK
#   bash tests/golden-unconstrained.sh --capture  # (re)write the fixtures — only on purpose
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$ROOT/tests/fixtures/golden-unconstrained"
PYSRC="${HB_PY_SRC:-$ROOT/py/src}"
MODE=compare; [ "${1:-}" = "--capture" ] && MODE=capture
export HB_NO_GIT=1
# python orders the cited anchors of a review pass by set iteration (hash-seeded): pin it
export PYTHONHASHSEED=0
unset HB_ACTOR

# One fixture DAG: a no-profile gate + one gate per shipped profile (all unconstrained).
PROFILES=$(cd "$ROOT/plugin/templates/refuters" && for f in *; do echo "${f%.json}"; done | sort)
mkdag(){
  python3 - "$1" $PROFILES <<'EOF'
import json, sys
out, profs = sys.argv[1], sys.argv[2:]
gates = {"GATE_NP": {"desc": "the no-profile phase", "review": {"prompt": "REVIEW-MARK refute it"},
                     "criteria": [{"id": "c", "cmd": "test -s \"$PROJECT_DIR/out.txt\""}]}}
phases = [{"id": "NP", "title": "no profile", "gate_entry": None, "gate_exit": "GATE_NP",
           "tasks": [{"id": "np1", "title": "t"}]}]
prev = "GATE_NP"
for i, p in enumerate(profs):
    g = "GATE_" + p.upper().replace("-", "_")
    gates[g] = {"desc": "the %s phase" % p, "review": {"prompt": "REVIEW-MARK %s" % p, "profile": p},
                "criteria": [{"id": "c", "cmd": "test -s \"$PROJECT_DIR/out.txt\""}]}
    phases.append({"id": "PH%d" % i, "title": p, "gate_entry": prev, "gate_exit": g,
                   "tasks": [{"id": "t%d" % i, "title": "t"}]})
    prev = g
json.dump({"phases": phases, "gates": gates}, open(out, "w"), indent=1)
EOF
}
mkproj(){  # $1 = dir → a node-runnable, python-runnable project with the shipped profiles
  local d="$1"; mkdir -p "$d/.hb"
  cp "$ROOT"/plugin/templates/*.js "$d/.hb/"
  cp -r "$ROOT/plugin/templates/refuters" "$d/.hb/refuters"
  mkdag "$d/.hb/dag.json"
  printf '%s\n' '{"ts":"2026-01-01T00:00:00Z","event":"initialized","project":"golden"}' > "$d/.hb/events.jsonl"
}
node_hb(){ local d="$1"; shift; node "$d/.hb/hb.js" "$@"; }
py_hb(){ local d="$1"; shift; PYTHONPATH="$PYSRC" python3 -m heartbeat.cli "$@" --dir "$d"; }
JNORM='import sys,json;d=json.load(sys.stdin);print(json.dumps({k:d.get(k) for k in ["prompt","model","provider","panel","refute_if"]},ensure_ascii=False,sort_keys=True))'

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
OUT="$WORK/out"; mkdir -p "$OUT"
emit(){ printf '%s' "$2" > "$OUT/$1.txt"; }   # name, content

# ── refute-prompt surfaces ──
P="$WORK/p"; mkproj "$P"
GATES=$(python3 -c 'import json,sys;print(" ".join(json.load(open(sys.argv[1]))["gates"]))' "$P/.hb/dag.json")
for g in $GATES; do
  emit "node.refute-prompt.$g" "$(node_hb "$P" refute-prompt "$g" 2>&1)"
  emit "py.refute-prompt.$g"   "$(py_hb "$P" refute-prompt "$g" 2>&1)"
  emit "node.refute-prompt-json.$g" "$(node_hb "$P" refute-prompt "$g" --json 2>&1 | python3 -c "$JNORM" 2>&1)"
  emit "py.refute-prompt-json.$g"   "$(py_hb "$P" refute-prompt "$g" --json 2>&1 | python3 -c "$JNORM" 2>&1)"
done

# ── review verdicts: a fresh project per case, the phase's task done by actor 'doer' ──
VALID='Refutation attempt for GATE_NP (task np1): tried an empty out.txt and a missing one; the criterion rejects both. Could not refute.'
case_review(){  # rt name reviewer artifact-content-or-NONE verdict [note]
  local rt="$1" name="$2" who="$3" body="$4" verdict="$5" note="${6:-}" d="$WORK/r-$1-$2" args
  mkproj "$d"
  if [ "$rt" = node ]; then HB_ACTOR=doer node_hb "$d" start np1 >/dev/null 2>&1; HB_ACTOR=doer node_hb "$d" done np1 >/dev/null 2>&1
  else HB_ACTOR=doer py_hb "$d" start np1 >/dev/null 2>&1; HB_ACTOR=doer py_hb "$d" done np1 >/dev/null 2>&1; fi
  args=(review GATE_NP "$verdict")
  if [ "$body" != NONE ]; then printf '%s\n' "$body" > "$d/finding.md"; args+=(--artifact finding.md); fi
  [ -n "$note" ] && args+=("$note")
  local o rc
  if [ "$rt" = node ]; then o=$(cd "$d" && HB_ACTOR="$who" node_hb "$d" "${args[@]}" 2>&1); rc=$?
  else o=$(cd "$d" && HB_ACTOR="$who" py_hb "$d" "${args[@]}" 2>&1); rc=$?; fi
  emit "$rt.review.$name" "rc=$rc
${o//$d/<D>}"
}
for rt in node py; do
  case_review "$rt" no-artifact  refuter NONE pass
  case_review "$rt" short        refuter 'looks fine' pass
  case_review "$rt" uncited      refuter 'I looked at everything carefully and could not find any problem at all here.' pass
  case_review "$rt" self-review  doer    "$VALID" pass
  case_review "$rt" valid        refuter "$VALID" pass
  case_review "$rt" fail         refuter NONE fail 'hole: out.txt may be stale'
done

N=$(ls "$OUT" | wc -l)
if [ "$MODE" = capture ]; then
  rm -rf "$FIX"; mkdir -p "$FIX"; cp "$OUT"/*.txt "$FIX/"
  echo "captured $N fixtures into ${FIX#$ROOT/}"; exit 0
fi
[ -d "$FIX" ] || { echo "✗ no fixtures at ${FIX#$ROOT/} (run --capture on the reference tree)"; exit 1; }
fail=0
for f in "$FIX"/*.txt; do
  n=$(basename "$f")
  if [ ! -f "$OUT/$n" ]; then echo "✗ $n: no longer produced"; fail=1
  elif ! cmp -s "$f" "$OUT/$n"; then echo "✗ $n differs:"; diff "$f" "$OUT/$n" | head -8; fail=1; fi
done
for f in "$OUT"/*.txt; do [ -f "$FIX/$(basename "$f")" ] || { echo "✗ $(basename "$f"): not in the golden"; fail=1; }; done
[ "$fail" = 0 ] && { echo "✓ $N golden surfaces unchanged"; echo "GOLDEN-UNCONSTRAINED-OK"; exit 0; }
exit 1
