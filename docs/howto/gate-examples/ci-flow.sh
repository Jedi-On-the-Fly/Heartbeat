#!/usr/bin/env bash
# Proof for "Run HeartBeat in CI": HeartBeat gates a pipeline by its EXIT CODES, so a CI job
# (audit -> exec) fails the build exactly when the work isn't verified. Prove three exits:
#   1. hb-audit on a hollow DAG exits non-zero  (pre-flight: bad plan fails CI before running),
#   2. a good project's `exec run` exits 0        (verified work -> CI green),
#   3. a project whose gate cannot pass exits non-zero (unverified work -> CI red).
# Prints CI-FLOW-OK only when the good flow is 0 and both failure cases are non-zero.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
AUDIT="$ROOT/plugin/templates/hb-audit.js"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
command -v node    >/dev/null 2>&1 || { echo "node absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
worker="$work/w.sh"; printf '#!/usr/bin/env bash\ncat >/dev/null\necho ok > out.txt\necho '\''{"ok":true,"summary":"d"}'\''\n' > "$worker"; chmod +x "$worker"

mkproj(){ local p; p="$(mktemp -d)"; hb init "$p" >/dev/null 2>&1
  GATE="$1" python3 -c 'import os,json,sys;json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_P0","tasks":[{"id":"T1","title":"produce out.txt"}]}],"gates":{"GATE_P0":{"desc":"g","criteria":[{"id":"c","cmd":os.environ["GATE"]}]}}},open(sys.argv[1],"w"))' "$p/.hb/dag.json"
  hb rebuild --dir "$p" >/dev/null 2>&1; echo "$p"; }

# 1. Pre-flight: a hollow-gate DAG fails the auditor (non-zero) — CI stops before running it.
hollow="$work/hollow.json"
printf '%s' '{"phases":[{"id":"P0","gate_exit":"G","tasks":[{"id":"T1"}]}],"gates":{"G":{"criteria":[{"id":"c","cmd":"true"}]}}}' > "$hollow"
node "$AUDIT" "$hollow" >/dev/null 2>&1 && fail "hb-audit passed a hollow DAG (CI would run a plan that verifies nothing)"

# 2. A good project: exec run exits 0 (verified -> CI green).
p="$(mkproj 'grep -q ok "$PROJECT_DIR/out.txt"')"
HB_EXEC_CMD="$worker" HB_EXEC_MAX_ITERS=25 hb exec run --dir "$p" >/dev/null 2>&1 || fail "a good project's exec run did not exit 0 (CI would be red on verified work)"
rm -rf "$p"

# 3. A project whose gate cannot pass: exec run exits non-zero (unverified -> CI red).
p="$(mkproj false)"
HB_EXEC_CMD="$worker" HB_EXEC_ATTEMPT_CAP=2 HB_EXEC_MAX_ITERS=25 hb exec run --dir "$p" >/dev/null 2>&1 && fail "an unpassable project's exec run exited 0 (CI would be green on unverified work)"
rm -rf "$p"

echo "CI-FLOW-OK: hb-audit fails a hollow DAG, exec run exits 0 on verified work and non-zero on unverified — CI can gate on it."
