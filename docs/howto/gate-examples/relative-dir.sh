#!/usr/bin/env bash
# Proof: a RELATIVE project dir must not break gates. From a parent working directory, a gate
# whose criteria reference $PROJECT_DIR and $HB_DIR passes when driven with a relative dir on
# BOTH runtimes — Python (`hb gate GATE --dir <relative>`) and node (`bash <relative>/.hb/gate.sh`,
# which self-absolutizes and is the parity control). Regression guard for the double-nesting bug
# where a relative dir made PROJECT_DIR/HB_DIR relative and criteria looked in <proj>/<proj>/...
# Prints RELATIVE-DIR-OK only when both runtimes pass.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

HB_NO_GIT=1 bash "$ROOT/plugin/bootstrap.sh" "$tmp/proj" >/dev/null 2>&1 </dev/null
cat > "$tmp/proj/.hb/dag.json" <<'JSON'
{ "phases": [ { "id": "P0", "gate_exit": "GATE_R", "tasks": [ { "id": "P0T1", "title": "produce out.txt" } ] } ],
  "gates": { "GATE_R": { "desc": "relative-dir", "criteria": [
    { "id": "pd", "desc": "PROJECT_DIR resolves", "cmd": "grep -q ok \"$PROJECT_DIR/out.txt\"" },
    { "id": "hd", "desc": "HB_DIR resolves",      "cmd": "test -f \"$HB_DIR/dag.json\"" } ] } } }
JSON
node "$tmp/proj/.hb/hb.js" rebuild >/dev/null 2>&1
printf 'ok\n' > "$tmp/proj/out.txt"

# Python leg — a RELATIVE --dir from the parent cwd (the path that used to double-nest).
py_out=$(cd "$tmp" && HB_NO_GIT=1 PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli gate GATE_R --dir proj 2>&1); py_rc=$?
# Node leg — a RELATIVE gate.sh path from the parent cwd (self-absolutizes; parity control).
node_out=$(cd "$tmp" && HB_NO_GIT=1 bash proj/.hb/gate.sh GATE_R 2>&1); node_rc=$?

[ "$py_rc" -eq 0 ]   || { echo "FAIL: python gate blocked with a relative --dir (rc=$py_rc)";  printf '%s\n' "$py_out"   | tail -3; exit 1; }
[ "$node_rc" -eq 0 ] || { echo "FAIL: node gate blocked with a relative path (rc=$node_rc)";   printf '%s\n' "$node_out" | tail -3; exit 1; }
echo "RELATIVE-DIR-OK: relative-dir gate (PROJECT_DIR + HB_DIR criteria) passes on both python and node."
