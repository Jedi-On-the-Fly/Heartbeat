#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# HeartBeat tick.sh — Generic Stage A script
# Outputs: { "wakeAgent": bool, "data": {...} }
#
# Usage: bash tick.sh            → normal tick
#        bash tick.sh --freeze   → (re)sanction the current WATCH_PATHS state as
#                                   the drift baseline
#
# Stage A does a series of priority checks and outputs whether the agent (Stage B)
# should wake, and why. It never runs LLM work itself. See the section banners
# below for the ordered checks.
# ══════════════════════════════════════════════════════════════════════════════

# ── PROJECT CONFIG (edit this section) ────────────────────────────────────────
HB_DIR="$(cd "$(dirname "$0")" && pwd)"   # auto: .hb/ dir where this script lives
PROJECT_DIR="$(dirname "$HB_DIR")"        # auto: parent project directory

# Optional: paths to watch for architecture drift (space-separated glob)
WATCH_PATHS=""   # e.g. "$PROJECT_DIR/core/*.js $PROJECT_DIR/adapters/*.js"

# Optional: custom next-task script (defaults to HB_DIR/hb-next-task.js)
NEXT_TASK_SCRIPT="$HB_DIR/hb-next-task.js"

# Lock considered dead after this many seconds (covers long agent sessions)
LOCK_STALE_S="${LOCK_STALE_S:-1800}"
# v1.3 (#3): objective no-progress guard. If the tick wakes an agent for the same
# task this many times with no task_started/done/failed event in between, the
# agent is looping WITHOUT reporting → treat as stuck (independent of self-report).
STUCK_TICKS="${STUCK_TICKS:-3}"
# v1.3 (#5): max tasks in flight at once (per-task leases). 1 = the classic serial
# behavior (one agent at a time). Raise it to run independent DAG branches in
# parallel — overlapping ticks hand out DISTINCT ready tasks up to this cap.
HB_MAX_CONCURRENCY="${HB_MAX_CONCURRENCY:-1}"
# v1.3 mid-session heartbeat: a long-running agent calls `hb heartbeat <id>` to
# refresh its lease. A lease WITH a beat marker is reclaimed after this many
# seconds of silence (fast hang-detection); a lease that never beats falls back
# to LOCK_STALE_S. So set this well below LOCK_STALE_S.
HEARTBEAT_STALE_S="${HEARTBEAT_STALE_S:-180}"
# v1.4: optional notifier for human-needed wakes. If set, it is run as
#   $HB_NOTIFY_CMD "<reason>" "<project>" "<detail>"
# on build_stuck / gate_blocked / deadlock / unsanctioned_drift / all_done /
# replan_pending / review_stuck / gate_rot — once per blockage (criteria_drift is not
# notified: it wakes every tick until cured). Timeout-wrapped and best-effort;
# it can never break the tick.
HB_NOTIFY_CMD="${HB_NOTIFY_CMD:-}"
# v1.6: run `hb.js doctor` each tick and wake `gate_rot` if a COMPLETED phase's
# gate references a file that no longer exists (rot). Set 0 to disable.
HB_ROT_CHECK="${HB_ROT_CHECK:-1}"
# ── END CONFIG ────────────────────────────────────────────────────────────────

set -euo pipefail
export HB_DIR PROJECT_DIR

STATE="$HB_DIR/state.json"
DAG="$HB_DIR/dag.json"
EVENTS="$HB_DIR/events.jsonl"
export STATE DAG EVENTS HB_DIR   # node -e reads these via process.env (not spliced into JS source)
LOCK="$HB_DIR/.lock"                  # short handout lock (serializes concurrent ticks)
LEASES="$HB_DIR/leases"               # per-task session claims (mkdir = atomic)
ARCH_HASH="$HB_DIR/architecture.hash"
STUCK_FLAG="$HB_DIR/.stuck-alerted"
NOPROG_FLAG="$HB_DIR/.noprogress-alerted"
DONE_FLAG="$HB_DIR/.all-done-alerted"
REPLAN_FLAG="$HB_DIR/.replan-alerted"     # holds the horizon phase id it alerted for
DEADLOCK_FLAG="$HB_DIR/.deadlock-alerted"
DAGBAD_FLAG="$HB_DIR/.dag-corrupted-alerted"     # one dag_corrupted event per blockage (the wake fires every tick)
RESERR_FLAG="$HB_DIR/.resolver-error-alerted"    # one notification per broken-resolver blockage — never the deadlock flag
GATE_NOTIFY_FLAG="$HB_DIR/.gate-notified"
DRIFT_NOTIFY_FLAG="$HB_DIR/.drift-notified"
REVIEW_STUCK_FLAG="$HB_DIR/.review-stuck-alerted"
ROT_FLAG="$HB_DIR/.rot-alerted"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mtime()     { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }   # GNU | BSD/macOS
log_event() { echo "{\"ts\":\"$TS\",\"event\":\"$1\"}" >> "$EVENTS"; }

