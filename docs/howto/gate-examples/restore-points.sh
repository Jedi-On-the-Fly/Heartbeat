#!/usr/bin/env bash
# Proof for "Restore a verified phase": every gate pass commits the working tree and
# force-tags the gate id, so each passed phase is a restore point. Drive the real hb CLI in a
# git project and prove:
#   1. passing the gate creates a tag named after the gate (it did not exist before),
#   2. after a destructive change the gate would_block,
#   3. `git reset --hard <gate-tag>` restores the tracked artifact and the gate would_pass,
#   4. control: HB_GIT_AUTOCOMMIT=0 makes the gate pass create NO tag (opt-out).
# Prints RESTORE-POINTS-OK only when the round-trip restores the passing state.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" STUCK_TICKS=999 HB_ROT_CHECK=0
unset HB_NO_GIT   # restore points need real git
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

mkproj(){ # -> git project dir with a content-gated phase
  local p; p="$(mktemp -d)"
  ( cd "$p" && git init -q && git config user.email t@t && git config user.name t )
  hb init "$p" >/dev/null 2>&1
  python3 -c 'import json,sys;json.dump({"phases":[{"id":"A0","gate_entry":None,"gate_exit":"GA0","tasks":[{"id":"T1","title":"make out.txt"}]}],"gates":{"GA0":{"desc":"g","criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},open(sys.argv[1],"w"))' "$p/.hb/dag.json"
  hb rebuild --dir "$p" >/dev/null 2>&1
  ( cd "$p" && git add -A && git commit -qm init >/dev/null 2>&1 )
  echo "$p"
}
gate_check(){ hb gate GA0 --check --dir "$1" 2>&1 | tail -1; }

# Main: a gate pass creates a restore point we can roll back to.
p="$(mkproj)"; trap 'rm -rf "$p" "${p2:-}"' EXIT
( cd "$p" && git tag | grep -qx GA0 ) && fail "tag GA0 existed before the gate passed"
hb start T1 --dir "$p" >/dev/null 2>&1; printf 'ok\n' > "$p/out.txt"; hb done T1 --dir "$p" >/dev/null 2>&1
hb gate GA0 --dir "$p" >/dev/null 2>&1
( cd "$p" && git tag | grep -qx GA0 ) || fail "the gate pass did not create the restore-point tag GA0"

printf 'DESTROYED\n' > "$p/out.txt"            # wreck the tracked artifact
( cd "$p" && git add -A && git commit -qm break >/dev/null 2>&1 )   # commit it so HEAD moves PAST the tag
( cd "$p" && [ "$(git rev-parse HEAD)" != "$(git rev-parse GA0)" ] ) || fail "HEAD did not diverge from GA0 — reset can't distinguish the tag"
gate_check "$p" | grep -q would_block || fail "the gate did not block after the artifact was destroyed"
( cd "$p" && git reset --hard GA0 >/dev/null 2>&1 ) || fail "git reset --hard GA0 failed"
grep -q ok "$p/out.txt" || fail "reset did not restore the artifact"
gate_check "$p" | grep -q would_pass || fail "the gate does not pass after restoring to its tag"

# Control: HB_GIT_AUTOCOMMIT=0 -> the gate pass creates no restore point.
p2="$(mkproj)"
hb start T1 --dir "$p2" >/dev/null 2>&1; printf 'ok\n' > "$p2/out.txt"; hb done T1 --dir "$p2" >/dev/null 2>&1
HB_GIT_AUTOCOMMIT=0 hb gate GA0 --dir "$p2" >/dev/null 2>&1
( cd "$p2" && git tag | grep -qx GA0 ) && fail "HB_GIT_AUTOCOMMIT=0 still created a tag — opt-out is broken"

echo "RESTORE-POINTS-OK: a gate pass tags a restore point; reset --hard restores the passing state; autocommit=0 opts out."
