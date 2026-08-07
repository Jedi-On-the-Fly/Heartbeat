#!/usr/bin/env bash
# Proof for "Use HeartBeat with Claude Code": the real claude-code adapter drives a task to a
# passing gate. To stay deterministic the CLI is mocked — a stub `claude` on PATH does the
# task and exits 0 — but the adapter (which shells out to `claude`), the driver, and the gate
# are all real. Prints CLAUDE-BACKEND-OK only when the stub-driven run completes AND the
# degrade control (no claude on PATH -> phase does not complete) holds.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
# Stub `claude`: ignore args, do the task (write the artifact), exit 0.
bindir="$work/bin"; mkdir -p "$bindir"
printf '#!/usr/bin/env bash\necho ok > out.txt\nexit 0\n' > "$bindir/claude"; chmod +x "$bindir/claude"

mkproj(){ local p; p="$(mktemp -d)"; hb init "$p" >/dev/null 2>&1
  python3 -c 'import json,sys;json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_P0","tasks":[{"id":"T1","title":"produce out.txt"}]}],"gates":{"GATE_P0":{"desc":"g","criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},open(sys.argv[1],"w"))' "$p/.hb/dag.json"
  hb rebuild --dir "$p" >/dev/null 2>&1; echo "$p"; }
done_P0(){ hb state --dir "$1" | python3 -c "import sys,json;sys.exit(0 if 'P0' in json.load(sys.stdin).get('completed_phases',[]) else 1)"; }

# 1. Stub claude present -> the real claude-code adapter drives the task to a passing gate.
p="$(mkproj)"
PATH="$bindir:$PATH" HB_EXEC_BACKEND=claude-code HB_EXEC_MAX_ITERS=25 hb exec run --dir "$p" >/dev/null 2>&1
done_P0 "$p" || fail "the claude-code adapter did not drive the task to a passing gate with the stub CLI"
rm -rf "$p"

# 2. Control: a claude that FAILS (exits non-zero, does nothing) degrades to a protocol-valid
#    failure and the phase does NOT complete — the driver never fakes completion for a failed
#    worker. (An entirely-absent claude takes the same {ok:false} path via the adapter's
#    which() guard; here claude is installed system-wide, so we mock a failing one instead.)
badbin="$work/badbin"; mkdir -p "$badbin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$badbin/claude"; chmod +x "$badbin/claude"
p="$(mkproj)"
PATH="$badbin:$PATH" HB_EXEC_BACKEND=claude-code HB_EXEC_ATTEMPT_CAP=2 HB_EXEC_MAX_ITERS=25 hb exec run --dir "$p" >/dev/null 2>&1
done_P0 "$p" && fail "control: the phase completed even though claude failed — the driver trusted a failed worker"
rm -rf "$p"

echo "CLAUDE-BACKEND-OK: the real claude-code adapter completes a gated task with a stub CLI; a failing claude does not complete the phase."
