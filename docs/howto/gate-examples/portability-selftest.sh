#!/usr/bin/env bash
# Proof for "Swap workers without changing the DAG": the gate is the contract, the worker is
# swappable. Run the SAME DAG through two DIFFERENT deterministic backends and prove the
# outcome is identical — then prove a worker-COUPLED gate (one that greps a marker only one
# backend writes) is DETECTED (its outcomes diverge). Prints PORTABILITY-OK only when the
# neutral DAG matches across backends AND the coupled DAG is caught.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
# Two genuinely different workers: both satisfy a content gate, but tag the artifact
# differently (so a gate that keys on the tag is worker-coupled).
mkbackend(){ local f="$work/$1.sh"; printf '#!/usr/bin/env bash\ncat >/dev/null\necho "%s ok" > out.txt\necho '\''{"ok":true,"summary":"%s"}'\''\n' "$2" "$1" > "$f"; chmod +x "$f"; echo "$f"; }
A="$(mkbackend backendA AAA)"
B="$(mkbackend backendB BBB)"

mkproj(){ # $1 = gate cmd -> project dir. Build dag.json via python so a gate cmd
  # containing quotes / $PROJECT_DIR is escaped correctly and stays literal.
  local p; p="$(mktemp -d)"; hb init "$p" >/dev/null 2>&1
  GATECMD="$1" python3 -c 'import os,json,sys; json.dump({"phases":[{"id":"A0","gate_entry":None,"gate_exit":"GA0","tasks":[{"id":"A0T1","title":"produce out.txt"}]}],"gates":{"GA0":{"desc":"g","criteria":[{"id":"c","cmd":os.environ["GATECMD"]}]}}}, open(sys.argv[1],"w"))' "$p/.hb/dag.json"
  hb rebuild --dir "$p" >/dev/null 2>&1; echo "$p"
}
outcome(){ # $1 = gate cmd, $2 = backend -> "completed" | "blocked"
  local p; p="$(mkproj "$1")"
  HB_EXEC_CMD="$2" HB_EXEC_MAX_ITERS=25 hb exec run --dir "$p" >/dev/null 2>&1
  if hb state --dir "$p" | python3 -c "import sys,json;sys.exit(0 if 'A0' in json.load(sys.stdin).get('completed_phases',[]) else 1)"
  then echo completed; else echo blocked; fi
  rm -rf "$p"
}

# 1. NEUTRAL: a content gate both workers satisfy -> identical outcome, and it must be the
#    real "completed" (not vacuously-equal "blocked").
nA="$(outcome 'grep -q ok "$PROJECT_DIR/out.txt"' "$A")"
nB="$(outcome 'grep -q ok "$PROJECT_DIR/out.txt"' "$B")"
[ "$nA" = "$nB" ]     || fail "neutral DAG diverged across backends ($nA vs $nB) — not portable"
[ "$nA" = completed ] || fail "neutral DAG did not complete under either backend ($nA) — vacuous match"

# 2. COUPLED: a gate keyed on backend A's private marker -> A completes, B blocks. The
#    divergence is exactly what a portability check must catch. (If the executor leaked
#    backend identity so both matched, this assertion would fail.)
cA="$(outcome 'grep -q AAA "$PROJECT_DIR/out.txt"' "$A")"
cB="$(outcome 'grep -q AAA "$PROJECT_DIR/out.txt"' "$B")"
[ "$cA" = completed ] || fail "coupled DAG did not complete under its own backend A ($cA)"
[ "$cB" = blocked ]   || fail "coupled DAG did not block under backend B ($cB) — coupling not detectable"
[ "$cA" != "$cB" ]    || fail "coupled DAG produced identical outcomes — hidden coupling would go undetected"

echo "PORTABILITY-OK: the same DAG completes under two different workers; a worker-coupled gate diverges (detected)."
