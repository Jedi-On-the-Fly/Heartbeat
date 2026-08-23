#!/usr/bin/env bash
# Proof (GS): the git-snapshot-on-acceptance is a cross-runtime behavioral PAIR — node's inline snapshot
# in hb.js `review` and python's gate._git_snapshot (via review_policy.accept_review) must behave the same.
# It tests the path HeartBeat ACTUALLY uses: real phases are review-gated, so the commit+tag is deferred to
# `review <gate> pass` (NOT the on-pass branch, which only fires for non-review gates). For each runtime we
# drive a genuine review acceptance (substantive distinct-actor artifact citing the phase) and assert BOTH
# created a commit AND force-created a git tag named exactly after the gate. Teeth: a runtime that fails to
# tag → FAIL (a silently-skipped snapshot goes RED, not green). Prints GIT-SNAPSHOT-PARITY-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v git >/dev/null 2>&1 || { echo "git absent"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail(){ echo "FAIL: $1"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# The suite exports HB_NO_GIT=1 / HB_NO_HOOK=1; the snapshot early-returns under HB_NO_GIT, so we must run
# the acceptance with it unset (the whole point is to exercise the real git path).
run(){ env -u HB_NO_GIT -u HB_NO_HOOK "$@"; }

ART='Refutation attempt for GATE_P0 (phase P0, task P0T1): I examined the phase and could not refute it. This artifact is deliberately over forty characters and cites a real anchor.'

# ── NODE: bootstrap → drive `hb.js review GATE_P0 pass` as a distinct actor → assert tag ──
pn="$tmp/n"
run bash "$ROOT/plugin/bootstrap.sh" "$pn" >/dev/null 2>&1 || fail "node bootstrap"
git -C "$pn" rev-parse --is-inside-work-tree >/dev/null 2>&1 || git -C "$pn" init -q
printf '%s\n' "$ART" > "$pn/att.md"
( cd "$pn" && run env HB_ACTOR=gs-refuter node .hb/hb.js review GATE_P0 pass --artifact att.md ) >/dev/null 2>&1 \
  || fail "node: review pass was rejected"
git -C "$pn" tag -l | grep -qx GATE_P0 || fail "node: review acceptance did NOT create the GATE_P0 tag"
git -C "$pn" rev-parse "GATE_P0^{commit}" >/dev/null 2>&1 || fail "node: GATE_P0 tag does not resolve to a commit"

# ── PYTHON: init → drive `hb review GATE_P0 pass` as a distinct actor → assert tag ──
pp="$tmp/p"
run env PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli init "$pp" >/dev/null 2>&1 || fail "py init"
git -C "$pp" rev-parse --is-inside-work-tree >/dev/null 2>&1 || git -C "$pp" init -q
printf '%s\n' "$ART" > "$pp/att.md"
( cd "$pp" && run env PYTHONPATH="$ROOT/py/src" HB_ACTOR=gs-refuter python3 -m heartbeat.cli review GATE_P0 pass --artifact att.md ) >/dev/null 2>&1 \
  || fail "py: review pass was rejected"
git -C "$pp" tag -l | grep -qx GATE_P0 || fail "py: review acceptance did NOT create the GATE_P0 tag"
git -C "$pp" rev-parse "GATE_P0^{commit}" >/dev/null 2>&1 || fail "py: GATE_P0 tag does not resolve to a commit"

echo "GIT-SNAPSHOT-PARITY-OK"
