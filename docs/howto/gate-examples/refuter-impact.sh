#!/usr/bin/env bash
# Proof: `hb report` surfaces REFUTER IMPACT from the event log (truth) — a `review_failed` is a CATCH
# (the refuter found a hole → gate_blocked), a `review_passed` is a clear (ran, could not refute), per
# gate with the gate's `review.profile` lens and the findings text. It records what was CAUGHT this run
# (never what was missed — misses are unknowable), so you can answer "did the refuter earn its keep?"
# node ≡ python on the canonical summary. Prints REFUTER-IMPACT-OK.
# `--selftest` proves the count / lens / findings / parity checks are each load-bearing. SELFTEST-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR DAG_FILE EVENTS_FILE HB_REFUTER 2>/dev/null || true
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# canonical JSON of report.refuters through each runtime
rimpact_py()   { PYTHONPATH="$ROOT/py/src" python3 -c 'import sys,json;from heartbeat.report import build;print(json.dumps(build(sys.argv[1]).get("refuters"),sort_keys=True,separators=(",",":"),ensure_ascii=False))' "$1" 2>/dev/null; }
rimpact_node() {
  node "$1/hb-report.js" "$1" --json 2>/dev/null | node -e '
    const r = JSON.parse(require("fs").readFileSync(0));
    const canon = (x) => Array.isArray(x) ? "[" + x.map(canon).join(",") + "]"
      : (x && typeof x === "object") ? "{" + Object.keys(x).sort().map(k => JSON.stringify(k) + ":" + canon(x[k])).join(",") + "}"
      : JSON.stringify(x === undefined ? null : x);
    console.log(canon(r.refuters));'
}

# ── selftest: the count/lens/findings/parity checks are load-bearing (synthetic canonical values) ────
if [ "${1:-}" = "--selftest" ]; then
  good='{"caught":2,"cleared":2,"gates":[{"caught":0,"cleared":1,"findings":[],"gate":"GATE_C","profile":null},{"caught":2,"cleared":1,"findings":["hole one","hole two"],"gate":"GATE_S","profile":"security"}]}'
  printf '%s' "$good" | grep -q '"caught":2'          || fail "selftest: caught check rejected a correct value"
  printf '%s' "$good" | grep -q '"profile":"security"' || fail "selftest: lens check rejected a correct value"
  printf '%s' "$good" | grep -q 'hole one'            || fail "selftest: findings check rejected real findings"
  bad_count='{"caught":0,"cleared":2,"gates":[]}'
  printf '%s' "$bad_count" | grep -q '"caught":2'      && fail "selftest: caught check is not load-bearing (passed a wrong count)"
  bad_lens='{"caught":2,"cleared":2,"gates":[{"caught":2,"cleared":1,"findings":["x"],"gate":"GATE_S","profile":null}]}'
  printf '%s' "$bad_lens" | grep -q '"profile":"security"' && fail "selftest: lens check is not load-bearing (passed a missing lens)"
  [ "$good" = "$good" ] || fail "selftest: parity compare rejected identical values"
  [ "$good" = "$bad_count" ] && fail "selftest: parity compare passed differing values (not load-bearing)"
  echo "SELFTEST-OK"; exit 0
fi

export HB_NO_GIT=1
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# a project with real review history: GATE_S (security lens) caught 2 + cleared 1; GATE_C (no lens) cleared 1
proj="$work/p"; bash "$ROOT/plugin/bootstrap.sh" "$proj" >/dev/null 2>&1 </dev/null
printf '%s' '{"phases":[{"id":"S","gate_entry":null,"gate_exit":"GATE_S","tasks":[{"id":"s1"}]},{"id":"C","gate_entry":"GATE_S","gate_exit":"GATE_C","tasks":[{"id":"c1"}]}],"gates":{"GATE_S":{"review":{"profile":"security","prompt":"r"},"criteria":[{"id":"x","cmd":"true"}]},"GATE_C":{"review":{"prompt":"r"},"criteria":[{"id":"x","cmd":"true"}]}}}' > "$proj/.hb/dag.json"
{ echo '{"event":"initialized"}'
  echo '{"event":"review_failed","gate":"GATE_S","note":"hole one: a real gap"}'
  echo '{"event":"review_failed","gate":"GATE_S","note":"hole two: another gap"}'
  echo '{"event":"review_passed","gate":"GATE_S","reviewer":"r","artifact":"reviews/GATE_S.md"}'
  echo '{"event":"review_passed","gate":"GATE_C","reviewer":"r","artifact":"reviews/GATE_C.md"}'
} > "$proj/.hb/events.jsonl"
node "$proj/.hb/hb.js" rebuild >/dev/null 2>&1

pj="$(rimpact_py "$proj/.hb")"; nj="$(rimpact_node "$proj/.hb")"
[ -n "$pj" ] || fail "python produced no refuter-impact summary"
[ "$pj" = "$nj" ] || fail "refuter impact differs node vs python: py=$pj node=$nj"
printf '%s' "$pj" | grep -q '"caught":2' || fail "caught count wrong (expected 2): $pj"
printf '%s' "$pj" | grep -q '"cleared":2' || fail "cleared count wrong (expected 2): $pj"
printf '%s' "$pj" | grep -q '"profile":"security"' || fail "the GATE_S security lens was not recorded: $pj"
printf '%s' "$pj" | grep -q 'hole one: a real gap' || fail "the finding text was not recorded: $pj"
# GATE_C has no profile → null lens, and it cleared (no catch). Structural check, not a
# key-adjacency grep — the summary gained a `models` key (v1.31) that sorts between them.
printf '%s' "$pj" | python3 -c 'import sys,json;d=json.load(sys.stdin);g=[x for x in d["gates"] if x["gate"]=="GATE_C"][0];sys.exit(0 if g["profile"] is None else 1)' \
  || fail "GATE_C should have a null lens: $pj"

# the human render shows the impact section
node "$proj/.hb/hb-report.js" "$proj/.hb" 2>/dev/null | grep -q 'Refuter impact: caught 2' || fail "node render omits the refuter-impact section"
PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli report --dir "$proj" 2>/dev/null | grep -q 'Refuter impact: caught 2' || fail "python render omits the refuter-impact section"

# a project with NO reviews → caught 0, cleared 0, and no section is rendered
clean="$work/clean"; bash "$ROOT/plugin/bootstrap.sh" "$clean" >/dev/null 2>&1 </dev/null
cj="$(rimpact_py "$clean/.hb")"
printf '%s' "$cj" | grep -q '"caught":0' || fail "a review-less project should report caught 0: $cj"
node "$clean/.hb/hb-report.js" "$clean/.hb" 2>/dev/null | grep -q 'Refuter impact' && fail "a review-less project must not render a refuter-impact section"

echo "REFUTER-IMPACT-OK"
