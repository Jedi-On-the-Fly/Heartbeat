#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# Parity test — the node+bash plugin and the pure-Python port (py/) must AGREE on
# the pure functions for the same inputs: lint (errors), audit (findings), and the
# state projection. Exit non-zero on any divergence. Skips cleanly without python3.
# Usage: bash tests/parity.sh
# ══════════════════════════════════════════════════════════════════════════════
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent — parity skipped"; exit 0; }
FAIL=0
PY="PYTHONPATH=$ROOT/py/src python3 -m heartbeat.cli"

# --- audit parity (errors, warns, sorted rule set) ---
a_node(){ node "$ROOT/plugin/templates/hb-audit.js" "$1" --json | node -pe 'const d=JSON.parse(require("fs").readFileSync(0));JSON.stringify([d.errors,d.warns,d.findings.map(x=>x.rule).sort()])'; }
a_py(){ eval "$PY audit \"$1\" --json" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(json.dumps([d["errors"],d["warns"],sorted(x["rule"] for x in d["findings"])],separators=(",",":"),ensure_ascii=False))'; }

# --- lint parity (sorted error strings) ---
l_node(){ node "$ROOT/plugin/templates/hb-lint.js" "$1" --json | node -pe 'JSON.stringify(JSON.parse(require("fs").readFileSync(0)).errors.sort())'; }
l_py(){ eval "$PY lint \"$1\" --json" | python3 -c 'import sys,json;print(json.dumps(sorted(json.load(sys.stdin)["errors"]),separators=(",",":"),ensure_ascii=False))'; }

cmp(){ # label nodeval pyval
  if [ "$2" = "$3" ]; then echo "  ✓ $1"; else echo "  ✗ $1"$'\n'"      node=$2"$'\n'"      py=  $3"; FAIL=1; fi
}

echo "── audit parity ──"
for f in hollow existence nondeterministic good; do
  cmp "audit:$f" "$(a_node "$ROOT/planning/audit-fixtures/$f.json")" "$(a_py "$ROOT/planning/audit-fixtures/$f.json")"
done

echo "── lint parity ──"
cmp "lint:broken" "$(l_node "$ROOT/planning/parity-fixtures/broken.json")" "$(l_py "$ROOT/planning/parity-fixtures/broken.json")"
for f in good hollow; do
  cmp "lint:$f" "$(l_node "$ROOT/planning/audit-fixtures/$f.json")" "$(l_py "$ROOT/planning/audit-fixtures/$f.json")"
done

echo "── state projection parity ──"
DAG='{"phases":[{"id":"P0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"P0T1","requires":[]},{"id":"P0T2","requires":["P0T1"]}]},{"id":"P1","gate_entry":"G0","gate_exit":"G1","tasks":[{"id":"P1T1","requires":[]}]}],"gates":{"G0":{"criteria":[{"id":"c","cmd":"true"}]},"G1":{"review":{"prompt":"r"},"criteria":[{"id":"c","cmd":"true"}]}}}'
state_case(){ # name events
  local d; d=$(mktemp -d); mkdir "$d/.hb"
  printf '%s' "$DAG" > "$d/.hb/dag.json"
  printf '%s\n' "$2" > "$d/.hb/events.jsonl"
  cp "$ROOT/plugin/templates/hb.js" "$ROOT/plugin/templates/hb-lint.js" "$ROOT/plugin/templates/hb-next-task.js" "$d/.hb/"
  node "$d/.hb/hb.js" rebuild >/dev/null 2>&1
  local n p
  n=$(node "$d/.hb/hb.js" state | node -pe 'const s=JSON.parse(require("fs").readFileSync(0));JSON.stringify([s.completed_tasks.sort(),s.completed_phases.sort(),s.pending_reviews.sort(),s.build_stuck_count,s.current_phase])')
  p=$(eval "$PY state --dir \"$d\"" | python3 -c 'import sys,json;s=json.load(sys.stdin);print(json.dumps([sorted(s["completed_tasks"]),sorted(s["completed_phases"]),sorted(s["pending_reviews"]),s["build_stuck_count"],s["current_phase"]],separators=(",",":"),ensure_ascii=False))')
  cmp "state:$1" "$n" "$p"
  rm -rf "$d"
}
state_case "fresh"        '{"event":"initialized"}'
state_case "p0-gated"     '{"event":"initialized"}
{"event":"task_done","task":"P0T1"}
{"event":"task_done","task":"P0T2"}
{"event":"gate_passed","gate":"G0"}'
state_case "review-owed"  '{"event":"initialized"}
{"event":"task_done","task":"P0T1"}
{"event":"task_done","task":"P0T2"}
{"event":"gate_passed","gate":"G0"}
{"event":"task_done","task":"P1T1"}
{"event":"gate_passed","gate":"G1"}'
state_case "two-fails"    '{"event":"initialized"}
{"event":"task_failed","task":"P0T1"}
{"event":"task_failed","task":"P0T1"}'

echo ""
[ "$FAIL" -eq 0 ] && { echo "✅ PARITY OK — node ≡ python"; exit 0; } || { echo "❌ PARITY DIVERGENCE"; exit 1; }
