#!/usr/bin/env bash
# Proof: `hb init` (python scaffold) must NOT wipe an existing event log. events.jsonl is the append-only
# source of truth; re-initializing an existing project without --force must PRESERVE it (matching node
# bootstrap.sh, which refuses re-init without --force). Prints INIT-LOG-SAFE-OK. Fails today (scaffold.py
# rewrites events.jsonl unconditionally). Deterministic.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

p="$tmp/proj"
HB_NO_GIT=1 hb init "$p" >/dev/null 2>&1 || fail "hb init failed"
# simulate real history appended to the append-only log
printf '%s\n' '{"event":"task_done","task":"REAL-WORK-SENTINEL"}' >> "$p/.hb/events.jsonl"

# re-init WITHOUT --force must preserve the existing event log
HB_NO_GIT=1 hb init "$p" >/dev/null 2>&1 || true
grep -q 'REAL-WORK-SENTINEL' "$p/.hb/events.jsonl" || fail "re-init WITHOUT --force wiped the event log (append-only source of truth lost)"

echo "INIT-LOG-SAFE-OK"
