#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# HeartBeat gate.sh — Generic gate runner (v1.5)
# Usage:
#   bash gate.sh <GATE_ID>            run a gate (side effects: log, reproject,
#                                     commit+tag on pass, advance the phase)
#   bash gate.sh --check <GATE_ID>    RE-VERIFY a gate read-only (no state change)
#   bash gate.sh --all                RE-VERIFY every gate read-only (regression check)
# Exit 0 = passed | 1 = blocked/failing | 2 = usage / unknown gate
#
# v1.5: --check / --all make a passed gate keep acting as a gate — you can re-run
# the criteria anytime to prove the project STILL passes, without mutating state.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

HB_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$HB_DIR")"
export HB_DIR PROJECT_DIR

DAG_FILE="$HB_DIR/dag.json"
export DAG_FILE HB_DIR   # node -e reads these via process.env (not spliced into JS source)
EVENTS_FILE="$HB_DIR/events.jsonl"

# Each criterion runs under a timeout so a hanging cmd blocks the gate (✗) instead
# of hanging. dag.json is TRUSTED input (criteria are eval'd) — one-line, <5s.
GATE_TIMEOUT_S="${GATE_TIMEOUT_S:-5}"
if   command -v timeout  >/dev/null 2>&1; then TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN="gtimeout"
else TIMEOUT_BIN=""; fi
run_criterion() {
  if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "${GATE_TIMEOUT_S}s" bash -c "$1"
  else bash -c "$1"; fi
}

# eval_gate <GATE> — run the criteria, print ✓/✗, set PASS/FAIL globals. No side effects.
eval_gate() {
  local -x G="$1"; PASS=0; FAIL=0; CRIT_EXITS=""   # CRIT_EXITS: per-criterion exit codes in dag order (provenance)
  echo "=== Gate: $G ==="
  echo ""
  # Hollow-gate floor: a gate with zero criteria proves nothing. The auditor warns
  # about this upstream; the runtime must also refuse it, so an un-audited or
  # post-audit-mutated DAG can't buy a free phase advance.
  local CRIT_COUNT
  CRIT_COUNT=$(node -e "const d=JSON.parse(require('fs').readFileSync(process.env.DAG_FILE,'utf8'));console.log((((d.gates||{})[process.env.G]||{}).criteria||[]).length)" 2>/dev/null || echo 0)
  if [ "${CRIT_COUNT:-0}" -eq 0 ]; then
    echo "  ✗ [--] gate $G has NO criteria — a gate must assert something"
    echo ""
    echo "=== $G: 0 passed, 1 failed ==="
    FAIL=1
    return
  fi
  # Transport: fields joined by \x1f (unit sep), records TERMINATED by \x1e (record sep), and read with
  # -d $'\x1e'. This is immune to embedded newlines in a cmd/desc (e.g. a heredoc) — which a plain
  # newline-delimited `read` would split into bogus empty-CMD records that trivially "pass" (a false
  # gate). \x1e never appears in a shell command, and a multi-line cmd now runs verbatim.
  while IFS=$'\x1f' read -r -d $'\x1e' ID DESC CMD; do
    if run_criterion "$CMD" >/dev/null 2>&1; then
      echo "  ✓ [$ID] $DESC"; PASS=$((PASS + 1)); CRIT_EXITS="$CRIT_EXITS 0"
    else
      echo "  ✗ [$ID] $DESC"; echo "      cmd: $CMD"; FAIL=$((FAIL + 1)); CRIT_EXITS="$CRIT_EXITS 1"
    fi
  done < <(node -e "
    const dag = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    for (const c of dag.gates[process.argv[2]].criteria) process.stdout.write([c.id, c.desc, c.cmd].join('\x1f') + '\x1e');
  " "$DAG_FILE" "$G")
  echo ""
  echo "=== $G: $PASS passed, $FAIL failed ==="
}

reproject() { [ -f "$HB_DIR/hb.js" ] && node "$HB_DIR/hb.js" rebuild >/dev/null 2>&1 || true; }
git_snapshot() {   # snapshot the phase on gate pass → git restore point (v1.4)
  [ -z "${HB_NO_GIT:-}" ] || return 0
  [ "${HB_GIT_AUTOCOMMIT:-1}" != "0" ] || return 0
  command -v git >/dev/null 2>&1 || return 0
  git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  # Descriptive message: the phase this gate closes (id + title), not just "GATE_X passed".
  MSG=$(node -e "
    try {
      const dag = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      const g = process.argv[2];
      const p = (dag.phases||[]).find(x => x.gate_exit === g);
      console.log(p ? 'heartbeat('+p.id+'): '+p.title+' ['+g+']' : 'heartbeat: '+g+' passed');
    } catch (e) { console.log('heartbeat: '+process.argv[2]+' passed'); }
  " "$DAG_FILE" "$1" 2>/dev/null)
  [ -n "$MSG" ] || MSG="heartbeat: $1 passed"
  git -C "$PROJECT_DIR" add -A >/dev/null 2>&1 || true
  # --no-verify: internal snapshots bypass the rot pre-commit hook (avoids a
  # pre-existing rot blocking this gate's own snapshot → loop deadlock).
  git -c user.name='HeartBeat' -c user.email='heartbeat@local' \
      -C "$PROJECT_DIR" commit -q --no-verify -m "$MSG" >/dev/null 2>&1 || true
  git -C "$PROJECT_DIR" tag -f "$1" >/dev/null 2>&1 || true
}

# ── flags ─────────────────────────────────────────────────────────────────────
CHECK=0; ALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift;;
    --all)   ALL=1; CHECK=1; shift;;   # --all is always read-only
    *) break;;
  esac
