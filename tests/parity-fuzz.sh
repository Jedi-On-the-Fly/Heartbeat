#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# Parity as a differential-testing ORACLE. Instead of a handful of fixed fixtures
# (tests/parity.sh), a seeded generator (tests/gen-parity-case.py) produces many
# structurally-varied, WELL-FORMED cases and we assert the node+bash plugin and the
# pure-Python port AGREE on every shared pure surface for each one. Two implementations
# of one spec are each other's oracle: any disagreement on a generated case is a real bug
# neither suite's fixtures happened to hit.
#
# Usage:
#   parity-fuzz.sh [N]        # fuzz N seeds (default 12); prints FUZZ-PARITY-OK:<N> if all agree
#   parity-fuzz.sh --selftest # prove the oracle has teeth: green on real py/src, red on a mutant
#
# HB_PY_SRC overrides the Python runtime under test (default py/src) — the same seam
# tests/parity.sh uses, so the mutation self-test can point it at a deliberately-broken copy.
# ══════════════════════════════════════════════════════════════════════════════
set -u
# Env hygiene: never inherit a calling gate's project pointers (same rule as run-tests.sh).
unset HB_DIR PROJECT_DIR GATE G DAG_FILE EVENTS_FILE 2>/dev/null || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent — fuzz skipped"; exit 0; }
command -v node    >/dev/null 2>&1 || { echo "node absent — fuzz skipped";    exit 0; }
PY="PYTHONPATH=${HB_PY_SRC:-$ROOT/py/src} python3 -m heartbeat.cli"
GEN="$ROOT/tests/gen-parity-case.py"

