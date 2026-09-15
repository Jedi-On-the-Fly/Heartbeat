#!/usr/bin/env bash
# Proof: the INTERACTIVE refute surface gets a machine-readable model binding — closing the
# gap where profile.model reached the exec dispatch (T147) but an interactive host had nothing
# to act on, so refuters silently inherited the (expensive) session model.
#   1. `refute-prompt <gate> --json` emits {prompt, model, provider, panel, refute_if} from the
#      gate's review.profile — BOTH runtimes.
#   2. profile-less gate: model/provider/panel null AND json.prompt byte-identical to the text
#      compose (backward-compat).
#   3. PROFILED gate: json.prompt byte-identical to the text compose too — ONE compose, pinned
#      in bytes, not piece-presence.
#   4. the TEXT compose byte-contract is intact (delegates to refuter-compose.sh, the T147 pin).
#   5. node --json ≡ python --json, with and without a profile.
#   6. the skill AND both runtimes' PROTOCOL review_pending text instruct the host BOTH halves:
#      spawn on the profile's model, record with --model (the instructions, not just the data).
# --selftest: each assertion is individually load-bearing. Prints REFUTER-MODEL-ROUTING-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# Env hygiene: when run AS a gate criterion, gate.sh exports HB_DIR/PROJECT_DIR — and the
# fixture's copied hb.js honors env HB_DIR, which would silently point it at the CALLING
# project's .hb instead of the fixture. Strip them so the proof tests the fixture, always.
unset HB_DIR PROJECT_DIR GATE G 2>/dev/null || true
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

mkproj(){ # $1 = dir
  mkdir -p "$1/.hb/refuters"
  cp "$ROOT/plugin/templates/hb.js" "$ROOT/plugin/templates/hb-audit.js" \
     "$ROOT/plugin/templates/hb-lint.js" "$ROOT/plugin/templates/hb-next-task.js" \
     "$ROOT/plugin/templates/refuter_profiles.js" "$1/.hb/"
  printf '%s' '{"phases":[{"id":"P0","gate_entry":null,"gate_exit":"GATE_A","tasks":[{"id":"T1","title":"t","requires":[]}]},{"id":"P1","gate_entry":"GATE_A","gate_exit":"GATE_B","tasks":[{"id":"T2","title":"t","requires":[]}]}],"gates":{"GATE_A":{"desc":"a","review":{"prompt":"RM-A refute it","profile":"secmod"},"criteria":[{"id":"c","cmd":"true"}]},"GATE_B":{"desc":"b","review":{"prompt":"RM-B refute it"},"criteria":[{"id":"c","cmd":"true"}]}}}' > "$1/.hb/dag.json"
  printf '%s' '{"persona":"SECMOD persona","questions":["QX authz?"],"model":"m-cheap","provider":"prov-x","verdict":{"panel":3,"refute_if":"any"}}' > "$1/.hb/refuters/secmod.json"
  printf '%s\n' '{"event":"initialized"}' > "$1/.hb/events.jsonl"
}

# json field extractor: jkey <file> <key> → value or the literal `null`
jkey(){ python3 -c 'import sys,json;v=json.load(open(sys.argv[1])).get(sys.argv[2]);print("null" if v is None else v)' "$1" "$2"; }
jprompt(){ python3 -c 'import sys,json;sys.stdout.write(json.load(open(sys.argv[1]))["prompt"])' "$1"; }

p="$(mktemp -d)"; trap 'rm -rf "$p"' EXIT
mkproj "$p"

# ── 1. --json carries the profile's binding (both runtimes) ──────────────────
hb refute-prompt GATE_A --json --dir "$p" > "$p/py_a.json" 2>/dev/null || fail "python refute-prompt --json failed (does the flag exist?)"
node "$p/.hb/hb.js" refute-prompt GATE_A --json > "$p/nd_a.json" 2>/dev/null || fail "node refute-prompt --json failed (does the flag exist?)"
for f in py_a nd_a; do
  [ "$(jkey "$p/$f.json" model)" = "m-cheap" ]   || fail "$f: model not taken from the profile"
  [ "$(jkey "$p/$f.json" provider)" = "prov-x" ] || fail "$f: provider not taken from the profile"
  [ "$(jkey "$p/$f.json" panel)" = "3" ]         || fail "$f: panel not surfaced (a host cannot fan out a panel without it)"
  [ "$(jkey "$p/$f.json" refute_if)" = "any" ]   || fail "$f: refute_if not surfaced (a host cannot aggregate a panel without it)"
done

# ── 1b. flag ORDER must not matter (round-1 refutation catch: node consumed a leading
#        --json AS the gate name and silently emitted a bogus TEXT prompt with exit 0) ──
hb refute-prompt --json GATE_A --dir "$p" > "$p/py_a2.json" 2>/dev/null || fail "python --json-first order failed"
node "$p/.hb/hb.js" refute-prompt --json GATE_A > "$p/nd_a2.json" 2>/dev/null || fail "node --json-first order failed"
[ "$(jkey "$p/py_a2.json" model 2>/dev/null)" = "m-cheap" ] || fail "python --json-first: flag eaten as the gate name"
[ "$(jkey "$p/nd_a2.json" model 2>/dev/null)" = "m-cheap" ] || fail "node --json-first: not JSON or model missing — the flag was eaten as the gate name"

