#!/usr/bin/env bash
# Proof for "Benchmark agents": verifiable-reward + model-regression, both PURE over data.
#  (1) reward: a KNOWN event log (one gate_passed, one gate_failed) must yield exactly the
#      matching labeled records — passed reflects the deterministic LOG verdict (never a
#      self-report), and phase is DERIVED from the dag (it is not on the event).
#  (2) regression: KNOWN scorecards must flag a strictly-worse candidate as regressed and
#      CLEAR an equal one — both directions, so a constant comparator can't pass.
# Prints REWARD-REGRESSION-OK only when every assertion holds.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
export PYTHONPATH="$ROOT/py/src"

d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
mkdir -p "$d/.hb"
cat > "$d/.hb/dag.json" <<'JSON'
{ "phases": [ { "id": "P0", "gate_entry": null, "gate_exit": "G0", "tasks": [] },
              { "id": "P1", "gate_entry": "G0", "gate_exit": "G1", "tasks": [] } ],
  "gates": { "G0": { "criteria": [] }, "G1": { "criteria": [] } } }
JSON
# A known log: G0 passed, G1 failed. actor present on one, absent on the other (honest null).
{ printf '%s\n' '{"event":"initialized"}'
  printf '%s\n' '{"event":"gate_passed","gate":"G0","actor":"worker","ts":"t1"}'
  printf '%s\n' '{"event":"gate_failed","gate":"G1"}'
} > "$d/.hb/events.jsonl"

python3 -m heartbeat.cli reward --dir "$d" --json > "$d/reward.json" 2>/dev/null \
  || { echo "FAIL: hb reward errored"; exit 1; }

python3 - "$d/reward.json" <<'PY' || { echo "FAIL: reward records wrong"; exit 1; }
import sys, json
recs = json.load(open(sys.argv[1]))
by = {r["gate"]: r for r in recs}
assert len(recs) == 2, recs                         # one per gate evaluation, not a count
assert by["G0"]["passed"] is True,  by["G0"]        # deterministic LOG verdict
assert by["G1"]["passed"] is False, by["G1"]
assert by["G0"]["phase"] == "P0", by["G0"]          # phase DERIVED from the dag
assert by["G1"]["phase"] == "P1", by["G1"]
assert by["G0"]["actor"] == "worker", by["G0"]      # actor from the event when present
assert by["G1"]["actor"] is None, by["G1"]          # honestly null when the log has none
PY

python3 - <<'PY' || { echo "FAIL: regression comparator wrong"; exit 1; }
from heartbeat import bench
base  = {"label": "base", "gate_passed": 2, "phases_done": 2, "task_failures": 0}
worse = {"label": "cand-worse", "gate_passed": 0, "phases_done": 0, "task_failures": 3}
equal = {"label": "cand-equal", "gate_passed": 2, "phases_done": 2, "task_failures": 0}
r = bench.regressions([base, worse, equal], "base")
by = {x["candidate"]: x["regressed"] for x in r}
assert by["cand-worse"] is True,  r                 # a strictly-worse candidate regressed
assert by["cand-equal"] is False, r                 # an equal candidate is cleared
PY

echo "REWARD-REGRESSION-OK: reward records carry the log verdict + derived phase; regression flags worse and clears equal."
