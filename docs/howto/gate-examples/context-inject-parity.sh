#!/usr/bin/env bash
# Proof: the GENERIC context hook injects a configured context_cmd's output into the task payload
# IDENTICALLY on both runtimes — for an exit-0 command AND a command that emits output then exits
# NONZERO (a common real case: a provider that warns-and-exits-nonzero; execSync throws while
# subprocess.run does not, so the runtimes must be reconciled). The context_cmd is a generic,
# NON-CODE command (echo CODECTX:<id>) — its non-code-ness proves the hook is generic. A stub
# backend captures the dispatched payload's `context`. We compare ONLY the delimited injected block
# (node's assembleContext appends a git-log block python does not — a pre-existing node-only
# divergence, so whole-context equality would be environment-fragile).
# Prints CONTEXT-INJECT-PARITY-OK. Fails before the executor hook exists (spec-first).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# exit-0 provider stub, and an emit-then-nonzero-exit stub (both generic, non-code)
printf '#!/usr/bin/env bash\necho "CODECTX:${HB_TASK_ID}"\n'          > "$tmp/ctx.sh";      chmod +x "$tmp/ctx.sh"
printf '#!/usr/bin/env bash\necho "CODECTX:${HB_TASK_ID}"\nexit 3\n'  > "$tmp/ctx_fail.sh"; chmod +x "$tmp/ctx_fail.sh"
# backend stub: read payload JSON on stdin (the wire protocol), write its .context to $OUTFILE.
cat > "$tmp/backend.sh" <<'EOF'
#!/usr/bin/env bash
python3 -c 'import sys,json; p=json.load(sys.stdin); open(sys.argv[1],"w").write(p.get("context","")); print(json.dumps({"ok":True,"summary":"stub"}))' "$OUTFILE"
EOF
chmod +x "$tmp/backend.sh"

extract(){ awk '/<<HB-CONTEXT>>/{f=1;next} /<\/HB-CONTEXT>>/{f=0} f' "$1"; }

# run one task through BOTH executors, each with a FRESH project (each mutates its own state — a
# shared project would make the legs dispatch different tasks), and compare the injected block.
assert_parity(){   # $1 = context_cmd stub  $2 = scenario label
  local pn pp nout pout nblk pblk
  pn="$(mktemp -d)"; pp="$(mktemp -d)"
  HB_NO_GIT=1 bash "$ROOT/plugin/bootstrap.sh" "$pn/x" >/dev/null 2>&1 </dev/null
  HB_NO_GIT=1 bash "$ROOT/plugin/bootstrap.sh" "$pp/x" >/dev/null 2>&1 </dev/null
  nout="$pn/ctx.out"; pout="$pp/ctx.out"
  OUTFILE="$nout" HB_EXEC_CMD="bash $tmp/backend.sh" HB_EXEC_CONTEXT_CMD="bash $1" \
    HB_EXEC_MAX_ITERS=1 HB_NO_GIT=1 node "$pn/x/.hb/hb-exec.js" run >/dev/null 2>&1 || true
  OUTFILE="$pout" HB_EXEC_CMD="bash $tmp/backend.sh" HB_EXEC_CONTEXT_CMD="bash $1" \
    HB_EXEC_MAX_ITERS=1 HB_NO_GIT=1 PYTHONPATH="$ROOT/py/src" \
    python3 -m heartbeat.cli exec run --dir "$pp/x" >/dev/null 2>&1 || true
  [ -s "$nout" ] && [ -s "$pout" ] || { echo "FAIL[$2]: a leg captured no context"; rm -rf "$pn" "$pp"; exit 1; }
  nblk="$(extract "$nout")"; pblk="$(extract "$pout")"; rm -rf "$pn" "$pp"
  echo "$nblk" | grep -q 'CODECTX:' || { echo "FAIL[$2]: node did not inject the context_cmd output"; exit 1; }
  echo "$pblk" | grep -q 'CODECTX:' || { echo "FAIL[$2]: python did not inject the context_cmd output"; exit 1; }
  [ "$nblk" = "$pblk" ] || { echo "FAIL[$2]: injected block differs node vs python"; printf 'NODE=[%s]\nPY=[%s]\n' "$nblk" "$pblk"; exit 1; }
}

assert_parity "$tmp/ctx.sh"      "exit0"
assert_parity "$tmp/ctx_fail.sh" "nonzero-exit"

echo "CONTEXT-INJECT-PARITY-OK"
