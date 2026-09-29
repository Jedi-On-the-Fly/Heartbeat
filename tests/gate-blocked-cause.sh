#!/usr/bin/env bash
# gate-blocked-cause.sh — a gate blocked by a REFUTED review names that cause. When the criteria pass
# but the adversarial review refuted the phase, `hb exec` must stop with the cause (review_failed) and
# the refuter's finding, and `hb diagnose` must say so too — not "gate errors" / "root-cause each ✗"
# (there is no ✗: the criteria pass). A gate blocked by failing criteria keeps the criteria diagnosis.
# Both runtimes (node hb-exec.js / hb.js, python hb exec / hb diagnose).
#   bash tests/gate-blocked-cause.sh      prints GATE-BLOCKED-CAUSE-OK
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail(){ echo "FAIL: $1"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
PYHB(){ PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli "$@"; }
FINDING="add(2,3) returns 2: the implementation is hard-coded to the single case the gate checks"

mkproj(){ # <dir> <criterion-cmd>
  local P="$1"; mkdir -p "$P"; ( cd "$P" && git init -q && bash "$ROOT/plugin/bootstrap.sh" . >/dev/null 2>&1 )
  python3 - "$P/.hb/dag.json" "$2" <<'EOF'
import json, sys
json.dump({"_meta": {"project": "gate-blocked cause"},
  "gates": {"GATE_A": {"desc": "add(a,b) returns a+b", "review": {"prompt": "Refute that add is correct."},
    "criteria": [{"id": "a1", "desc": "add works on one case", "cmd": sys.argv[2]}]}},
  "phases": [{"id": "A", "title": "add", "gate_entry": None, "gate_exit": "GATE_A",
    "tasks": [{"id": "a", "title": "write m.py", "requires": [], "description": "Write m.py with add(a,b); the gate imports m."}]}]},
  open(sys.argv[1], "w"))
EOF
  cat > "$P/agent.sh" <<EOF
#!/usr/bin/env bash
mode="\${!#}"; cat >/dev/null
case "\$mode" in
  execute) printf 'def add(a,b):\n    return 2\n' > m.py; echo '{"ok":true,"summary":"wrote m.py"}' ;;
  refute)  echo '{"refuted":true,"findings":"$FINDING. REFUTED"}' ;;
  *)       echo '{"error":"unsupported"}' ;;
esac
EOF
  ( cd "$P" && git add -A && git -c user.name=t -c user.email=t@l commit -qm init )
}
OK='cd "$PROJECT_DIR" && python3 -c "import m; assert m.add(1,1)==2"'
BAD='cd "$PROJECT_DIR" && python3 -c "import m; assert m.add(2,3)==5"'

for rt in node python; do
  # 1. criteria pass, review refutes → the stop and the diagnosis name review_failed + the finding
  P="$W/$rt-review"; mkproj "$P" "$OK"
  if [ $rt = node ]; then
    out=$(cd "$P" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $P/agent.sh" timeout 120 node .hb/hb-exec.js run 2>&1)
    diag=$(cd "$P" && node .hb/hb.js diagnose 2>&1)
  else
    out=$(cd "$P" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $P/agent.sh" timeout 120 bash -c "PYTHONPATH='$ROOT/py/src' python3 -m heartbeat.cli exec run --dir '$P'" 2>&1)
    diag=$(PYHB diagnose --dir "$P" 2>&1)
  fi
  grep -Eq '"event": ?"review_failed"' "$P/.hb/events.jsonl" || fail "$rt: setup — no review_failed recorded: $out"
  stop=$(printf '%s\n' "$out" | grep 'HB-EXEC STOP' | tail -1)
  printf '%s' "$stop" | grep -q 'review_failed' || fail "$rt: hb exec stop does not name review_failed: $stop"
  printf '%s' "$stop" | grep -q 'hard-coded' || fail "$rt: hb exec stop does not carry the refuter's finding: $stop"
  printf '%s' "$diag" | grep -q 'Cause: review_failed' || fail "$rt: diagnose does not name the review as the cause: $diag"
  printf '%s' "$diag" | grep -q 'hard-coded' || fail "$rt: diagnose does not show the finding: $diag"
  printf '%s' "$diag" | grep -q 'each ✗' && fail "$rt: diagnose tells to root-cause failing criteria though none fail: $diag"

  # 2. control: criteria fail → the criteria diagnosis, not review_failed
  P="$W/$rt-crit"; mkproj "$P" "$BAD"
  if [ $rt = node ]; then
    out=$(cd "$P" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $P/agent.sh" HB_EXEC_ATTEMPT_CAP=1 timeout 120 node .hb/hb-exec.js run 2>&1)
    diag=$(cd "$P" && node .hb/hb.js diagnose 2>&1)
  else
    out=$(cd "$P" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $P/agent.sh" HB_EXEC_ATTEMPT_CAP=1 timeout 120 bash -c "PYTHONPATH='$ROOT/py/src' python3 -m heartbeat.cli exec run --dir '$P'" 2>&1)
    diag=$(PYHB diagnose --dir "$P" 2>&1)
  fi
  grep -Eq '"event": ?"review_failed"' "$P/.hb/events.jsonl" && fail "$rt: control — a review ran on a failing gate"
  stop=$(printf '%s\n' "$out" | grep 'HB-EXEC STOP' | tail -1)
  printf '%s' "$stop" | grep -q 'review_failed' && fail "$rt: control — a criteria failure was reported as review_failed: $stop"
  printf '%s' "$diag" | grep -q 'Cause: review_failed' && fail "$rt: control — diagnose blamed the review: $diag"
  printf '%s' "$diag" | grep -q '✗' || fail "$rt: control — diagnose lost the failing criterion: $diag"
done
echo "GATE-BLOCKED-CAUSE-OK"