# ── 2. profile-less: nulls + prompt byte-identical to the text compose ───────
hb refute-prompt GATE_B --json --dir "$p" > "$p/py_b.json" 2>/dev/null || fail "python --json failed on a profile-less gate"
node "$p/.hb/hb.js" refute-prompt GATE_B --json > "$p/nd_b.json" 2>/dev/null || fail "node --json failed on a profile-less gate"
[ "$(jkey "$p/py_b.json" model)" = "null" ] || fail "profile-less gate must report model null — never a fabricated default"
hb refute-prompt GATE_B --dir "$p" > "$p/py_b.txt" 2>/dev/null
jprompt "$p/py_b.json" > "$p/py_b.jp"; printf '%s' "$(cat "$p/py_b.txt")" > "$p/py_b.tt"
cmp -s "$p/py_b.jp" "$p/py_b.tt" || fail "profile-less json.prompt != text compose (byte drift)"

# ── 3. PROFILED: json.prompt byte-identical to the text compose (one compose) ─
hb refute-prompt GATE_A --dir "$p" > "$p/py_a.txt" 2>/dev/null
jprompt "$p/py_a.json" > "$p/py_a.jp"; printf '%s' "$(cat "$p/py_a.txt")" > "$p/py_a.tt"
cmp -s "$p/py_a.jp" "$p/py_a.tt" || fail "PROFILED json.prompt != text compose — --json has drifted from the one compose"
node "$p/.hb/hb.js" refute-prompt GATE_A > "$p/nd_a.txt" 2>/dev/null
jprompt "$p/nd_a.json" > "$p/nd_a.jp"; printf '%s' "$(cat "$p/nd_a.txt")" > "$p/nd_a.tt"
cmp -s "$p/nd_a.jp" "$p/nd_a.tt" || fail "node PROFILED json.prompt != text compose"

# ── 4. the TEXT byte-contract is intact (T147's own pin) ─────────────────────
bash "$ROOT/docs/howto/gate-examples/refuter-compose.sh" 2>&1 | grep -q 'REFUTER-COMPOSE-OK' \
  || fail "text-compose byte contract broken (refuter-compose.sh / T147 no longer passes)"

# ── 5. node --json ≡ python --json (semantic) ────────────────────────────────
norm(){ python3 -c 'import sys,json;d=json.load(open(sys.argv[1]));print(json.dumps([d.get("model"),d.get("provider"),d.get("panel"),d.get("refute_if"),d.get("prompt")],sort_keys=True))' "$1"; }
[ "$(norm "$p/py_a.json")" = "$(norm "$p/nd_a.json")" ] || fail "node --json != python --json (profiled)"
[ "$(norm "$p/py_b.json")" = "$(norm "$p/nd_b.json")" ] || fail "node --json != python --json (profile-less)"

# ── 6. the instructions exist — BOTH halves, all three texts ─────────────────
for f in "$ROOT/plugin/skills/heartbeat/SKILL.md" "$ROOT/py/src/heartbeat/protocol.py" "$ROOT/plugin/templates/hb.js"; do
  # apostrophe-tolerant: hb.js carries the sentence inside a single-quoted JS string (profile\'s)
  grep -qi "refuter ON the profile" "$f" || fail "$(basename "$f"): missing the SPAWN half (spawn the refuter on the profile's model)"
  grep -q -- '--model' "$f"             || fail "$(basename "$f"): missing the RECORD half (record the verdict with --model)"
done

# ── --selftest: each assertion is load-bearing ───────────────────────────────
if [ "${1:-}" = "--selftest" ]; then
  python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));d.pop("model");json.dump(d,open(sys.argv[1],"w"))' "$p/py_a.json"
  [ "$(jkey "$p/py_a.json" model)" = "null" ] || { echo "SELFTEST-ESCAPED: dropped model not detected"; exit 1; }
  printf 'PERTURBED' >> "$p/py_a.jp"
  cmp -s "$p/py_a.jp" "$p/py_a.tt" && { echo "SELFTEST-ESCAPED: byte-pin did not catch a perturbed prompt"; exit 1; }
  printf 'Refute that --json is truly complete.\n' > "$p/bogus.json"
  [ "$(jkey "$p/bogus.json" model 2>/dev/null)" = "m-cheap" ] && { echo "SELFTEST-ESCAPED: a bogus TEXT output (the round-1 bug shape) passed the JSON check"; exit 1; }
  sed 's/--model//g' "$ROOT/py/src/heartbeat/protocol.py" > "$p/proto.stripped"
  grep -q -- '--model' "$p/proto.stripped" && { echo "SELFTEST-ESCAPED: stripped instruction still matched"; exit 1; }
  bash "$ROOT/docs/howto/gate-examples/refuter-compose.sh" --selftest 2>&1 | grep -q 'SELFTEST-OK' \
    || { echo "SELFTEST-ESCAPED: the underlying compose selftest is not protecting assertion 4"; exit 1; }
  echo "SELFTEST-OK: model-key, byte-pin, instruction-grep, and compose-contract teeth all bite."
  exit 0
fi

echo "REFUTER-MODEL-ROUTING-OK: --json binding (both runtimes), one-compose byte pins, text contract intact, both instruction halves present."
