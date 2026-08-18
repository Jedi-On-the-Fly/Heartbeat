#!/usr/bin/env bash
# Proof for "Recover a dead or corrupted run": the event log is truth, state.json is a
# derived projection. Drive the REAL hb CLI to show the recovery alarms fire and rebuild
# heals — each alarm load-bearing (it would not fire if nothing were wrong):
#   1. DRIFT   — a stale state.json is flagged by doctor; hb rebuild heals it.
#   2. ROT     — deleting a completed gate's artifact is flagged ("no longer reproducible").
#   3. REBUILD — reprojection from the log is faithful and idempotent (two rebuilds equal).
# Prints RECOVERY-GUARDS-OK only when all hold.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
python3 -c "import sys; sys.path.insert(0,'$ROOT/py/src'); import heartbeat" 2>/dev/null || { echo "heartbeat package not importable"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }

proj="$(mktemp -d)"; trap 'rm -rf "$proj"' EXIT
hb init "$proj" >/dev/null 2>&1
cat > "$proj/.hb/dag.json" <<'JSON'
{ "phases": [ { "id": "A0", "gate_entry": null, "gate_exit": "GA0",
               "tasks": [ { "id": "A0T1", "title": "produce artifact.txt" } ] } ],
  "gates": { "GA0": { "desc": "p", "criteria": [ { "id": "c", "cmd": "grep -q ok \"$PROJECT_DIR/artifact.txt\"" } ] } } }
JSON

# Complete the phase: do the work, pass the behavioral gate.
HB_ACTOR=a hb rebuild --dir "$proj" >/dev/null 2>&1
HB_ACTOR=a hb start A0T1 --dir "$proj" >/dev/null 2>&1
printf 'ok\n' > "$proj/artifact.txt"
HB_ACTOR=a hb done A0T1 --dir "$proj" >/dev/null 2>&1
HB_ACTOR=a hb gate GA0 --dir "$proj" >/dev/null 2>&1

completed_A0(){ hb state --dir "$proj" | python3 -c "import sys,json; sys.exit(0 if 'A0' in json.load(sys.stdin).get('completed_phases',[]) else 1)"; }
completed_A0 || { echo "FAIL: setup — phase A0 did not complete"; exit 1; }

# 3. REBUILD writes a faithful, idempotent projection to the state.json FILE. (Assert on the
#    on-disk file rebuild produces — not `hb state`, which always reprojects from the log and
#    would be identical regardless of whether the write worked.) `last_updated` is a wall-clock
#    stamp of WHEN the projection was written (the projection is deterministic *except* that field),
#    so normalize it out before comparing — otherwise two rebuilds straddling a 1-second boundary
#    spuriously differ.
norm(){ python3 -c "import sys,json; d=json.load(sys.stdin); d.pop('last_updated',None); print(json.dumps(d,sort_keys=True))"; }
hb rebuild --dir "$proj" >/dev/null 2>&1; f1="$(norm < "$proj/.hb/state.json")"
hb rebuild --dir "$proj" >/dev/null 2>&1; f2="$(norm < "$proj/.hb/state.json")"
[ "$f1" = "$f2" ] || { echo "FAIL: rebuild's on-disk projection is not idempotent (excluding last_updated)"; exit 1; }
printf '%s' "$f1" | python3 -c "import sys,json; sys.exit(0 if 'A0' in json.load(sys.stdin).get('completed_phases',[]) else 1)" \
  || { echo "FAIL: rebuild wrote a projection missing the completed phase"; exit 1; }

# 1. DRIFT alarm + heal: a stale (valid-JSON) state.json is flagged; rebuild heals it.
printf '{"completed_phases":[],"completed_tasks":[]}' > "$proj/.hb/state.json"
hb doctor --dir "$proj" 2>&1 | grep -qi 'differs from the event-log projection' \
  || { echo "FAIL: doctor did not flag a stale state.json"; exit 1; }
hb rebuild --dir "$proj" >/dev/null 2>&1
hb doctor --dir "$proj" 2>&1 | grep -qi 'differs from the event-log projection' \
  && { echo "FAIL: rebuild did not heal the drift"; exit 1; }

# Control: with an in-sync state.json, the drift alarm must be SILENT (not a constant).
hb doctor --dir "$proj" 2>&1 | grep -qi 'differs from the event-log projection' \
  && { echo "FAIL: drift alarm fires even when in sync (vacuous)"; exit 1; }

# 2. ROT alarm: deleting the completed gate's artifact is flagged as unreproducible.
hb doctor --dir "$proj" 2>&1 | grep -qi 'no longer reproducible' \
  && { echo "FAIL: rot alarm fires before the artifact is deleted (vacuous)"; exit 1; }
rm -f "$proj/artifact.txt"
hb doctor --dir "$proj" 2>&1 | grep -qi 'no longer reproducible' \
  || { echo "FAIL: doctor did not flag the deleted gate artifact as rot"; exit 1; }

echo "RECOVERY-GUARDS-OK: drift flagged + healed, rot flagged, rebuild faithful + idempotent."
