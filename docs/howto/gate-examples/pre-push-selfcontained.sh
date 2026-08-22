#!/usr/bin/env bash
# Proof: the pre-push gate guard is tested AS IT RUNS — no PYTHONPATH, no editable install masking it (a
# prior parity proof false-greened by computing the expected exit WITH PYTHONPATH while the hook ran
# without it). Under a claude/hb-free PATH with the SYSTEM python3 (no heartbeat importable):
#   NODE  — the hook (`.hb/gate.sh --all`) is genuinely self-contained: it blocks on a failing gate with
#           no hb and no PYTHONPATH (and HB_NO_HOOK bypasses).
#   PY    — with `hb` ABSENT the hook must NOT block on an IMPORT error; it skips (exit 0) with a visible
#           message. With `hb` present it blocks iff gate re-verify fails (covered by T118).
# Prints PRE-PUSH-SELFCONTAINED-OK. Fails today (py hook falls back to `python3 -m heartbeat.cli` → import
# error → blocks). Deterministic.
set -u
unset HB_NO_GIT HB_NO_HOOK   # the suite exports HB_NO_GIT=1; this proof installs real git hooks in temp repos
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v git >/dev/null 2>&1 || { echo "git absent"; exit 1; }
fail(){ echo "FAIL: $1"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CLEAN="/usr/bin:/bin"                     # system tools only: git/node/python3/coreutils — NO hb, NO ~/.local
env PATH="$CLEAN" bash -c 'command -v hb' >/dev/null 2>&1 && fail "proof setup: hb leaked into the clean PATH"
env -u PYTHONPATH PATH="$CLEAN" python3 -c 'import heartbeat' >/dev/null 2>&1 && fail "proof setup: system python3 can import heartbeat (can't reproduce the stripped env)"

# ── NODE: self-contained hook blocks on a failing gate with no hb / no PYTHONPATH ──
pn="$tmp/node"; mkdir -p "$pn"
env -u HB_NO_GIT -u HB_NO_HOOK -u PYTHONPATH PATH="$CLEAN" bash "$ROOT/plugin/bootstrap.sh" "$pn" >/dev/null 2>&1 || fail "node bootstrap failed"
[ -x "$pn/.git/hooks/pre-push" ] || fail "node: no pre-push hook installed"
# fresh node seed (GATE_P1) fails --all → hook must block, using only the clean PATH
if env -u HB_NO_HOOK -u PYTHONPATH PATH="$CLEAN" bash -c "cd '$pn' && .git/hooks/pre-push o u </dev/null" >/dev/null 2>&1; then
  fail "node: self-contained hook did not block on a failing gate under a clean PATH"
fi
env HB_NO_HOOK=1 PATH="$CLEAN" bash -c "cd '$pn' && .git/hooks/pre-push o u </dev/null" >/dev/null 2>&1 || fail "node: HB_NO_HOOK did not bypass"

# ── PY: with hb absent the hook skips (exit 0) with a message, NOT an import-error block ──
pp="$tmp/py"
PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli init "$pp" >/dev/null 2>&1 || fail "python init failed (setup)"
[ -x "$pp/.git/hooks/pre-push" ] || fail "python: no pre-push hook installed"
out="$(env -u PYTHONPATH PATH="$CLEAN" bash -c "cd '$pp' && .git/hooks/pre-push o u </dev/null" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "python: hook blocked (rc=$rc) when hb is absent — must skip, not fail on an import error. out: $out"
printf '%s' "$out" | grep -qiE 'hb|heartbeat' || fail "python: hook skipped silently — it should print a visible 'hb not found' message"

echo "PRE-PUSH-SELFCONTAINED-OK"
