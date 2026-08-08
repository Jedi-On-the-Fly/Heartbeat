#!/usr/bin/env bash
# Proof for "Handle a successful refutation": when the refuter finds a hole, the phase does NOT
# advance — you fix it and re-verify. Drive the real hb CLI on a review-gated phase:
#   1. the deterministic gate passes -> review owed,
#   2. record a review FAIL (a found hole) -> the phase is HELD (not completed),
#   3. fix + re-run the gate, then a SELF-review pass (same actor as the doer) is rejected,
#   4. a valid review pass (substantive artifact citing the phase, from a DIFFERENT actor)
#      advances the phase.
# Prints HANDLE-REFUTATION-OK only when the fail holds and only a valid distinct-actor pass advances.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }
completed(){ hb state --dir "$1" | python3 -c "import sys,json;sys.exit(0 if 'P0' in json.load(sys.stdin).get('completed_phases',[]) else 1)"; }

p="$(mktemp -d)"; trap 'rm -rf "$p"' EXIT
hb init "$p" >/dev/null 2>&1
cat > "$p/.hb/dag.json" <<'JSON'
{ "phases":[{"id":"P0","gate_entry":null,"gate_exit":"GA0","tasks":[{"id":"T1","title":"do the work"}]}],
  "gates":{"GA0":{"desc":"g","review":{"prompt":"Refute that P0 is done."},"criteria":[{"id":"c","cmd":"true"}]}} }
JSON
hb rebuild --dir "$p" >/dev/null 2>&1

# The doer is 'worker'. Deterministic gate passes -> review owed.
HB_ACTOR=worker hb start T1 --dir "$p" >/dev/null 2>&1
HB_ACTOR=worker hb done  T1 --dir "$p" >/dev/null 2>&1
HB_ACTOR=worker hb gate  GA0 --dir "$p" >/dev/null 2>&1
completed "$p" && fail "a review-gated phase completed on the deterministic pass alone"

# 2. A review FAIL holds the phase.
HB_ACTOR=refuter hb review GA0 fail "hollow test: the gate asserts nothing about the real output" --dir "$p" >/dev/null 2>&1
completed "$p" && fail "the phase advanced despite a review FAIL — a found hole did not hold it"

# 3. After fixing and re-gating, a SELF-review pass (doer == reviewer) is rejected.
art="$p/refutation.md"; printf 'Refutation attempt for GA0: re-inspected T1 against the log and re-ran the gate; the earlier hole is fixed and no new hole remains.\n' > "$art"
HB_ACTOR=worker hb gate GA0 --dir "$p" >/dev/null 2>&1
HB_ACTOR=worker hb review GA0 pass --artifact "$art" --dir "$p" >/dev/null 2>&1 && fail "a self-review (same actor as the doer) was accepted"
completed "$p" && fail "the phase advanced on a self-review"

# 4. A valid pass from a DIFFERENT actor advances the phase.
HB_ACTOR=refuter hb review GA0 pass --artifact "$art" --dir "$p" >/dev/null 2>&1 || fail "a valid distinct-actor review pass was rejected"
completed "$p" || fail "the phase did not advance after a valid refutation pass"

echo "HANDLE-REFUTATION-OK: a review fail holds the phase; a self-review is rejected; a valid distinct-actor pass advances it."
