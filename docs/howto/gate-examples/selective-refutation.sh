#!/usr/bin/env bash
# Proof for "Refute high-risk claims, not every task": a review block is a selective lever.
# Adding one to a gate HOLDS the phase after the deterministic gate passes (a second, distinct
# actor must fail to refute before it advances) — a real cost. A phase WITHOUT a review block
# advances on the deterministic pass alone. So you spend refutation only where the risk is.
# Drive the real hb CLI and prove both. Prints SELECTIVE-REFUTATION-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

mkproj(){ # $1 = review block fragment ("" for none) -> project dir
  local p; p="$(mktemp -d)"; hb init "$p" >/dev/null 2>&1
  cat > "$p/.hb/dag.json" <<JSON
{ "phases":[{"id":"P0","gate_entry":null,"gate_exit":"GATE_P0","tasks":[{"id":"T1","title":"do"}]}],
  "gates":{"GATE_P0":{"desc":"g",${1}"criteria":[{"id":"c","cmd":"true"}]}} }
JSON
  hb rebuild --dir "$p" >/dev/null 2>&1
  hb start T1 --dir "$p" >/dev/null 2>&1; hb done T1 --dir "$p" >/dev/null 2>&1; hb gate GATE_P0 --dir "$p" >/dev/null 2>&1
  echo "$p"
}
completed(){ hb state --dir "$1" | python3 -c "import sys,json;sys.exit(0 if 'P0' in json.load(sys.stdin).get('completed_phases',[]) else 1)"; }
pending(){   hb state --dir "$1" | python3 -c "import sys,json;sys.exit(0 if 'GATE_P0' in json.load(sys.stdin).get('pending_reviews',[]) else 1)"; }

# 1. Review-gated phase: deterministic gate passes, but the phase is HELD pending refutation.
p="$(mkproj '"review":{"prompt":"refute"},')"
completed "$p" && fail "a review-gated phase completed on the deterministic pass alone — the review block did not hold it"
pending "$p"   || fail "a review-gated phase whose gate passed is not awaiting review (pending_reviews)"
rm -rf "$p"

# 2. Non-review phase: the same deterministic pass advances it.
p="$(mkproj '')"
completed "$p" || fail "a non-review phase did not complete on its deterministic gate pass"
pending "$p"   && fail "a non-review phase is somehow awaiting a review it never asked for"
rm -rf "$p"

echo "SELECTIVE-REFUTATION-OK: a review block holds a phase pending refutation; a non-review phase advances on the gate pass — apply refutation only where the risk is."