# --- normalizers: identical to tests/parity.sh so node and python are compared apples-to-apples
a_node(){ node "$ROOT/plugin/templates/hb-audit.js" "$1" --json | node -pe 'const d=JSON.parse(require("fs").readFileSync(0));JSON.stringify([d.errors,d.warns,d.findings.map(x=>x.rule).sort()])'; }
a_py(){   eval "$PY audit \"$1\" --json" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(json.dumps([d["errors"],d["warns"],sorted(x["rule"] for x in d["findings"])],separators=(",",":"),ensure_ascii=False))'; }
l_node(){ node "$ROOT/plugin/templates/hb-lint.js" "$1" --json | node -pe 'JSON.stringify(JSON.parse(require("fs").readFileSync(0)).errors.sort())'; }
l_py(){   eval "$PY lint \"$1\" --json" | python3 -c 'import sys,json;print(json.dumps(sorted(json.load(sys.stdin)["errors"]),separators=(",",":"),ensure_ascii=False))'; }

# Run one generated case ($d) through every shared surface on both runtimes; echo the first
# diverging surface name, or nothing if all agree.
run_case(){ # dir
  local d="$1" n p
  # Recompute PY from the CURRENT HB_PY_SRC each call (dynamic scope reaches a_py/l_py too),
  # so the mutation self-test's mutant runtime is actually exercised.
  local PY="PYTHONPATH=${HB_PY_SRC:-$ROOT/py/src} python3 -m heartbeat.cli"
  cp "$ROOT/plugin/templates/hb.js" "$ROOT/plugin/templates/hb-lint.js" \
     "$ROOT/plugin/templates/hb-next-task.js" "$ROOT/plugin/templates/hb-report.js" \
     "$ROOT/plugin/templates/gate.sh" "$d/.hb/"
  node "$d/.hb/hb.js" rebuild >/dev/null 2>&1

  [ "$(a_node "$d/.hb/dag.json")" = "$(a_py "$d/.hb/dag.json")" ] || { echo audit; return; }
  [ "$(l_node "$d/.hb/dag.json")" = "$(l_py "$d/.hb/dag.json")" ] || { echo lint; return; }

  n=$(node "$d/.hb/hb.js" state | node -pe 'const s=JSON.parse(require("fs").readFileSync(0));JSON.stringify([s.completed_tasks.sort(),s.completed_phases.sort(),s.pending_reviews.sort(),s.build_stuck_count,s.current_phase])')
  p=$(eval "$PY state --dir \"$d\"" | python3 -c 'import sys,json;s=json.load(sys.stdin);print(json.dumps([sorted(s["completed_tasks"]),sorted(s["completed_phases"]),sorted(s["pending_reviews"]),s["build_stuck_count"],s["current_phase"]],separators=(",",":"),ensure_ascii=False))')
  [ "$n" = "$p" ] || { echo state; return; }

  n=$(node "$d/.hb/hb-next-task.js" "$d/.hb/state.json" | node -pe 'const d=JSON.parse(require("fs").readFileSync(0))||{};JSON.stringify([d.type||"task",d.id||"",d.gate||"",d.phase||""])')
  p=$(eval "$PY next --dir \"$d\"" | python3 -c 'import sys,json;d=json.load(sys.stdin) or {};print(json.dumps([d.get("type","task"),d.get("id",""),d.get("gate",""),d.get("phase","")],separators=(",",":"),ensure_ascii=False))')
  [ "$n" = "$p" ] || { echo next; return; }

  n=$(node "$d/.hb/hb.js" ready 9 | node -pe 'JSON.stringify(JSON.parse(require("fs").readFileSync(0)).map(t=>t.id).sort())')
  p=$(eval "$PY ready 9 --dir \"$d\"" | python3 -c 'import sys,json;print(json.dumps(sorted(t["id"] for t in json.load(sys.stdin)),separators=(",",":"),ensure_ascii=False))')
  [ "$n" = "$p" ] || { echo ready; return; }

  n=$(node "$d/.hb/hb-report.js" "$d/.hb" --json | node -pe 'const p=JSON.parse(require("fs").readFileSync(0)).progress;JSON.stringify([p.done,p.total,p.pct])')
  p=$(eval "$PY report --dir \"$d\" --json" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(json.dumps([d["tasks_done"],d["tasks_total"],d["percent"]],separators=(",",":"),ensure_ascii=False))')
  [ "$n" = "$p" ] || { echo report; return; }

  n=$(node "$d/.hb/hb.js" diagnose 2>/dev/null | head -1)
  p=$(eval "$PY diagnose --dir \"$d\"" 2>/dev/null | head -1)
  [ "$n" = "$p" ] || { echo diagnose; return; }
}

# Fuzz N seeds. Echoes a divergence report + returns 1 on the first mismatch; 0 if all agree.
fuzz(){ # n_seeds  quiet
  local n="$1" quiet="${2:-}" seed d surf
  for seed in $(seq 0 $((n - 1))); do
    d="$(mktemp -d)"
    python3 "$GEN" "$seed" "$d" || { echo "gen failed (seed $seed)"; rm -rf "$d"; return 1; }
    surf="$(run_case "$d")"
    rm -rf "$d"
    if [ -n "$surf" ]; then
      echo "  ✗ seed $seed diverged on: $surf"
      return 1
    fi
    [ -n "$quiet" ] || echo "  ✓ seed $seed"
  done
  return 0
}

# ── mode: mutation self-test ─────────────────────────────────────────────────
# Bind the teeth: (1) the fuzzer must be legitimately GREEN on the real py/src, then
# (2) RED on a mutant (a phantom lint error, the tests/parity.sh self-test's technique).
# Requiring BOTH markers from ONE run means an unconditional echo cannot satisfy poc2.
if [ "${1:-}" = "--selftest" ]; then
  SEEDS=4
  if fuzz "$SEEDS" quiet; then
    echo "SELFTEST-CLEAN-OK: fuzzer green on real py/src across $SEEDS seeds"
  else
    echo "SELFTEST-FAIL: fuzzer is not green on the real runtime — cannot self-test"; exit 1
  fi
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  cp -r "$ROOT/py/src" "$tmp/src"
  cat >> "$tmp/src/heartbeat/lint.py" <<'PY'

_orig_lint = lint
def lint(dag):
    r = dict(_orig_lint(dag))
    r["errors"] = list(r["errors"]) + ["ZZZ-fuzz-selftest-divergence"]
    return r
PY
  surf=""
  for seed in $(seq 0 $((SEEDS - 1))); do
    d="$(mktemp -d)"
    python3 "$GEN" "$seed" "$d" >/dev/null 2>&1
    s="$(HB_PY_SRC="$tmp/src" run_case "$d")"
    rm -rf "$d"
    [ -n "$s" ] && { surf="$s"; break; }
  done
  if [ -z "$surf" ]; then
    echo "SELFTEST-ESCAPED: fuzzer did NOT catch an injected node<->python divergence"; exit 1
  fi
  echo "SELFTEST-CAUGHT:$surf — fuzzer flags an injected divergence on the $surf surface"
  exit 0
fi

# ── mode: fuzz N seeds ───────────────────────────────────────────────────────
N="${1:-12}"
echo "── parity fuzz ($N seeds) ──"
if fuzz "$N"; then
  echo "FUZZ-PARITY-OK:$N — node ≡ python across $N generated cases"
  exit 0
else
  echo "❌ FUZZ-PARITY DIVERGENCE"
  exit 1
fi
