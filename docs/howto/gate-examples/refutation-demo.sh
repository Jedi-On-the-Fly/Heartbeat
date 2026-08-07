#!/usr/bin/env bash
# Proof for "Add refutation to a sensitive gate": drive the REAL hb review guard through
# the public CLI and show a review pass reduces to evidence, not assertion. In a throwaway
# project we bring a review-gated phase to review_pending, then check the four outcomes:
#   1. pass with NO --artifact           -> rejected
#   2. pass with a thin/anchorless file  -> rejected
#   3. pass as a SELF-review (same actor as the doer) -> rejected
#   4. pass with a substantive, phase-anchored artifact from a DIFFERENT actor -> accepted
# Prints REFUTATION-GUARDS-OK only when all four hold. This drives heartbeat.cli directly —
# the authoritative tests are py/tests/test_hardening.py.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PY="$ROOT/py/src"
export PYTHONPATH="$PY" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
python3 -c "import sys; sys.path.insert(0,'$PY'); import heartbeat" 2>/dev/null || { echo "heartbeat package not importable"; exit 1; }

hb(){ python3 -m heartbeat.cli "$@"; }
proj="$(mktemp -d)"
trap 'rm -rf "$proj"' EXIT

# A one-phase project whose gate is behavioral AND review-gated.
hb init "$proj" >/dev/null 2>&1
cat > "$proj/.hb/dag.json" <<'JSON'
{ "phases": [ { "id": "A0", "gate_entry": null, "gate_exit": "GA0",
               "tasks": [ { "id": "A0T1", "title": "write A0T1 to done.log" } ] } ],
  "gates": { "GA0": { "desc": "p", "review": { "prompt": "Refute A0." },
                      "criteria": [ { "id": "c", "cmd": "grep -q A0T1 \"$PROJECT_DIR/done.log\"" } ] } } }
JSON

# Do the work as actor agent-A, then pass the deterministic gate -> review_pending.
HB_ACTOR=agent-A hb rebuild --dir "$proj" >/dev/null 2>&1
HB_ACTOR=agent-A hb start A0T1 --dir "$proj" >/dev/null 2>&1
printf 'A0T1\n' > "$proj/done.log"
HB_ACTOR=agent-A hb done A0T1 --dir "$proj" >/dev/null 2>&1
HB_ACTOR=agent-A hb gate GA0 --dir "$proj" >/dev/null 2>&1

anchored="$proj/real.md"
printf 'Refutation for GA0: inspected A0T1 in done.log and re-ran the behavioral gate. No hole found.\n' > "$anchored"
printf 'ok\n' > "$proj/thin.md"

done_now(){ hb state --dir "$proj" 2>/dev/null | python3 -c "import sys,json; sys.exit(0 if 'A0' in json.load(sys.stdin).get('completed_phases',[]) else 1)"; }

# 1. no artifact -> rejected (nonzero) and phase NOT complete
HB_ACTOR=agent-B hb review GA0 pass --dir "$proj" >/dev/null 2>&1 && { echo "FAIL: no-artifact pass accepted"; exit 1; }
# 2. thin artifact -> rejected
HB_ACTOR=agent-B hb review GA0 pass --artifact "$proj/thin.md" --dir "$proj" >/dev/null 2>&1 && { echo "FAIL: thin artifact accepted"; exit 1; }
# 3. self-review (doer agent-A reviewing own work) -> rejected
HB_ACTOR=agent-A hb review GA0 pass --artifact "$anchored" --dir "$proj" >/dev/null 2>&1 && { echo "FAIL: self-review accepted"; exit 1; }
done_now && { echo "FAIL: phase advanced before a valid review"; exit 1; }
# 4. distinct actor + substantive, anchored artifact -> accepted, phase completes
HB_ACTOR=agent-B hb review GA0 pass --artifact "$anchored" --dir "$proj" >/dev/null 2>&1 || { echo "FAIL: valid distinct-actor review rejected"; exit 1; }
done_now || { echo "FAIL: phase did not advance after a valid review"; exit 1; }

echo "REFUTATION-GUARDS-OK: no-artifact, thin, and self-review rejected; distinct-actor anchored artifact accepted."
