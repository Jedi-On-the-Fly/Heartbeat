#!/usr/bin/env bash
# Proof for "HeartBeat in 5 minutes": the whole first-run cycle actually works end to end —
# init a project, author a one-phase DAG with a behavioral gate, drive it with a worker, and
# the phase completes because the gate passed. Uses a deterministic script backend (so the
# proof is reproducible), but drives the REAL init/exec/gate path. Prints QUICKSTART-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
# A worker that does the task: writes the artifact the gate checks.
worker="$work/worker.sh"; printf '#!/usr/bin/env bash\ncat >/dev/null\necho ok > out.txt\necho '\''{"ok":true,"summary":"wrote out.txt"}'\''\n' > "$worker"; chmod +x "$worker"
# A worker that does NOT do the task (control).
idle="$work/idle.sh";     printf '#!/usr/bin/env bash\ncat >/dev/null\necho '\''{"ok":true,"summary":"did nothing"}'\''\n' > "$idle"; chmod +x "$idle"

mkproj(){ local p; p="$(mktemp -d)"; hb init "$p" >/dev/null 2>&1
  python3 -c 'import json,sys;json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_P0","tasks":[{"id":"P0T1","title":"produce out.txt"}]}],"gates":{"GATE_P0":{"desc":"the work is done","criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},open(sys.argv[1],"w"))' "$p/.hb/dag.json"
  hb rebuild --dir "$p" >/dev/null 2>&1; echo "$p"; }
done_P0(){ hb state --dir "$1" | python3 -c "import sys,json;sys.exit(0 if 'P0' in json.load(sys.stdin).get('completed_phases',[]) else 1)"; }

# The 5-minute cycle: init -> author -> drive -> gate -> done.
p="$(mkproj)"
HB_EXEC_CMD="$worker" HB_EXEC_MAX_ITERS=25 hb exec run --dir "$p" >/dev/null 2>&1
done_P0 "$p" || fail "the quickstart cycle did not complete the phase (gate did not pass)"
rm -rf "$p"

# Control: a worker that doesn't produce the artifact must NOT complete the phase (the gate
# is real, not a rubber stamp).
p="$(mkproj)"
HB_EXEC_CMD="$idle" HB_EXEC_ATTEMPT_CAP=2 HB_EXEC_MAX_ITERS=25 hb exec run --dir "$p" >/dev/null 2>&1
done_P0 "$p" && fail "control: the phase completed even though the worker did nothing — the gate is hollow"
rm -rf "$p"

echo "QUICKSTART-OK: init -> author -> drive -> gate -> done; and a worker that does nothing does not complete the phase."
