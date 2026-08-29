#!/usr/bin/env bash
# Proof: gate.sh counts a gate CORRECTLY even when a criterion's `cmd` contains an embedded newline
# (e.g. a heredoc). The transport from the node criteria-extractor to the bash consumer used to be
# newline-delimited (`console.log` + `while read`), so a newline in a cmd split one record into many:
# the heredoc body lines became bogus records with an empty CMD, and `bash -c ""` exits 0 → a FALSE ✓,
# which inflated the pass count and desynced every criterion after it — a false gate, silently. This
# proof drives the REAL gate.sh --check on a 3-fail gate whose middle criterion is a heredoc, and
# asserts 0 passed / 3 failed, no bogus heredoc-body entries, the newline criterion correctly FAILS,
# and node/bash ≡ python. Prints GATE-NEWLINE-CMD-OK. RED on the pre-fix gate.sh (reports 4 passed / 2).
# `--selftest` proves the count / no-bogus-entry checks are load-bearing.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR DAG_FILE EVENTS_FILE 2>/dev/null || true
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }

if [ "${1:-}" = "--selftest" ]; then
  good=$'  ✗ [a] first\n  ✗ [nl] newline cmd\n  ✗ [c] third\n=== GATE_X: 0 passed, 3 failed ==='
  bad=$'  ✗ [a] first\n  ✓ [nl] newline cmd\n  ✓ [import sys] \n  ✓ [sys.exit(1)] \n  ✓ [PYX] \n  ✗ [c] third\n=== GATE_X: 4 passed, 2 failed ==='
  # count check: a clean output has zero ✓; the miscounted one has some
  [ "$(printf '%s' "$good" | grep -c '✓ \[')" -eq 0 ] || fail "selftest: pass-count check rejected a clean gate"
  [ "$(printf '%s' "$bad"  | grep -c '✓ \[')" -ne 0 ] || fail "selftest: pass-count check is not load-bearing (missed the miscount)"
  # bogus heredoc-body detector
  printf '%s' "$bad"  | grep -qE '\[(import|sys|PYX)' || fail "selftest: bogus-entry detector missed heredoc-body records"
  printf '%s' "$good" | grep -qE '\[(import|sys|PYX)' && fail "selftest: bogus-entry detector false-fired on a clean gate"
  echo "SELFTEST-OK"; exit 0
fi

export HB_NO_GIT=1
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
proj="$work/p"; bash "$ROOT/plugin/bootstrap.sh" "$proj" >/dev/null 2>&1 </dev/null
# a gate whose 3 criteria all FAIL; the MIDDLE one's cmd is a multi-line heredoc (exits 1)
python3 - "$proj/.hb/dag.json" <<'PY'
import json, sys
json.dump({"phases": [{"id": "P", "gate_entry": None, "gate_exit": "GATE_X", "tasks": [{"id": "t"}]}],
           "gates": {"GATE_X": {"criteria": [
               {"id": "a", "desc": "first", "cmd": "false"},
               {"id": "nl", "desc": "newline cmd", "cmd": "python3 - <<'PYX'\nimport sys\nsys.exit(1)\nPYX"},
               {"id": "c", "desc": "third", "cmd": "false"}]}}}, open(sys.argv[1], "w"))
PY

out="$(bash "$proj/.hb/gate.sh" --check GATE_X 2>&1)"
np="$(printf '%s' "$out" | grep -c '✓ \[')"; nf="$(printf '%s' "$out" | grep -c '✗ \[')"
[ "$np" -eq 0 ] && [ "$nf" -eq 3 ] || fail "node/bash miscounted a newline cmd: $np passed / $nf failed (expected 0/3)"$'\n'"$out"
printf '%s' "$out" | grep -qE '\[(import|sys|PYX)' && fail "heredoc body was misparsed into bogus criteria"$'\n'"$out"
printf '%s' "$out" | grep -q '✗ \[nl\]' || fail "the newline-cmd criterion was not correctly failed (false pass)"

# node/bash ≡ python on the SAME dag (python reads the dag directly — the parity oracle)
pyout="$(PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli gate GATE_X --check --dir "$proj" 2>&1)"
pp="$(printf '%s' "$pyout" | grep -c '✓ \[')"; pf="$(printf '%s' "$pyout" | grep -c '✗ \[')"
{ [ "$np" -eq "$pp" ] && [ "$nf" -eq "$pf" ]; } || fail "node/bash ≠ python on a newline cmd: node $np/$nf vs py $pp/$pf"

echo "GATE-NEWLINE-CMD-OK"
