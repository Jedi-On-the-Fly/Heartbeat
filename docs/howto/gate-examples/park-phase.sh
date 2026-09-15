#!/usr/bin/env bash
# Proof for "Park a phase" (hb park / hb unpark): retire a drafted-but-abandoned phase WITHOUT
# deleting it (deletion dangles gate_exit — lint catches that) and WITHOUT hand-editing dag.json:
#   1. park accepts the GATE id too (resolves to the phase that carries it as gate_exit)
#   2. audit SKIPS a parked phase's gate — an unsound parked gate no longer blocks audit-clean —
#      and unpark RESTORES the audit error (reversible, not a deletion)
#   3. the resolver skips a parked phase: its tasks are never offered and all_done is reachable
#   4. report shows the phase as parked (excluded from the % denominator), never silently gone
#   5. --all skips a parked gate even if ARMED (ever-passed), loudly
#   6. an unknown id is refused (exit != 0)
# Prints PARK-PHASE-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }
p="$(mktemp -d)"; trap 'rm -rf "$p"' EXIT
hb init "$p" >/dev/null 2>&1
python3 - "$p" <<'PY'
import json, sys
dag = {"phases": [
    {"id": "P0", "gate_entry": None, "gate_exit": "G0",
     "tasks": [{"id": "T1", "title": "make out.txt", "requires": []}]},
    {"id": "P9", "gate_entry": None, "gate_exit": "GP9",
     "tasks": [{"id": "T9", "title": "future work", "requires": []}]}],
  "gates": {"G0": {"desc": "g", "criteria": [{"id": "c", "cmd": "grep -q ok \"$PROJECT_DIR/out.txt\""}]},
            "GP9": {"desc": "unsound", "criteria": [{"id": "c9", "cmd": "true"}]}}}
json.dump(dag, open(sys.argv[1] + "/.hb/dag.json", "w"))
PY
hb rebuild --dir "$p" >/dev/null 2>&1

# 2-pre. the drafted GP9 is hollow → audit is NOT clean (the situation that forces parking)
hb audit --dir "$p" >/dev/null 2>&1 && fail "precondition: hollow GP9 should fail audit"
# 1 + 2. park BY GATE ID; audit becomes clean and SAYS why
hb park GP9 --reason "refuted as unsound; parked" --dir "$p" >/dev/null 2>&1 || fail "hb park GP9 failed"
hb audit --dir "$p" >/dev/null 2>&1 || fail "audit still fails — a parked phase's gate must be skipped"
hb audit --dir "$p" 2>&1 | grep -qi "parked" || fail "the audit skip is SILENT — it must report the parked phase"
# 6. unknown id refused
hb park NOPE --dir "$p" >/dev/null 2>&1 && fail "parking an unknown id must fail"
# 3. resolver: only P0 offered; after P0 completes, all_done — the parked P9 never blocks the plan
hb next --dir "$p" | grep -q '"T1"' || fail "resolver did not offer T1"
hb next --dir "$p" | grep -q '"T9"' && fail "resolver offered a PARKED phase's task"
hb start T1 --dir "$p" >/dev/null 2>&1; printf 'ok\n' > "$p/out.txt"; hb done T1 --dir "$p" >/dev/null 2>&1
hb gate G0 --dir "$p" >/dev/null 2>&1
hb next --dir "$p" | grep -q 'all_done' || fail "all_done unreachable — the parked phase still blocks the plan"
# 4. report: parked visible, excluded from the denominator (1/1 tasks, 100%)
hb report --json --dir "$p" | python3 -c '
import sys, json
r = json.load(sys.stdin)
assert r["parked"] == ["P9"], r.get("parked")
assert r["tasks_total"] == 1 and r["percent"] == 100, (r["tasks_total"], r["percent"])
assert [p for p in r["phases"] if p["id"] == "P9"][0]["parked"] is True
' || fail "report does not show the parked phase honestly"
# 5. --all: parked GP9 skipped as PARKED; then park the ARMED G0 → sweep skips it too, loudly
hb gate --all --dir "$p" 2>&1 | grep -qi "parked" || fail "--all does not report the parked skip"
hb park P0 --dir "$p" >/dev/null 2>&1 || fail "parking the armed phase failed"
o=$(hb gate --all --dir "$p" 2>&1) || fail "--all failed with everything parked"
echo "$o" | grep -q "re-verifying 0 ever-passed" || fail "an ARMED parked gate was still swept"
hb unpark P0 --dir "$p" >/dev/null 2>&1 || fail "unpark failed"
hb gate --all --dir "$p" 2>&1 | grep -q "re-verifying 1 ever-passed" || fail "unpark did not restore the sweep"
# 2-post. unpark restores the audit error — parking is reversible, not a deletion
hb unpark GP9 --dir "$p" >/dev/null 2>&1 || fail "unpark GP9 failed"
hb audit --dir "$p" >/dev/null 2>&1 && fail "unpark did not restore the audit error — parking must be reversible"

echo "PARK-PHASE-OK: park/unpark by phase or gate id — resolver, audit, report, and the sweep all honor it."