done
GATE="${1:-}"; export GATE

# ── --all: read-only re-verification of every gate ────────────────────────────
if [ "$ALL" = 1 ]; then
  GATES=$(node -e "console.log(Object.keys(JSON.parse(require('fs').readFileSync(process.env.DAG_FILE,'utf8')).gates).join(' '))")
  TOTAL_FAIL=0
  for g in $GATES; do eval_gate "$g"; TOTAL_FAIL=$((TOTAL_FAIL + FAIL)); echo ""; done
  if [ "$TOTAL_FAIL" -eq 0 ]; then echo "✅ ALL GATES PASS (read-only)"; exit 0
  else echo "❌ $TOTAL_FAIL failing criteria across gates (read-only)"; exit 1; fi
fi

# ── single gate ───────────────────────────────────────────────────────────────
if [ -z "$GATE" ]; then
  echo "Usage: gate.sh [--check|--all] <GATE_ID>"
  echo "Available gates:"
  node -e "
    const dag = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    Object.keys(dag.gates).forEach(g => console.log('  ' + g + ' — ' + (dag.gates[g].desc||'')));
  " "$DAG_FILE"
  exit 2
fi
node -e "
  const dag = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
  if (!dag.gates[process.argv[2]]) { console.error('Unknown gate: ' + process.argv[2]); process.exit(2); }
" "$DAG_FILE" "$GATE" || exit 2

eval_gate "$GATE"

# ── --check: read-only, report only ───────────────────────────────────────────
if [ "$CHECK" = 1 ]; then
  echo ""
  if [ "$FAIL" -eq 0 ]; then echo "✅ (check) $GATE would pass — no state change."; exit 0
  else echo "❌ (check) $GATE would block ($FAIL failing) — no state change."; exit 1; fi
fi

# ── normal run: side effects (log → reproject → snapshot → review/advance) ─────
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [ "$FAIL" -eq 0 ]; then
  # Evidence provenance: record what was proven and how — per-criterion {id,cmd,exit}, the commit
  # tested, and the runtime. Built via node so command strings are correctly JSON-escaped.
  COMMIT=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || true)
  node -e '
    const fs=require("fs");
    const dag=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    const gate=process.argv[2];
    const exits=process.argv[3].trim().split(/\s+/).filter(x=>x!=="").map(Number);
    const crits=((dag.gates[gate]||{}).criteria||[]).map((c,i)=>({id:c.id,cmd:c.cmd,exit:exits[i]===undefined?0:exits[i]}));
    const ev={ts:process.argv[4],event:"gate_passed",gate,pass:Number(process.argv[5]),fail:0,criteria:crits,commit:process.argv[6]||null,runtime:"node"};
    fs.appendFileSync(process.argv[7],JSON.stringify(ev)+"\n");
  ' "$DAG_FILE" "$GATE" "$CRIT_EXITS" "$TS" "$PASS" "$COMMIT" "$EVENTS_FILE"
  reproject
  echo ""
  if node -e "process.exit((JSON.parse(require('fs').readFileSync(process.env.DAG_FILE,'utf8')).gates[process.env.GATE]||{}).review?0:1)" 2>/dev/null; then
    # A review-gated phase is ACCEPTED only after the adversarial review passes, so its restore
    # point (commit+tag) is created at review acceptance (hb.js review pass), NOT here — the tag
    # must never certify an un-reviewed / later-refuted state.
    echo "🧪 DETERMINISTIC GATE PASSED — adversarial review required (no checkpoint yet)."
    echo "   Spawn a skeptical reviewer to REFUTE completion, then run:"
    echo "     node $HB_DIR/hb.js review $GATE pass    (could not refute → commits+tags $GATE)"
    echo "     node $HB_DIR/hb.js review $GATE fail \"<findings>\"   (found holes)"
    exit 0
  fi
  git_snapshot "$GATE"
  echo "✅ GATE PASSED — proceed to next phase."
  exit 0
else
  echo "{\"ts\":\"$TS\",\"event\":\"gate_failed\",\"gate\":\"$GATE\",\"pass\":$PASS,\"fail\":$FAIL}" >> "$EVENTS_FILE"
  reproject
  echo ""
  echo "❌ GATE BLOCKED — fix $FAIL failing criteria before proceeding."
  exit 1
fi
