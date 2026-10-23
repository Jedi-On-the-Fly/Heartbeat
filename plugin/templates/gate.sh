#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# HeartBeat gate.sh — Generic gate runner (v1.5)
# Usage:
#   bash gate.sh <GATE_ID>            run a gate (side effects: log, reproject,
#                                     commit+tag on pass, advance the phase)
#   bash gate.sh --check <GATE_ID>    RE-VERIFY a gate read-only (no state change)
#   bash gate.sh --all                RE-VERIFY every ever-passed gate read-only
#                                     (regression check; never-passed/planned gates
#                                     are SKIPPED and reported — nothing to regress from)
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

# Each criterion runs under a timeout so a hanging cmd blocks the gate (✗) instead of
# hanging. dag.json is TRUSTED input (criteria are eval'd). The default is sized for a REAL
# criterion (a test suite, a build step) — 5s killed legitimate work. A criterion sets its
# own budget with `timeout_s` in dag.json, which WINS over this default: the DAG (versioned
# config) outranks the environment (a blunt global).
GATE_TIMEOUT_S="${GATE_TIMEOUT_S:-60}"
# A FAILING criterion's captured output is surfaced as a bounded TAIL (the WHY, not just the
# WHICH) — full output would bury the gate summary, so the cut is bounded and LOUD.
GATE_OUT_LINES="${GATE_OUT_LINES:-20}"
# Capture to a FILE, not $(…): a timed-out criterion's surviving grandchildren would hold a
# command-substitution pipe open past the kill (an unbounded hang); a file has no EOF wait.
# mktemp may be absent (the coreutils-less PATH T156 exercises) — fall back to a $$-named file.
if command -v mktemp >/dev/null 2>&1; then CRIT_OUT="$(mktemp "${TMPDIR:-/tmp}/hb-gate-out.XXXXXX")"
else CRIT_OUT="${TMPDIR:-/tmp}/hb-gate-out.$$"; : > "$CRIT_OUT"; fi
trap 'rm -f "$CRIT_OUT" "$CRIT_OUT.2" 2>/dev/null || true' EXIT
if   command -v timeout  >/dev/null 2>&1; then TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN="gtimeout"
else TIMEOUT_BIN=""; fi
run_criterion() {   # $1 = cmd, $2 = timeout seconds (defaults to GATE_TIMEOUT_S)
  local t="${2:-$GATE_TIMEOUT_S}"
  # </dev/null on BOTH branches: eval_gate streams the criteria into its `while read` loop
  # via stdin, so a criterion that reads stdin (docker compose exec -T, psql, ssh, anything
  # slurping) would EAT the remaining criteria records — never run, never reported, never
  # counted: the gate printed "N passed, 0 failed" and PASSED on partial evidence (silent,
  # fail-open, position-dependent). The fallback below always guarded this; the timeout(1)
  # branch — the one that runs wherever coreutils exists — did not. Field report: a 5-criterion
  # gate ran 3 and passed; a 16-criterion gate would have run 1. Python mirrors (stdin=DEVNULL).
  if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "${t}s" bash -c "$1" </dev/null; return $?; fi
  # No timeout(1)/gtimeout (e.g. stock macOS ships no coreutils): apply a portable shell-level bound so a
  # hanging criterion still blocks the gate (kill → ✗) instead of running unbounded — parity with the
  # python runner (subprocess timeout). Background + poll + kill; </dev/null so the criterion can't read stdin.
  bash -c "$1" </dev/null &
  local p=$! i=0 n=$(( t * 10 ))
  while kill -0 "$p" 2>/dev/null; do
    i=$((i + 1)); if [ "$i" -ge "$n" ]; then kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null; return 124; fi
    sleep 0.1
  done
  wait "$p"
}

