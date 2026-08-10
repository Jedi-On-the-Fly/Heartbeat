#!/usr/bin/env bash
# Parity of DOCTOR / rot detection: both runtimes must agree on whether a completed phase's gate
# is still reproducible. The tick keys off doctor's rot output, so a divergence here would wake the
# two runtimes differently. A completed phase whose gate references a now-deleted file is rot.
# Prints DOCTOR-PARITY-OK only when: clean project -> 0 rot on both; rotted -> >0 rot on both.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

HB_NO_GIT=1 bash "$ROOT/plugin/bootstrap.sh" "$tmp/proj" >/dev/null 2>&1 </dev/null
DAG='{"phases":[{"id":"P0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"P0T1","title":"produce out.txt","requires":[]}]}],"gates":{"G0":{"desc":"g","criteria":[{"id":"c","desc":"d","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}}'
printf '%s' "$DAG" > "$tmp/proj/.hb/dag.json"
printf '%s\n' '{"event":"initialized"}' '{"event":"task_done","task":"P0T1"}' '{"event":"gate_passed","gate":"G0"}' > "$tmp/proj/.hb/events.jsonl"
node "$tmp/proj/.hb/hb.js" rebuild >/dev/null 2>&1

rot_node() { HB_NO_GIT=1 node "$tmp/proj/.hb/hb.js" doctor 2>&1 | grep -ci 'reproduc'; }
rot_py()   { HB_NO_GIT=1 PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli doctor --dir "$tmp/proj" 2>&1 | grep -ci 'reproduc'; }

# clean: the gate's file exists -> no rot on either runtime
printf 'ok\n' > "$tmp/proj/out.txt"
cn=$(rot_node); cp=$(rot_py)
[ "$cn" -eq 0 ] && [ "$cp" -eq 0 ] || { echo "FAIL: clean project flagged rot (node=$cn python=$cp)"; exit 1; }
echo "  ok [clean] node=$cn python=$cp"

# rotted: delete the completed gate's file -> rot on BOTH
rm -f "$tmp/proj/out.txt"
rn=$(rot_node); rp=$(rot_py)
[ "$rn" -gt 0 ] && [ "$rp" -gt 0 ] || { echo "FAIL: rot not detected on both (node=$rn python=$rp)"; exit 1; }
echo "  ok [rotted] node=$rn python=$rp"

echo "DOCTOR-PARITY-OK: node ≡ python on rot detection (clean -> none; deleted gate file -> flagged on both)."
