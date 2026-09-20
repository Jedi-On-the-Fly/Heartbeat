#!/usr/bin/env bash
# Proof: gate criteria are IMMUNE to stdin-slurping commands — found in the field (issue
# 09-heartbeat-gate-stdin-bug): eval_gate streams criteria into a `while read` loop over
# stdin, and run_criterion's PRIMARY (timeout(1)) branch ran criteria without redirecting
# stdin — so a criterion that reads stdin (docker compose exec -T, psql, ssh, anything
# slurping) ATE the remaining criteria records. Those criteria were never executed, never
# reported, never counted: the gate printed "N passed, 0 failed" and PASSED on partial
# evidence — silent, fail-open, and position-dependent (everything after the first slurper
# was lost). The fallback branch always guarded this (</dev/null, with a comment naming the
# hazard); the branch that runs wherever coreutils exists did not.
#   1. NODE: a gate [true, slurper, false] must evaluate ALL THREE criteria and BLOCK —
#      the criterion after the slurper is the one that fails.
#   2. NODE: the reported result-line count equals the DAG's criteria count (count honesty).
#   3. PYTHON: criteria run with stdin at /dev/null too (mirrored contract) — a slurper
#      completes instantly instead of reading the caller's stdin, and `read x` sees EOF.
# --selftest: strip the </dev/null from the primary branch on a COPY — the skip must
# reappear and be caught (the assertion is load-bearing). Prints GATE-STDIN-IMMUNE-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR PROJECT_DIR GATE G 2>/dev/null || true
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

mkproj(){ # $1 dir
  mkdir -p "$1/.hb"
  cp "$ROOT/plugin/templates/gate.sh" "$ROOT/plugin/templates/hb.js" \
     "$ROOT/plugin/templates/hb-lint.js" "$ROOT/plugin/templates/hb-next-task.js" "$1/.hb/"
  printf '%s' '{"phases":[{"id":"P0","gate_entry":null,"gate_exit":"G_EAT","tasks":[{"id":"T1","title":"t","requires":[]}]}],"gates":{"G_EAT":{"desc":"slurper mid-gate","criteria":[{"id":"c1","desc":"passes","cmd":"true"},{"id":"c2","desc":"slurps stdin like docker exec -T / psql","cmd":"cat >/dev/null"},{"id":"c3","desc":"MUST still run and fail","cmd":"false"}]}}}' > "$1/.hb/dag.json"
  printf '%s\n' '{"event":"initialized"}' > "$1/.hb/events.jsonl"
}

p="$(mktemp -d)"; trap 'rm -rf "$p"' EXIT
mkproj "$p"

# ── 1+2. node: all three criteria evaluated; the post-slurper failure BLOCKS the gate ──
o=$(bash "$p/.hb/gate.sh" --check G_EAT 2>&1); rc=$?
n=$(printf '%s\n' "$o" | grep -c '^  [✓✗]')
[ "$n" -eq 3 ] || fail "node evaluated $n of 3 criteria — the slurper ATE the rest (silent fail-open skip): $o"
[ "$rc" -ne 0 ] || fail "node gate PASSED with a failing criterion after the slurper"
printf '%s\n' "$o" | grep -q '✗ \[c3\]' || fail "node: c3 (after the slurper) was not the reported failure"

# ── 3. python: same stdin contract — slurper instant, read sees EOF ──────────
py="$p/py"; mkproj "$py"
o=$(hb gate G_EAT --check --dir "$py" 2>&1); rc=$?
n=$(printf '%s\n' "$o" | grep -c '^  [✓✗]')
[ "$n" -eq 3 ] || fail "python evaluated $n of 3 criteria: $o"
[ "$rc" -ne 0 ] || fail "python gate passed with a failing criterion"
python3 - "$py" <<'PY'
import json, sys
f = sys.argv[1] + "/.hb/dag.json"
d = json.load(open(f))
d["gates"]["G_EAT"]["criteria"] = [{"id": "r1", "desc": "read must see EOF, not the caller's stdin", "cmd": "read -r x"}]
json.dump(d, open(f, "w"))
PY
printf 'SHOULD-NOT-BE-READ\n' | hb gate G_EAT --check --dir "$py" >/dev/null 2>&1 \
  && fail "python: a criterion READ the caller's stdin (read -r x succeeded) — stdin must be /dev/null"

# ── --selftest: the guard is load-bearing (mutation: strip </dev/null, skip must reappear) ──
if [ "${1:-}" = "--selftest" ]; then
  if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
    echo "  (no timeout/gtimeout — the primary branch can't be exercised here; mutant leg skipped)"
    echo "SELFTEST-OK: fallback-branch guard exercised; mutant leg skipped (no timeout binary)."
    exit 0
  fi
  m="$p/mut"; mkproj "$m"
  sed 's|"${t}s" bash -c "$1" </dev/null|"${t}s" bash -c "$1"|' "$m/.hb/gate.sh" > "$m/.hb/gate.mut.sh"
  cmp -s "$m/.hb/gate.sh" "$m/.hb/gate.mut.sh" && { echo "SELFTEST-ESCAPED: mutation did not apply (guard line not found?)"; exit 1; }
  mo=$(bash "$m/.hb/gate.mut.sh" --check G_EAT 2>&1); mrc=$?
  mn=$(printf '%s\n' "$mo" | grep -c '^  [✓✗]')
  if [ "$mn" -eq 3 ] && [ "$mrc" -ne 0 ]; then
    echo "SELFTEST-ESCAPED: the unguarded mutant did NOT reproduce the skip — the assertion is not pinning the guard"
    exit 1
  fi
  echo "SELFTEST-CAUGHT: mutant evaluated $mn/3 (rc=$mrc) — the </dev/null guard is load-bearing."
  echo "SELFTEST-OK: skip reappears without the guard; count + verdict checks bite."
  exit 0
fi

echo "GATE-STDIN-IMMUNE-OK: a slurping criterion cannot eat its successors (node), stdin is /dev/null on both runtimes, counts are honest."