# Sweep-scope dedup (--all only): byte-identical (cmd, effective timeout) pairs run ONCE per
# sweep — 15 gates referencing the same 10s test suite must not run it 15 times to learn one
# bit. Every reuse is reported ("deduped"), never silent; keyed on cmd AND effective timeout
# (a pass under a 60s budget proves nothing about a 1s one). Sound per the DAG contract
# (criteria are deterministic — the auditor flags the rest); no cross-run cache to rot.
# bash-3.2-portable: parallel indexed arrays + linear scan (no associative arrays on stock macOS).
_dedup_find() {   # $1 = key → sets DD_I on hit
  local i=0
  while [ "$i" -lt "${#DEDUP_KEYS[@]}" ]; do
    [ "${DEDUP_KEYS[$i]}" = "$1" ] && { DD_I=$i; return 0; }
    i=$((i + 1))
  done
  return 1
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
  while IFS=$'\x1f' read -r -d $'\x1e' ID DESC TOUT CMD; do
    # Per-criterion timeout_s (empty = use the default). Invalid is a LOUD runtime failure of
    # the criterion (the zero-criteria-floor precedent) — never a silent fallback.
    EFF_T="$GATE_TIMEOUT_S"
    if [ -n "$TOUT" ]; then
      case "$TOUT" in *[!0-9]*|0) EFF_T="";; *) EFF_T="$TOUT";; esac
    fi
    if [ -z "$EFF_T" ]; then
      echo "  ✗ [$ID] $DESC"; echo "      invalid timeout_s: '$TOUT' (must be a positive integer)"
      FAIL=$((FAIL + 1)); CRIT_EXITS="$CRIT_EXITS 1"
      continue
    fi
    KEY="$CMD"$'\x1f'"$EFF_T"
    if [ "${DEDUP:-0}" = 1 ] && _dedup_find "$KEY"; then
      RC="${DEDUP_EXITS[$DD_I]}"; DT="${DEDUP_DTS[$DD_I]}"; DEDUP_HITS=$((DEDUP_HITS + 1))
      FMARK=""; [ "${DEDUP_FLAKY[$DD_I]}" = 1 ] && FMARK=", FLAKY"
      if [ "$RC" -eq 0 ]; then
        echo "  ✓ [$ID] $DESC (deduped, ${DT}s)"; PASS=$((PASS + 1)); CRIT_EXITS="$CRIT_EXITS 0"
      else
        echo "  ✗ [$ID] $DESC (deduped, ${DT}s${FMARK})"; echo "      cmd: $CMD"
        echo "      (first failure of this cmd shown above)"
        FAIL=$((FAIL + 1)); CRIT_EXITS="$CRIT_EXITS 1"
      fi
      continue
    fi
    # TTY-only transient "what is running now" line (with its budget), cleared before the
    # result prints — piped/captured output (hooks, tests) never carries it. Every result
    # line carries its duration, so "slow" is distinguishable from "hung" mid-sweep.
    [ -t 1 ] && printf '  ⏳ [%s] %s (≤%ss)' "$ID" "$DESC" "$EFF_T"
    T0=$SECONDS
    if run_criterion "$CMD" "$EFF_T" >"$CRIT_OUT" 2>&1; then RC=0; else RC=1; fi
    DT=$((SECONDS - T0))
    [ -t 1 ] && printf '\r\033[K'
    # Flake probe (sweep-only): re-run a FAILURE once to distinguish flake from regression.
    # The verdict NEVER changes — observed nondeterminism is itself a gate-contract violation
    # (the behavioral complement of the auditor's static `nondeterministic` rule) and fails
    # closed; the probe only labels. Probe output goes to a second file so the FIRST failure's
    # tail (the evidence) is preserved.
    IS_FLAKY=0; REPRO=0; DT2=0
    if [ "$RC" -ne 0 ] && [ "${DEDUP:-0}" = 1 ]; then
      T1=$SECONDS
      if run_criterion "$CMD" "$EFF_T" >"$CRIT_OUT.2" 2>&1; then IS_FLAKY=1; else REPRO=1; fi
      DT2=$((SECONDS - T1))
      [ "$IS_FLAKY" = 1 ] && FLAKY_TOTAL=$((FLAKY_TOTAL + 1))
    fi
    if [ "${DEDUP:-0}" = 1 ]; then
      DEDUP_KEYS+=("$KEY"); DEDUP_EXITS+=("$RC"); DEDUP_DTS+=("$DT"); DEDUP_FLAKY+=("$IS_FLAKY")
    fi
    if [ "$RC" -eq 0 ]; then
      echo "  ✓ [$ID] $DESC (${DT}s)"; PASS=$((PASS + 1)); CRIT_EXITS="$CRIT_EXITS 0"
    elif [ "$IS_FLAKY" = 1 ]; then
      echo "  ✗ [$ID] $DESC FLAKY: failed (${DT}s), then passed on re-run (${DT2}s) — still FAILED (a criterion must be deterministic)"
      echo "      cmd: $CMD"
      FAIL=$((FAIL + 1)); CRIT_EXITS="$CRIT_EXITS 1"
    else
      echo "  ✗ [$ID] $DESC (${DT}s)"; echo "      cmd: $CMD"
      [ "$REPRO" = 1 ] && echo "      (failure reproduced on immediate re-run, ${DT2}s)"
      if [ -s "$CRIT_OUT" ]; then
        # Pure-bash tail (no wc/tail/sed — they're absent on the coreutils-less PATH T156 exercises).
        OUT_LINES=()
        while IFS= read -r _l || [ -n "$_l" ]; do OUT_LINES+=("$_l"); done < "$CRIT_OUT"
        N=${#OUT_LINES[@]}; START=0
        if [ "$N" -gt "$GATE_OUT_LINES" ]; then
          echo "      … (+$((N - GATE_OUT_LINES)) earlier output lines)"; START=$((N - GATE_OUT_LINES))
        fi
        i=$START; while [ "$i" -lt "$N" ]; do echo "      ${OUT_LINES[$i]}"; i=$((i + 1)); done
      fi
      FAIL=$((FAIL + 1)); CRIT_EXITS="$CRIT_EXITS 1"
    fi
  done < <(node -e "
    const dag = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    // timeout_s travels as the 3rd field; cmd stays LAST so it keeps swallowing any remainder.
    for (const c of dag.gates[process.argv[2]].criteria) process.stdout.write([c.id, c.desc, c.timeout_s ?? '', c.cmd].join('\x1f') + '\x1e');
  " "$DAG_FILE" "$G")
  echo ""
  echo "=== $G: $PASS passed, $FAIL failed ==="
}

reproject() { [ -f "$HB_DIR/hb.js" ] && node "$HB_DIR/hb.js" rebuild >/dev/null 2>&1 || true; }
# The git policy in force: autocommit on AND git present AND inside a worktree. Recorded on the
# acceptance event as git:{autocommit} so doctor judges a missing tag by the policy of the time.
git_policy() {
  [ -z "${HB_NO_GIT:-}" ] && [ "${HB_GIT_AUTOCOMMIT:-1}" != "0" ] && command -v git >/dev/null 2>&1 \
    && git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 && echo true || echo false
}
# A failed restore-point step is reported on stderr AND recorded — never swallowed.
restore_point_failed() {   # <gate> <step> <error>
  echo "⚠ restore point for $1: git $2 failed — $3" >&2
  node -e 'require("fs").appendFileSync(process.argv[1], JSON.stringify({ts:new Date().toISOString(),event:"restore_point_failed",gate:process.argv[2],step:process.argv[3],error:process.argv[4]})+"\n")' \
    "$EVENTS_FILE" "$1" "$2" "$3"
}
git_snapshot() {   # snapshot the phase on gate pass → git restore point (v1.4)
  [ "$(git_policy)" = true ] || return 0
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
  local err
  # A failed add/commit returns BEFORE tagging: a tag on the pre-phase HEAD would make the
  # documented restore (git reset --hard <GATE>) silently discard the phase's work.
  if ! err=$(git -C "$PROJECT_DIR" add -A 2>&1); then restore_point_failed "$1" add "$(echo "$err" | tail -1)"; reproject; return 0; fi
  # Nothing staged ⇒ nothing to commit: not a failure (the tag then marks the current HEAD).
  if ! git -C "$PROJECT_DIR" diff --cached --quiet >/dev/null 2>&1; then
    # --no-verify: internal snapshots bypass the rot pre-commit hook (avoids a
    # pre-existing rot blocking this gate's own snapshot → loop deadlock).
    if ! err=$(git -c user.name='HeartBeat' -c user.email='heartbeat@local' \
        -C "$PROJECT_DIR" commit -q --no-verify -m "$MSG" 2>&1); then restore_point_failed "$1" commit "$(echo "$err" | tail -1)"; reproject; return 0; fi
  fi
  if ! err=$(git -C "$PROJECT_DIR" tag -f "$1" 2>&1); then restore_point_failed "$1" tag "$(echo "$err" | tail -1)"; fi
  reproject
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

# ── --all: read-only re-verification of every EVER-PASSED gate ────────────────
# Regression semantics: a gate that has passed keeps acting as a gate; a gate that has never
# passed — a drafted/planned future phase — has nothing to regress from and is SKIPPED, loudly.
# Filter on the event log (truth), not state.json: gate_failed resets the projection's det flag,
# and a once-proven gate must stay armed through a recorded failure.
if [ "$ALL" = 1 ]; then
  LISTS=$(node -e "
    const fs = require('fs');
    const dag = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
    const seen = new Set();
    let raw = ''; try { raw = fs.readFileSync(process.argv[2], 'utf8'); } catch (e) {}
    for (const l of raw.split('\n')) {
      if (!l.trim()) continue;
      try { const ev = JSON.parse(l); if (ev.event === 'gate_passed' && ev.gate) seen.add(ev.gate); } catch (e) {}
    }
    // A parked phase's gate leaves the sweep entirely (retirement) — even if it was armed.
    const parkedG = new Set((dag.phases || []).filter(p => p.parked && p.gate_exit).map(p => p.gate_exit));
    const all = Object.keys(dag.gates || {});
    // A pending regate is COUNTED FAILING regardless of armed/planned status — the sweep must never
    // say ALL GREEN over an unrefuted revision. A parked one stays retired but is ANNOTATED.
    // Fail-closed predicate (== hb.js regateBlocks): only a well-formed pending:false record clears.
    const rp = (g) => { const gv = dag.gates[g] || {}; if (!Object.prototype.hasOwnProperty.call(gv, 'regate')) return false;
      const r = gv.regate; return !(r && typeof r === 'object' && !Array.isArray(r) && r.pending === false); };
    const regated = new Set(all.filter(rp));
    console.log(all.filter(g => seen.has(g) && !parkedG.has(g) && !regated.has(g)).join(' '));
    console.log(all.filter(g => !seen.has(g) && !parkedG.has(g) && !regated.has(g)).join(' '));
    console.log(all.filter(g => parkedG.has(g)).join(' '));
    console.log(all.filter(g => regated.has(g) && !parkedG.has(g)).join(' '));
    console.log(all.filter(g => regated.has(g) && parkedG.has(g)).join(' '));
  " "$DAG_FILE" "$EVENTS_FILE")
  GATES=$(printf '%s\n' "$LISTS" | sed -n 1p)
  PLANNED=$(printf '%s\n' "$LISTS" | sed -n 2p)
  PARKED=$(printf '%s\n' "$LISTS" | sed -n 3p)
  REGATED=$(printf '%s\n' "$LISTS" | sed -n 4p)     # regate-guard
  PARKED_RG=$(printf '%s\n' "$LISTS" | sed -n 5p)   # regate-guard
  # Announce scope UP FRONT — a multi-minute silent sweep (the pre-push hook path) is
  # indistinguishable from a hung run — and report the elapsed total in the verdict.
  set -- $GATES; NGATES=$#
  echo "— re-verifying $NGATES ever-passed gate(s)…"
  echo ""
  DEDUP=1; DEDUP_KEYS=(); DEDUP_EXITS=(); DEDUP_DTS=(); DEDUP_FLAKY=(); DEDUP_HITS=0; FLAKY_TOTAL=0
  S0=$SECONDS
  TOTAL_FAIL=0
  for g in $GATES; do eval_gate "$g"; TOTAL_FAIL=$((TOTAL_FAIL + FAIL)); echo ""; done
  T_ALL=$((SECONDS - S0))
  if [ -n "${REGATED:-}" ]; then set -- $REGATED; echo "— ⛔ $# regate-pending gate(s) (revised, not re-refuted — counted FAILING): $REGATED"; echo ""; TOTAL_FAIL=$((TOTAL_FAIL + $#)); fi   # regate-guard: a pending revision is a FAILURE, never a skip (single line: a stripped guard must leave a PARSING script)
  if [ -n "$PLANNED" ]; then
    set -- $PLANNED
    echo "— skipped $# planned gate(s) (never passed): $PLANNED"
    echo ""
  fi
  if [ -n "$PARKED" ]; then
    set -- $PARKED
    RGNOTE=""; [ -n "${PARKED_RG:-}" ] && RGNOTE=" (regate pending: $PARKED_RG)"   # regate-guard: retirement never hides a revision
    echo "— skipped $# parked gate(s): $PARKED${RGNOTE:-}"
    echo ""
  fi
  DSUF=""; [ "$DEDUP_HITS" -gt 0 ] && DSUF=", $DEDUP_HITS deduped"
  FSUF=""; [ "$FLAKY_TOTAL" -gt 0 ] && FSUF=", $FLAKY_TOTAL flaky"
  if [ "$TOTAL_FAIL" -eq 0 ]; then echo "✅ ALL GATES PASS (read-only: $NGATES gate(s) in ${T_ALL}s${DSUF})"; exit 0
  else echo "❌ $TOTAL_FAIL failing criteria across gates (read-only; ${T_ALL}s${DSUF}${FSUF})"; exit 1; fi
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

# A pending regate refuses evaluation FAIL-CLOSED: the criteria were revised and not yet re-refuted,
# so running them proves nothing (and the dead premises may make execution itself harmful). Exit 3 —
# distinct from 1 (blocked) and 2 (usage) — so a driver can escalate rather than retry. No event:
# nothing was evaluated, so nothing failed; the dag marker carries the state.
RG_PENDING=$(node -e "const d=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));const g=((d.gates||{})[process.argv[2]]||{});if(Object.prototype.hasOwnProperty.call(g,'regate')){const r=g.regate;const clear=r&&typeof r==='object'&&!Array.isArray(r)&&r.pending===false;if(!clear){const rr=(r&&typeof r==='object'&&!Array.isArray(r))?r:{};process.stdout.write((rr.actor||'?')+': '+(rr.reason||'(unreadable regate record — run lint)'));}}" "$DAG_FILE" "$GATE")   # regate-guard
[ -n "$RG_PENDING" ] && { printf '⛔ %s is being revised — regate pending (%s)\n   evaluation refused (fail-closed). Edit the criteria → re-audit → a DIFFERENT actor rearms:\n   node %s/hb.js regate %s --rearm --artifact <findings-file>\n' "$GATE" "$RG_PENDING" "$HB_DIR" "$GATE"; exit 3; }   # regate-guard

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
    const ev={ts:process.argv[4],event:"gate_passed",gate,pass:Number(process.argv[5]),fail:0,criteria:crits,commit:process.argv[6]||null,runtime:"node",git:{autocommit:process.argv[8]==="true"}};
    fs.appendFileSync(process.argv[7],JSON.stringify(ev)+"\n");
  ' "$DAG_FILE" "$GATE" "$CRIT_EXITS" "$TS" "$PASS" "$COMMIT" "$EVENTS_FILE" "$(git_policy)"
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
  node "$HB_DIR/hb.js" anchor "$GATE" >/dev/null || true   # acceptance anchor (hb.js reports a failure on stderr)
  echo "✅ GATE PASSED — proceed to next phase."
  exit 0
else
  echo "{\"ts\":\"$TS\",\"event\":\"gate_failed\",\"gate\":\"$GATE\",\"pass\":$PASS,\"fail\":$FAIL}" >> "$EVENTS_FILE"
  reproject
  echo ""
  echo "❌ GATE BLOCKED — fix $FAIL failing criteria before proceeding."
  exit 1
fi