# v1.4 (#2): best-effort notifier. Args to HB_NOTIFY_CMD: reason, project, detail
# (passed as $1/$2/$3 to avoid interpolation). Timeout-bounded; never fails the tick.
notify() {
  [ -n "$HB_NOTIFY_CMD" ] || return 0
  local proj; proj="$(basename "$PROJECT_DIR")"
  # reason/project/detail are exposed to HB_NOTIFY_CMD as $1/$2/$3 (positional args
  # after the _ sentinel). The command may reference them or ignore them.
  if command -v timeout >/dev/null 2>&1; then
    timeout 10s bash -c "$HB_NOTIFY_CMD" _ "$1" "$proj" "${2:-}" >/dev/null 2>&1 || true
  else
    bash -c "$HB_NOTIFY_CMD" _ "$1" "$proj" "${2:-}" >/dev/null 2>&1 || true
  fi
}

compute_watch_hash() {
  local sha="sha256sum"; command -v sha256sum >/dev/null 2>&1 || sha="shasum -a 256"   # macOS fallback
  ( eval "find $WATCH_PATHS" 2>/dev/null || true ) \
    | sort | xargs $sha 2>/dev/null | $sha | cut -d' ' -f1
}

HAVE_LOCK=false
# v1.3 (#5): the handout lock is SHORT-LIVED — it only serializes concurrent ticks
# during task selection. The agent session is now protected by a per-task LEASE
# (.hb/leases/<id>), not the global lock. So BOTH exits release the handout lock.
release_lock() { if [ "$HAVE_LOCK" = true ]; then rm -rf "$LOCK"; HAVE_LOCK=false; fi; }
sleep_out() {
  release_lock
  echo "{\"wakeAgent\":false,\"data\":$1}"
  exit 0
}
wake_out() {
  release_lock
  # v1.7: make the tick self-describing — inject data.action from the protocol map
  # so any driver (cron, headless, another harness) knows what to do from the JSON
  # alone. Falls back to the bare payload if node/hb.js is unavailable.
  node -e "
    const hb=require('$HB_DIR/hb.js');
    let d; try{d=JSON.parse(process.argv[1])}catch(e){d={}}
    if(d.reason && hb.PROTOCOL && hb.PROTOCOL[d.reason]) d.action=hb.PROTOCOL[d.reason];
    process.stdout.write(JSON.stringify({wakeAgent:true,data:d}));
  " "$1" 2>/dev/null || echo "{\"wakeAgent\":true,\"data\":$1}"
  exit 0
}

# ── --freeze: sanction the current architecture as the drift baseline ─────────
if [ "${1:-}" = "--freeze" ]; then
  if [ -z "$WATCH_PATHS" ]; then
    echo "WATCH_PATHS is not set — nothing to freeze." >&2
    exit 1
  fi
  compute_watch_hash > "$ARCH_HASH"
  log_event "architecture_frozen"
  echo "Baseline frozen: $(cat "$ARCH_HASH")"
  exit 0
fi

# ── 1. Handout lock (atomic — only serializes concurrent ticks) ──────────────
# v1.3 (#5): short-lived. It guards task selection so two overlapping ticks can't
# hand out the same task. Released before the agent runs (agent holds a lease).
if ! mkdir "$LOCK" 2>/dev/null; then
  lock_age=$(( $(date +%s) - $(mtime "$LOCK") ))
  if [ "$lock_age" -lt "$LOCK_STALE_S" ]; then
    echo "{\"wakeAgent\":false,\"data\":{\"reason\":\"already_running\",\"lock_age_s\":$lock_age}}"
    exit 0
  fi
  log_event "stale_lock_broken"
  rm -rf "$LOCK"
  mkdir "$LOCK"
fi
HAVE_LOCK=true

# ── 1.5 dag.json structure (the shape contract, T186) ────────────────────────
# FIRST, before the state self-heal (which rebuilds through the plan): a missing, unparseable or
# structurally malformed dag.json wakes dag_corrupted EVERY tick, carrying the errors — never a
# dispatch on a broken plan, never a silent sleep.
SHAPE_JSON=$(node -e "const l=require(process.env.HB_DIR+'/hb-lint.js');const r=l.readDagFile(process.env.DAG);const e=r.error?[r.error]:l.shapeErrors(r.dag,true);process.stdout.write(e.length?JSON.stringify(e.slice(0,5)):'')" 2>/dev/null || echo '["dag.json could not be checked (hb-lint.js missing or outdated?)"]')
if [ -n "$SHAPE_JSON" ]; then [ -f "$DAGBAD_FLAG" ] || { touch "$DAGBAD_FLAG"; log_event "dag_corrupted"; }; wake_out "{\"reason\":\"dag_corrupted\",\"errors\":$SHAPE_JSON,\"hint\":\"run node .hb/hb-lint.js .hb/dag.json — restore dag.json from git/backup or fix the named fields\"}"; fi   # shape-guard: tick

rm -f "$DAGBAD_FLAG"

# ── 2. state.json integrity ─────────────────────────────────────────────────
# v1.3 (#2): state.json is a projection of events.jsonl. On corruption, try to
# self-heal by reprojecting from the log; only wake state_corrupted if that fails
# too (log itself unusable).
if ! node -e "JSON.parse(require('fs').readFileSync(process.env.STATE,'utf8'))" 2>/dev/null; then
  if [ -f "$HB_DIR/hb.js" ] && node "$HB_DIR/hb.js" rebuild >/dev/null 2>&1 \
     && node -e "JSON.parse(require('fs').readFileSync(process.env.STATE,'utf8'))" 2>/dev/null; then
    log_event "state_reprojected"
  else
    log_event "state_corrupted"
    wake_out "{\"reason\":\"state_corrupted\",\"hint\":\"rebuild state.json from events.jsonl and dag.json\"}"
  fi
fi

# ── 2.5 Reclaim stale leases (dead/hung agent) → free the task for re-handout ─
# v1.3: a lease with a fresh `beat` marker (mid-session heartbeat) is alive; if it
# goes silent > HEARTBEAT_STALE_S it's hung → reclaim FAST. A lease that never
# beats falls back to the LOCK_STALE_S deadline. Reclaim appends lease_expired so
# the projector returns the task to pending.
if [ -d "$LEASES" ]; then
  reclaimed=false
  for d in "$LEASES"/*/; do
    [ -d "$d" ] || continue
    if [ -f "${d}beat" ]; then
      ref=$(mtime "${d}beat"); threshold="$HEARTBEAT_STALE_S"
    else
      ref=$(mtime "$d");       threshold="$LOCK_STALE_S"
    fi
    lease_age=$(( $(date +%s) - ref ))
    if [ "$lease_age" -ge "$threshold" ]; then
      tid=$(basename "$d")
      rm -rf "$d"
      echo "{\"ts\":\"$TS\",\"event\":\"lease_expired\",\"task\":\"$tid\"}" >> "$EVENTS"
      reclaimed=true
    fi
  done
  [ "$reclaimed" = true ] && node "$HB_DIR/hb.js" rebuild >/dev/null 2>&1 || true
fi

# ── 2.6 Doctor-driven checks: criteria drift, then rot ────────────────────────
# hb doctor is static and cheap; run it ONCE each tick and filter its problems.
# Drift outranks rot and fires EVERY tick until cured (no once-only flag): an
# unsanctioned edit of accepted criteria is laundering, and it must never fade
# into a waiting sleep the way rot does.
if [ "$HB_ROT_CHECK" != "0" ] && [ -f "$HB_DIR/hb.js" ]; then
  DOC_OUT=$(node "$HB_DIR/hb.js" doctor 2>/dev/null || true)
  drift=$(printf '%s\n' "$DOC_OUT" | grep -c "criteria drifted from the pinned evidence" || true)   # drift-guard: tick — the per-tick doctor filter, widened to the drift problem
  if [ "${drift:-0}" -gt 0 ]; then wake_out "{\"reason\":\"criteria_drift\",\"count\":$drift,\"ts\":\"$TS\"}"; fi   # drift-guard: tick — human-needed, every tick until cured
  rot=$(printf '%s\n' "$DOC_OUT" | grep -c "no longer reproducible" || true)
  if [ "${rot:-0}" -gt 0 ]; then
    if [ ! -f "$ROT_FLAG" ]; then
      touch "$ROT_FLAG"
      log_event "gate_rot_detected"
      notify "gate_rot" "$rot gate(s)"
      wake_out "{\"reason\":\"gate_rot\",\"count\":$rot,\"hint\":\"a completed phase's gate references a deleted file — run: node .hb/hb.js doctor\"}"
    fi
    sleep_out "{\"reason\":\"gate_rot_waiting\",\"count\":$rot}"
  fi
  rm -f "$ROT_FLAG"
fi

# ── 3. Circuit breaker (wakes ONCE, then waits for a human reset) ────────────
stuck=$(node -e "
  const s=JSON.parse(require('fs').readFileSync(process.env.STATE,'utf8'));
  console.log(s.build_stuck_count??0);
" 2>/dev/null || echo "0")

if [ "$stuck" -ge 5 ]; then
  if [ ! -f "$STUCK_FLAG" ]; then
    touch "$STUCK_FLAG"
    log_event "circuit_breaker_tripped"
    notify "build_stuck" "count=$stuck"
    wake_out "{\"reason\":\"build_stuck\",\"build_stuck_count\":$stuck}"
  fi
  sleep_out "{\"reason\":\"stuck_waiting_human\",\"build_stuck_count\":$stuck}"
fi
rm -f "$STUCK_FLAG"

# ── 4. Drift detection (baseline auto-frozen on first run) ───────────────────
if [ -n "$WATCH_PATHS" ]; then
  CURRENT=$(compute_watch_hash)
  if [ ! -f "$ARCH_HASH" ]; then
    echo "$CURRENT" > "$ARCH_HASH"
    log_event "architecture_frozen"
  elif [ "$CURRENT" != "$(cat "$ARCH_HASH")" ]; then
    log_event "unsanctioned_drift"
    if [ -n "$HB_NOTIFY_CMD" ] && [ ! -f "$DRIFT_NOTIFY_FLAG" ]; then
      touch "$DRIFT_NOTIFY_FLAG"; notify "unsanctioned_drift" ""
    fi
    wake_out "{\"reason\":\"unsanctioned_drift\",\"hint\":\"review changes; if sanctioned run: bash tick.sh --freeze\",\"ts\":\"$TS\"}"
  else
    rm -f "$DRIFT_NOTIFY_FLAG"
  fi
fi

# ── 5. Gate errors from previous run ──────────────────────────────────────────
gate_errors=$(node -e "
  const s=JSON.parse(require('fs').readFileSync(process.env.STATE,'utf8'));
  console.log(s.gate?.errors??0);
" 2>/dev/null || echo "0")

GBTICKS_FILE="$HB_DIR/.gate-blocked-ticks"
if [ "$gate_errors" -gt 0 ]; then
  gbt=$(cat "$GBTICKS_FILE" 2>/dev/null || echo 0); gbt=$((gbt + 1)); echo "$gbt" > "$GBTICKS_FILE"
  # Circuit breaker: a persistently blocked gate must NOT re-wake the agent every tick forever. After
  # GATE_BLOCKED_MAX no-progress ticks, stop waking and wait for a human (mirrors the build_stuck breaker).
  if [ "$gbt" -ge "${GATE_BLOCKED_MAX:-5}" ]; then
    sleep_out "{\"reason\":\"gate_blocked_waiting_human\",\"gate_errors\":$gate_errors,\"ticks\":$gbt}"
  fi
  if [ -n "$HB_NOTIFY_CMD" ] && [ ! -f "$GATE_NOTIFY_FLAG" ]; then
    touch "$GATE_NOTIFY_FLAG"; notify "gate_blocked" "errors=$gate_errors"
  fi
  wake_out "{\"reason\":\"gate_blocked\",\"gate_errors\":$gate_errors,\"ticks\":$gbt}"
else
  rm -f "$GBTICKS_FILE"
fi
rm -f "$GATE_NOTIFY_FLAG"

# ── 6. Next task lookup ────────────────────────────────────────────────────────
# A resolver that is missing, crashes or prints garbage is a human-needed deadlock (resolver_error)
# — never a silent no_pending_tasks sleep that would swallow the failure forever.
if [ ! -f "$NEXT_TASK_SCRIPT" ]; then
  NEXT='{"type":"deadlock","cause":"resolver_error","detail":{"error":"the resolver script is missing"}}'
else
  NEXT=$(node "$NEXT_TASK_SCRIPT" "$STATE" 2>/dev/null) && RES_RC=0 || RES_RC=$?
  # a usable answer is null, a known verdict type, or a task view with a string id — anything else
  # (a crash, garbage, {}, [], a bare string) is the resolver failing, never a phantom task
  if [ "$RES_RC" != 0 ] || ! printf '%s' "$NEXT" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));const T=['all_done','deadlock','busy','gate_pending','review_pending','replan_pending'];process.exit(d===null||(d&&typeof d==='object'&&!Array.isArray(d)&&(T.includes(d.type)||(d.type===undefined&&typeof d.id==='string'&&d.id)))?0:1)" 2>/dev/null; then
    NEXT="{\"type\":\"deadlock\",\"cause\":\"resolver_error\",\"detail\":{\"error\":\"the resolver failed (exit $RES_RC)\"}}"
  fi
fi
case "$NEXT" in *'"cause":"resolver_error"'*) ;; *) rm -f "$RESERR_FLAG";; esac

if [ -z "$NEXT" ] || [ "$NEXT" = "null" ]; then
  sleep_out "{\"reason\":\"no_pending_tasks\"}"
fi

TYPE=$(echo "$NEXT" | node -e "
  let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
    try{console.log(JSON.parse(d).type??'task');}catch(e){console.log('task');}
  });
")

case "$TYPE" in
  all_done)
    rm -f "$REPLAN_FLAG"
    if [ ! -f "$DONE_FLAG" ]; then
      touch "$DONE_FLAG"
      log_event "project_complete"
      notify "all_done" ""
      wake_out "{\"reason\":\"all_done\",\"next_task\":$NEXT,\"ts\":\"$TS\"}"
    fi
    sleep_out "{\"reason\":\"project_complete\"}"
    ;;
  replan_pending)
    # The flagged last phase completed: a replan decision is owed (append the next horizon, or
    # hb horizon close). Wake ONCE per horizon phase — the flag stores the phase id, so a stale
    # flag from an earlier horizon never silences a newer one. No event: the log records
    # decisions, not notifications.
    rm -f "$DEADLOCK_FLAG"
    RP_PHASE=$(echo "$NEXT" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{process.stdout.write(String(JSON.parse(d).phase??''));}catch(e){process.stdout.write('');}});")
    RP_JSON=$(RP="$RP_PHASE" node -e "process.stdout.write(JSON.stringify(process.env.RP))")
    if [ "$(cat "$REPLAN_FLAG" 2>/dev/null || true)" != "$RP_PHASE" ]; then printf '%s' "$RP_PHASE" > "$REPLAN_FLAG"; notify "replan_pending" "$RP_PHASE"; wake_out "{\"reason\":\"replan_pending\",\"phase\":$RP_JSON,\"next_task\":$NEXT,\"ts\":\"$TS\"}"; fi   # horizon-guard: tick
    sleep_out "{\"reason\":\"replan_waiting\",\"phase\":$RP_JSON}"
    ;;
  deadlock)
    # a broken resolver (resolver_error) stays LOUD every tick — no later tick may sleep past it;
    # the alert flag still bounds the event and the notification to once per blockage
    if printf '%s' "$NEXT" | grep -q '"cause":"resolver_error"'; then
      [ -f "$RESERR_FLAG" ] || { touch "$RESERR_FLAG"; notify "deadlock" "resolver_error"; }
      wake_out "{\"reason\":\"deadlock\",\"next_task\":$NEXT,\"ts\":\"$TS\"}"
    fi
    if [ ! -f "$DEADLOCK_FLAG" ]; then
      touch "$DEADLOCK_FLAG"
      log_event "deadlock_detected"
      notify "deadlock" ""
      wake_out "{\"reason\":\"deadlock\",\"next_task\":$NEXT,\"ts\":\"$TS\"}"
    fi
    sleep_out "{\"reason\":\"deadlock_waiting\",\"detail\":$NEXT}"
    ;;
  busy)
    # v1.3 (#5): the only ready work is already leased in another session → wait.
    rm -f "$DEADLOCK_FLAG"
    sleep_out "{\"reason\":\"at_capacity\",\"detail\":$NEXT}"
    ;;
  gate_pending)
    rm -f "$DEADLOCK_FLAG"
    # A pending regate needs a DIFFERENT actor's rearm — waking gate_pending forever over it would
    # busy-loop every unattended run (refusals append no event, so no breaker ever trips). Sleep a
    # non-PROTOCOL reason instead (the gate_blocked_waiting_human precedent).
    RG_TICK=$(echo "$NEXT" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{const n=JSON.parse(d);const dag=JSON.parse(require('fs').readFileSync(process.env.DAG,'utf8'));const g=((dag.gates||{})[n.gate]||{});if(!Object.prototype.hasOwnProperty.call(g,'regate'))return process.stdout.write('');const r=g.regate;const clear=r&&typeof r==='object'&&!Array.isArray(r)&&r.pending===false;process.stdout.write(clear?'':String(n.gate));}catch(e){process.stdout.write('');}});" 2>/dev/null)   # regate-guard: tick-sleep
    [ -n "$RG_TICK" ] && sleep_out "{\"reason\":\"regate_pending_waiting\",\"gate\":\"$RG_TICK\"}"   # regate-guard: tick-sleep
    wake_out "{\"reason\":\"gate_pending\",\"next_task\":$NEXT,\"ts\":\"$TS\"}"
    ;;
  review_pending)
    # v1.4 (#3): deterministic gate passed — an adversarial review is owed.
    # v1.6: a review that never resolves (agent doesn't run it / session died) is a
    # SILENT stall — the no-progress breaker now covers reviews too. Count review
    # wakes for this gate since its last verdict; past the threshold → escalate.
    rm -f "$DEADLOCK_FLAG"
    RGATE=$(echo "$NEXT" | node -e "
      let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
        try{process.stdout.write(String(JSON.parse(d).gate||''));}catch(e){process.stdout.write('');}
      });")
    noreview=$(node -e "
      const fs=require('fs'); const g=process.argv[1];
      let raw=''; try{raw=fs.readFileSync(process.env.EVENTS,'utf8');}catch(e){}
      const lines=raw.split('\n').filter(Boolean); let n=0;
      for(let i=lines.length-1;i>=0;i--){
        let ev; try{ev=JSON.parse(lines[i]);}catch(e){continue;}
        if(ev.gate===g && (ev.event==='review_passed'||ev.event==='review_failed'||ev.event==='gate_passed')) break;
        if(ev.event==='review_wake' && ev.gate===g) n++;
      }
      console.log(n);
    " "$RGATE" 2>/dev/null || echo 0)

    RGP=$([ -n "$RGATE" ] && node -e "const dag=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));const g=((dag.gates||{})[process.argv[2]]||{});let out='';if(Object.prototype.hasOwnProperty.call(g,'regate')){const r=g.regate;const clear=r&&typeof r==='object'&&!Array.isArray(r)&&r.pending===false;out=clear?'':'1';}process.stdout.write(out);" "$DAG" "$RGATE" 2>/dev/null || true)   # regate-guard: tick-sleep
    [ -n "${RGP:-}" ] && sleep_out "{\"reason\":\"regate_pending_waiting\",\"gate\":\"$RGATE\"}"   # regate-guard: tick-sleep

    if [ -n "$RGATE" ] && [ "$noreview" -ge "$STUCK_TICKS" ]; then
      if [ ! -f "$REVIEW_STUCK_FLAG" ]; then
        touch "$REVIEW_STUCK_FLAG"
        log_event "review_stalled"
        notify "review_stuck" "$RGATE"
        wake_out "{\"reason\":\"review_stuck\",\"gate\":\"$RGATE\",\"no_review\":$noreview,\"hint\":\"the adversarial review isn't resolving — run the refuter, then: hb review $RGATE pass|fail\"}"
      fi
      sleep_out "{\"reason\":\"review_waiting\",\"gate\":\"$RGATE\"}"
    fi
    rm -f "$REVIEW_STUCK_FLAG"
    [ -n "$RGATE" ] && echo "{\"ts\":\"$TS\",\"event\":\"review_wake\",\"gate\":\"$RGATE\"}" >> "$EVENTS"
    wake_out "{\"reason\":\"review_pending\",\"next_task\":$NEXT,\"ts\":\"$TS\"}"
    ;;
  *)
    rm -f "$DONE_FLAG" "$DEADLOCK_FLAG" "$REPLAN_FLAG"
    # v1.3 (#3): objective no-progress detection. Count how many times we've
    # already woken for THIS task with no task_started/done/failed since.
    TASK_ID=$(echo "$NEXT" | node -e "
      let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
        try{process.stdout.write(String(JSON.parse(d).id||''));}catch(e){process.stdout.write('');}
      });")

    # v1.3 (#5): capacity gate — never exceed HB_MAX_CONCURRENCY tasks in flight.
    # In-flight == active leases. The resolver already excluded leased tasks, so
    # NEXT is an unleased ready task; we just enforce the cap here.
    in_flight=0
    if [ -d "$LEASES" ]; then
      in_flight=$(find "$LEASES" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [ -n "$TASK_ID" ] && [ "${in_flight:-0}" -ge "$HB_MAX_CONCURRENCY" ]; then
      sleep_out "{\"reason\":\"at_capacity\",\"in_flight\":${in_flight:-0},\"max\":$HB_MAX_CONCURRENCY}"
    fi
    noprog=$(node -e "
      const fs=require('fs'); const id=process.argv[1];
      let raw=''; try{raw=fs.readFileSync(process.env.EVENTS,'utf8');}catch(e){}
      const lines=raw.split('\n').filter(Boolean); let n=0;
      for(let i=lines.length-1;i>=0;i--){
        let ev; try{ev=JSON.parse(lines[i]);}catch(e){continue;}
        if(ev.task===id && (ev.event==='task_started'||ev.event==='task_done'||ev.event==='task_failed')) break;
        if(ev.event==='wake' && ev.task===id) n++;
      }
      console.log(n);
    " "$TASK_ID" 2>/dev/null || echo 0)

    if [ -n "$TASK_ID" ] && [ "$noprog" -ge "$STUCK_TICKS" ]; then
      if [ ! -f "$NOPROG_FLAG" ]; then
        touch "$NOPROG_FLAG"
        log_event "circuit_breaker_tripped"
        notify "build_stuck" "no_progress $TASK_ID"
        wake_out "{\"reason\":\"build_stuck\",\"signal\":\"no_progress\",\"task\":\"$TASK_ID\",\"no_progress\":$noprog}"
      fi
      sleep_out "{\"reason\":\"stuck_waiting_human\",\"signal\":\"no_progress\",\"task\":\"$TASK_ID\"}"
    fi
    rm -f "$NOPROG_FLAG"
    # v1.3 (#5): claim the task with an atomic lease before waking. We hold the
    # handout lock and the resolver excluded leased tasks, so this can't collide.
    if [ -n "$TASK_ID" ]; then
      mkdir -p "$LEASES"
      mkdir "$LEASES/$TASK_ID" 2>/dev/null || true
      # Record this wake so repeated no-progress wakes are counted next tick.
      echo "{\"ts\":\"$TS\",\"event\":\"wake\",\"task\":\"$TASK_ID\"}" >> "$EVENTS"
    fi
    wake_out "{\"reason\":\"next_task\",\"next_task\":$NEXT,\"ts\":\"$TS\"}"
    ;;
esac
