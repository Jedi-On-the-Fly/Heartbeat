#!/usr/bin/env bash
# Proof for "Use HeartBeat with Codex": the real codex-backend adapter drives a task to a passing
# gate. Live Codex needs auth (and a small local model is flaky through its loop), so — like the
# claude-code backend — the deterministic proof mocks the CLI: a stub `codex` on PATH does the
# task and exits 0, while the real adapter (backends/codex.py, which shells to `codex exec`), the
# driver, and the gate all run. Prints CODEX-BACKEND-OK only when the stub-driven run completes
# AND a failing stub does NOT complete the phase (the driver never fakes completion).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
# Stub `codex`: emulate `codex exec … -C <dir> … <prompt>` — parse -C, write the artifact there,
# exit 0. Reads/ignores stdin so it can't hang (the adapter also passes </dev/null).
bindir="$work/bin"; mkdir -p "$bindir"
cat > "$bindir/codex" <<'STUB'
#!/usr/bin/env bash
dir="."
while [ $# -gt 0 ]; do case "$1" in -C) dir="$2"; shift 2;; *) shift;; esac; done
cat >/dev/null 2>&1 || true
echo ok > "$dir/out.txt"
exit 0
STUB
chmod +x "$bindir/codex"

mkproj(){ local p; p="$(mktemp -d)"; hb init "$p" >/dev/null 2>&1
  python3 -c 'import json,sys;json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_P0","tasks":[{"id":"T1","title":"produce out.txt"}]}],"gates":{"GATE_P0":{"desc":"g","criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},open(sys.argv[1],"w"))' "$p/.hb/dag.json"
  hb rebuild --dir "$p" >/dev/null 2>&1; echo "$p"; }
done_P0(){ hb state --dir "$1" | python3 -c "import sys,json;sys.exit(0 if 'P0' in json.load(sys.stdin).get('completed_phases',[]) else 1)"; }

# 1. Stub codex present -> the real codex adapter drives the task to a passing gate.
p="$(mkproj)"
PATH="$bindir:$PATH" HB_EXEC_BACKEND=codex HB_EXEC_MAX_ITERS=25 hb exec run --dir "$p" >/dev/null 2>&1
done_P0 "$p" || fail "the codex adapter did not drive the task to a passing gate with the stub CLI"
rm -rf "$p"

# 2. Control: a FAILING stub codex (exits 1, writes nothing) -> phase does NOT complete.
badbin="$work/badbin"; mkdir -p "$badbin"
printf '#!/usr/bin/env bash\ncat >/dev/null 2>&1 || true\nexit 1\n' > "$badbin/codex"; chmod +x "$badbin/codex"
p="$(mkproj)"
PATH="$badbin:$PATH" HB_EXEC_BACKEND=codex HB_EXEC_ATTEMPT_CAP=2 HB_EXEC_MAX_ITERS=25 hb exec run --dir "$p" >/dev/null 2>&1
done_P0 "$p" && fail "control: the phase completed even though codex failed — the driver trusted a failed worker"
rm -rf "$p"

echo "CODEX-BACKEND-OK: the real codex adapter completes a gated task with a stub CLI; a failing codex does not complete the phase."
