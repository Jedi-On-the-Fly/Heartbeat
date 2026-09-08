#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# HeartBeat v1.1 — Regression suite
# Covers the 3 v1.0 bugs + the v1.1 reliability fixes.
# Usage: bash tests/run-tests.sh    (exit 0 = all green)
# ══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

HB_SRC="$(cd "$(dirname "$0")/.." && pwd)"
# v1.3: keep objective no-progress detection (#3) from tripping in tests that tick
# repeatedly on a pending task without running an agent. The dedicated no-progress
# test sets STUCK_TICKS low locally.
export STUCK_TICKS=999
# v1.4: keep git init / commit-on-gate-pass out of the throwaway test projects by
# default; T26 opts back in explicitly (HB_NO_GIT="").
export HB_NO_GIT=1
# v1.6: keep the per-tick rot check out of unrelated tests (T30 opts back in).
export HB_ROT_CHECK=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"
HB="$P/.hb"

PASS=0; FAIL=0
declare -A _GFAIL; declare -A _GCHECKS; _CURG=""; _ALLG=""
# grp "<Tnn — title>" — start a group; enables an outcome marker (GROUPS-PASSED) so a
# coverage gate can assert a group PASSED, not just that its header exists.
grp(){ _CURG="${1%% *}"; case " $_ALLG " in *" $_CURG "*) ;; *) _ALLG="$_ALLG $_CURG";; esac; echo "═══ $1 ═══"; }
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); [ -n "$_CURG" ] && _GCHECKS["$_CURG"]=1; }
ko(){ echo "  ✗ $1"; FAIL=$((FAIL+1)); [ -n "$_CURG" ] && { _GFAIL["$_CURG"]=1; _GCHECKS["$_CURG"]=1; }; }
# H1 coverage floor: a run that silently SKIPPED most groups (a stripped box) must NOT read green.
_coverage_check(){ local skipped="${2:-0}" floor="${HB_SKIP_FLOOR:-20}"; if [ "$skipped" -gt "$floor" ]; then echo "⚠ COVERAGE-INCOMPLETE: $skipped groups skipped (> floor $floor) — suite NOT fully verified"; return 3; fi; return 0; }
check(){ if eval "$2" >/dev/null 2>&1; then ok "$1"; else ko "$1"; fi; }
set_state(){ node -e "const fs=require('fs');const f=process.argv[1];const s=JSON.parse(fs.readFileSync(f,'utf8'));${1};fs.writeFileSync(f,JSON.stringify(s,null,2));" "$HB/state.json"; }
tick(){ rm -rf "$HB/.lock"; bash "$HB/tick.sh"; }

grp "T1 — bootstrap (non-interactive)"
bash "$HB_SRC/plugin/bootstrap.sh" "$P" >/dev/null 2>&1 </dev/null
check "T1.1 .hb/ created with the 6 files" \
  '[ -f "$HB/tick.sh" ] && [ -f "$HB/gate.sh" ] && [ -f "$HB/hb-next-task.js" ] && [ -f "$HB/dag.json" ] && [ -f "$HB/state.json" ] && [ -f "$HB/events.jsonl" ]'
bash "$HB_SRC/plugin/bootstrap.sh" "$P" >/dev/null 2>&1 </dev/null
check "T1.2 re-bootstrap without tty → clean refusal (no crash)" '[ $? -eq 0 ]'

grp "T2 — gate.sh out-of-the-box (bug #1)"
# v1.3: gate.sh now reprojects state (a passing gate advances the phase), so run
# it on a dedicated throwaway project — the shared $HB must stay pristine for T3+.
PG="$TMP/gate"; bash "$HB_SRC/plugin/bootstrap.sh" "$PG" >/dev/null 2>&1 </dev/null; HBG="$PG/.hb"
out=$(bash "$HBG/gate.sh" GATE_P0 2>&1); rc=$?
check "T2.1 GATE_P0 passes (exit 0)" '[ "$rc" -eq 0 ]'
check "T2.2 the 2 criteria are evaluated (PROJECT_DIR set)" 'echo "$out" | grep -q "2 passed, 0 failed"'
out=$(bash "$HBG/gate.sh" GATE_NONEXISTENT 2>&1); rc=$?
check "T2.3 unknown gate → exit 2 + message" '[ "$rc" -eq 2 ] && echo "$out" | grep -q "Unknown gate"'

grp "T3 — resolver gate-aware (bug #2)"
set_state 's.completed_tasks=["P0T1","P0T2"]'
next=$(node "$HB/hb-next-task.js" "$HB/state.json")
check "T3.1 P0 done, gate NOT passed → gate_pending (not P1T1)" \
  'echo "$next" | grep -q gate_pending && echo "$next" | grep -qv P1T1'
check "T3.2 gate_pending points at GATE_P0" 'echo "$next" | grep -q GATE_P0'
set_state 's.completed_phases=["P0"]'
next=$(node "$HB/hb-next-task.js" "$HB/state.json")
check "T3.3 phase P0 closed → P1T1 served" 'echo "$next" | grep -q P1T1'

grp "T4 — state.json corrupted → auto-repair (v1.3, #2)"
cp "$HB/state.json" "$TMP/state.bak"
echo "{broken" > "$HB/state.json"
out=$(tick)
check "T4.1 corruption + intact log → auto reprojection (state.json revalidated, no corrupted wake)" \
  'node -e "JSON.parse(require(\"fs\").readFileSync(\"$HB/state.json\",\"utf8\"))" && ! echo "$out" | grep -q state_corrupted'
mv "$HB/hb.js" "$HB/hb.js.bak"
echo "{broken" > "$HB/state.json"
out=$(tick)
check "T4.2 corruption without hb.js (pre-v1.3 project) → WAKE state_corrupted (safety net)" \
  'echo "$out" | grep -q state_corrupted && echo "$out" | grep -q "\"wakeAgent\":true"'
mv "$HB/hb.js.bak" "$HB/hb.js"
cp "$TMP/state.bak" "$HB/state.json"

grp "T5 — leases & handout lock (v1.3, #5)"
set_state 's.completed_tasks=[];s.completed_phases=[];s.active_tasks=[]'; rm -rf "$HB/leases"
out=$(tick)
check "T5.1 tick with work → wakeAgent:true (next_task)" \
  'echo "$out" | grep -q "\"wakeAgent\":true" && echo "$out" | grep -q next_task'
TID=$(echo "$out" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{process.stdout.write(String(JSON.parse(d).data.next_task.id));}catch(e){}})")
check "T5.2 task leased by the tick + handout lock released" '[ -d "$HB/leases/$TID" ] && [ ! -d "$HB/.lock" ]'
out=$(tick)
check "T5.3 in-progress task leased → at_capacity/busy (no 2nd agent in parallel)" \
  'echo "$out" | grep -qE "at_capacity|busy" && echo "$out" | grep -q "\"wakeAgent\":false"'
touch -d "2 hours ago" "$HB/leases/$TID"
out=$(tick)
check "T5.4 expired lease → reclaim (lease_expired) + task re-served" \
  'grep -q lease_expired "$HB/events.jsonl" && echo "$out" | grep -q "\"wakeAgent\":true"'
rm -rf "$HB/leases"

grp "T6 — circuit breaker (single alert)"
set_state 's.build_stuck_count=5'
out1=$(tick)
check "T6.1 first tick → build_stuck wake" 'echo "$out1" | grep -q build_stuck && echo "$out1" | grep -q "\"wakeAgent\":true"'
out2=$(tick)
check "T6.2 second tick → SILENCE (stuck_waiting_human)" \
  'echo "$out2" | grep -q stuck_waiting_human && echo "$out2" | grep -q "\"wakeAgent\":false"'
set_state 's.build_stuck_count=0'
tick >/dev/null
check "T6.3 human reset → alert flag cleared" '[ ! -f "$HB/.stuck-alerted" ]'

grp "T7 — gate_blocked"
set_state 's.gate.errors=1'
out=$(tick)
check "T7.1 gate failing → gate_blocked wake" 'echo "$out" | grep -q gate_blocked'
set_state 's.gate.errors=0'

grp "T8 — drift + freeze"
mkdir -p "$P/core"; echo "module.exports=1;" > "$P/core/a.js"
sed -i 's|^WATCH_PATHS=.*|WATCH_PATHS="$PROJECT_DIR/core/*.js"|' "$HB/tick.sh"
tick >/dev/null
check "T8.1 baseline auto-frozen on first run" '[ -f "$HB/architecture.hash" ]'
echo "// drift" >> "$P/core/a.js"
out=$(tick)
check "T8.2 unsanctioned modification → unsanctioned_drift wake" 'echo "$out" | grep -q unsanctioned_drift'
bash "$HB/tick.sh" --freeze >/dev/null
out=$(tick)
check "T8.3 after --freeze → no more drift" 'echo "$out" | grep -qv unsanctioned_drift'

grp "T9 — all_done (single alert)"
set_state 's.completed_tasks=["P0T1","P0T2","P1T1","P1T2","P1T3"];s.completed_phases=["P0","P1"]'
out1=$(tick)
check "T9.1 project done → ONE all_done wake (final report)" 'echo "$out1" | grep -q all_done && echo "$out1" | grep -q "\"wakeAgent\":true"'
out2=$(tick)
check "T9.2 subsequent ticks → project_complete, silence" \
  'echo "$out2" | grep -q project_complete && echo "$out2" | grep -q "\"wakeAgent\":false"'

grp "T10 — documentation consistency"
check "T10.1 README documents the tick checks and --freeze" \
  'grep -qi "priority checks" "$HB_SRC/README.md" && grep -q -- "--freeze" "$HB_SRC/README.md"'
check "T10.2 STATUS is current (v1.6) and covers doctor/rot" \
  'grep -q "v1.6" "$HB_SRC/STATUS.md" && grep -qi "rot" "$HB_SRC/STATUS.md"'
check "T10.3 README documents the hb CLI tick protocol" \
  'grep -q "hb.js start" "$HB_SRC/README.md" && grep -qi "tick protocol" "$HB_SRC/README.md"'

grp "T11 — hb-lint (v1.2)"
FX="$HB_SRC/tests/fixtures"
check "T11.1 duplicate IDs detected" '! node "$HB_SRC/plugin/templates/hb-lint.js" "$FX/lint-dup-ids.json"'
check "T11.2 cycle detected" '! node "$HB_SRC/plugin/templates/hb-lint.js" "$FX/lint-cycle.json"'
check "T11.3 broken requires detected" '! node "$HB_SRC/plugin/templates/hb-lint.js" "$FX/lint-missing-ref.json"'
check "T11.4 undefined gate detected" '! node "$HB_SRC/plugin/templates/hb-lint.js" "$FX/lint-undefined-gate.json"'
check "T11.5 phase >8 tasks = warning only" 'node "$HB_SRC/plugin/templates/hb-lint.js" "$FX/lint-big-phase.json"'
check "T11.6 dag template valid" 'node "$HB_SRC/plugin/templates/hb-lint.js" "$HB_SRC/plugin/templates/dag.json"'
check "T11.7 bootstrap lints the dag" 'grep -q hb-lint "$HB_SRC/plugin/bootstrap.sh" && [ -f "$HB/hb-lint.js" ]'

grp "T12 — deadlock & corrupted dag (v1.2)"
next=$(node "$HB_SRC/plugin/templates/hb-next-task.js" "$FX/deadlock-missing-ref/state.json")
check "T12.1 broken requires → deadlock diagnosed (dag_invalid)" 'echo "$next" | grep -q deadlock && echo "$next" | grep -q dag_invalid'
next=$(node "$HB_SRC/plugin/templates/hb-next-task.js" "$FX/deadlock-orphan/state.json")
check "T12.2 orphan active task → active_orphan" 'echo "$next" | grep -q active_orphan'
P2="$TMP/proj2"; bash "$HB_SRC/plugin/bootstrap.sh" "$P2" >/dev/null 2>&1 </dev/null
HB2="$P2/.hb"
node -e "const fs=require('fs');const f='$HB2/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));d.phases[0].tasks[1].requires=['GHOST'];fs.writeFileSync(f,JSON.stringify(d,null,2));"
node -e "const fs=require('fs');const f='$HB2/state.json';const s=JSON.parse(fs.readFileSync(f,'utf8'));s.completed_tasks=['P0T1'];fs.writeFileSync(f,JSON.stringify(s,null,2));"
rm -rf "$HB2/.lock"; out1=$(bash "$HB2/tick.sh")
check "T12.3 tick → ONE deadlock wake" 'echo "$out1" | grep -q "\"reason\":\"deadlock\"" && echo "$out1" | grep -q "\"wakeAgent\":true"'
rm -rf "$HB2/.lock"; out2=$(bash "$HB2/tick.sh")
check "T12.4 second tick → deadlock_waiting, silence" 'echo "$out2" | grep -q deadlock_waiting && echo "$out2" | grep -q "\"wakeAgent\":false"'
echo "{broken" > "$HB2/dag.json"
rm -rf "$HB2/.lock"; out=$(bash "$HB2/tick.sh")
check "T12.5 dag.json corrupted → dag_corrupted wake" 'echo "$out" | grep -q dag_corrupted'

grp "T13 — hb-report (v1.2)"
check "T13.1 text report generated with phases" 'node "$HB_SRC/plugin/templates/hb-report.js" "$HB" | grep -q "P0"'
check "T13.2 --json report parseable" 'node "$HB_SRC/plugin/templates/hb-report.js" "$HB" --json > "$TMP/r.json" && node -e "JSON.parse(require(\"fs\").readFileSync(\"$TMP/r.json\",\"utf8\"))"'
check "T13.3 incidents counted (T6 stuck visible)" 'node "$HB_SRC/plugin/templates/hb-report.js" "$HB" | grep -q circuit_breaker_tripped'

grp "T14 — hb-viz (v1.2)"
node "$HB_SRC/plugin/templates/hb-viz.js" "$HB" >/dev/null
check "T14.1 dag-view.html generated" '[ -f "$HB/dag-view.html" ]'
check "T14.2 self-contained (no external URL)" '! grep -qE "https?://" "$HB/dag-view.html"'
check "T14.3 task statuses embedded" 'grep -q "t-done" "$HB/dag-view.html" && grep -q P0T1 "$HB/dag-view.html"'

grp "T15 — packaging Claude Code (plugin + install script)"
check "T15.1 plugin.json valid + name=heartbeat" \
  'node -e "const m=JSON.parse(require(String.raw\`fs\`).readFileSync(process.argv[1]));process.exit(m.name===\"heartbeat\"?0:1)" "$HB_SRC/plugin/.claude-plugin/plugin.json"'
check "T15.2 marketplace.json valid + lists heartbeat" \
  'node -e "const m=JSON.parse(require(String.raw\`fs\`).readFileSync(process.argv[1]));process.exit(m.plugins.some(p=>p.name===\"heartbeat\")?0:1)" "$HB_SRC/.claude-plugin/marketplace.json"'
check "T15.3 skill present with frontmatter name" \
  '[ -f "$HB_SRC/plugin/skills/heartbeat/SKILL.md" ] && head -5 "$HB_SRC/plugin/skills/heartbeat/SKILL.md" | grep -q "^name: heartbeat"'
check "T15.4 no /workspace/group path in the plugin files" \
  '! grep -Rq "/workspace/group" "$HB_SRC/plugin" "$HB_SRC/.claude-plugin" "$HB_SRC/CLAUDE-MD-SNIPPET.md"'
check "T15.5 scheduling adapted to routines (no schedule_task in the skill)" \
  '! grep -q "schedule_task" "$HB_SRC/plugin/skills/heartbeat/SKILL.md" && grep -q "/schedule routine" "$HB_SRC/plugin/skills/heartbeat/SKILL.md"'
check "T15.6 install.sh → sandbox HOME installs skill + tooling + smoke" \
  'SBX=$(mktemp -d); HOME="$SBX" bash "$HB_SRC/scripts/install.sh" >/dev/null 2>&1 && [ -f "$SBX/.claude/skills/heartbeat/SKILL.md" ] && [ -f "$SBX/.claude/heartbeat/bootstrap.sh" ]; rc=$?; rm -rf "$SBX"; [ $rc -eq 0 ]'
check "T15.7 skill installed by script has concrete paths (var substituted)" \
  'SBX=$(mktemp -d); HOME="$SBX" bash "$HB_SRC/scripts/install.sh" >/dev/null 2>&1; ! grep -q "CLAUDE_PLUGIN_ROOT" "$SBX/.claude/skills/heartbeat/SKILL.md"; rc=$?; rm -rf "$SBX"; [ $rc -eq 0 ]'
check "T15.8 skill documents /heartbeat plan (plan → dag.json conversion)" \
  'grep -q "/heartbeat plan" "$HB_SRC/plugin/skills/heartbeat/SKILL.md" && grep -q "Spec-first" "$HB_SRC/plugin/skills/heartbeat/SKILL.md"'

grp "T16 — hb CLI & event-sourced projection (v1.3, #1/#2)"
P16="$TMP/p16"; bash "$HB_SRC/plugin/bootstrap.sh" "$P16" >/dev/null 2>&1 </dev/null; H16="$P16/.hb"
node "$H16/hb.js" start P0T1 >/dev/null; node "$H16/hb.js" done P0T1 >/dev/null
check "T16.1 hb done → task in completed_tasks (derived from the log)" 'node "$H16/hb.js" state | grep -q "\"P0T1\""'
node "$H16/hb.js" fail P0T2 >/dev/null
check "T16.2 hb fail → derived build_stuck_count incremented" \
  'node "$H16/hb.js" state | node -e "let d=\"\";process.stdin.on(\"data\",c=>d+=c).on(\"end\",()=>process.exit(JSON.parse(d).build_stuck_count>=1?0:1))"'
node "$H16/hb.js" rebuild >/dev/null; A16=$(node -e "const s=require(\"$H16/state.json\");delete s.last_updated;console.log(JSON.stringify(s))")
node "$H16/hb.js" rebuild >/dev/null; B16=$(node -e "const s=require(\"$H16/state.json\");delete s.last_updated;console.log(JSON.stringify(s))")
check "T16.3 deterministic rebuild (state = pure projection of the log)" '[ "$A16" = "$B16" ]'
echo "{broken" > "$H16/state.json"
check "T16.4 corrupted state → hb rebuild repairs from the log" \
  'node "$H16/hb.js" rebuild >/dev/null && node -e "JSON.parse(require(\"fs\").readFileSync(\"$H16/state.json\",\"utf8\"))"'
P16b="$TMP/p16b"; bash "$HB_SRC/plugin/bootstrap.sh" "$P16b" >/dev/null 2>&1 </dev/null; H16b="$P16b/.hb"
node -e "const fs=require(\"fs\");const f=\"$H16b/state.json\";const s=JSON.parse(fs.readFileSync(f,\"utf8\"));s.completed_tasks=[\"P0T1\"];fs.writeFileSync(f,JSON.stringify(s,null,2))"
node "$H16b/hb.js" import >/dev/null
check "T16.5 legacy migration (hb import) → log reconstructed (P0T1 done)" 'node "$H16b/hb.js" state | grep -q "\"P0T1\""'

grp "T17 — objective no-progress detection (v1.3, #3)"
P17="$TMP/p17"; bash "$HB_SRC/plugin/bootstrap.sh" "$P17" >/dev/null 2>&1 </dev/null; H17="$P17/.hb"
# simulate a woken agent that makes no progress AND releases its lease → re-served every tick
t17(){ rm -rf "$H17/.lock" "$H17/leases"; STUCK_TICKS=3 bash "$H17/tick.sh"; }
t17 >/dev/null; t17 >/dev/null; t17 >/dev/null
o17=$(t17)
check "T17.1 N wakes without progress → build_stuck (no_progress signal)" \
  'echo "$o17" | grep -q build_stuck && echo "$o17" | grep -q no_progress'
o17b=$(t17)
check "T17.2 next wake → SILENCE (stuck_waiting_human)" \
  'echo "$o17b" | grep -q stuck_waiting_human && echo "$o17b" | grep -q "\"wakeAgent\":false"'
node "$H17/hb.js" start P0T1 >/dev/null; node "$H17/hb.js" done P0T1 >/dev/null
o17c=$(t17)
check "T17.3 progress (hb done) → counter reset, tick resumes" \
  'echo "$o17c" | grep -q next_task && [ ! -f "$H17/.noprogress-alerted" ]'

grp "T18 — gate criteria timeout (v1.3, #4)"
P18="$TMP/p18"; bash "$HB_SRC/plugin/bootstrap.sh" "$P18" >/dev/null 2>&1 </dev/null; H18="$P18/.hb"
node -e "const fs=require(\"fs\");const f=\"$H18/dag.json\";const d=JSON.parse(fs.readFileSync(f,\"utf8\"));d.gates.GATE_SLOW={desc:\"s\",criteria:[{id:\"S\",desc:\"hang\",cmd:\"sleep 10\"}]};fs.writeFileSync(f,JSON.stringify(d,null,2))"
s18=$(date +%s); GATE_TIMEOUT_S=1 bash "$H18/gate.sh" GATE_SLOW >/dev/null 2>&1; rc18=$?; e18=$(date +%s)
check "T18.1 slow criterion → gate blocked (exit 1)" '[ "$rc18" -eq 1 ]'
check "T18.2 fast timeout (< 5s — no frozen tick)" '[ $((e18-s18)) -lt 5 ]'

grp "T19 — leases & bounded concurrency (v1.3, #5)"
P19="$TMP/p19"; bash "$HB_SRC/plugin/bootstrap.sh" "$P19" >/dev/null 2>&1 </dev/null; H19="$P19/.hb"
node -e "const fs=require(\"fs\");const f=\"$H19/dag.json\";const d=JSON.parse(fs.readFileSync(f,\"utf8\"));d.phases=[{id:'P0',title:'P',gate_entry:null,gate_exit:'GATE_P0',tasks:[{id:'A',title:'a',requires:[]},{id:'B',title:'b',requires:[]},{id:'C',title:'c',requires:[]}]}];d.gates={GATE_P0:{desc:'g',criteria:[{id:'g',desc:'ok',cmd:'true'}]}};fs.writeFileSync(f,JSON.stringify(d,null,2))"
node -e "const fs=require(\"fs\");const f=\"$H19/state.json\";const s=JSON.parse(fs.readFileSync(f,\"utf8\"));s.completed_tasks=[];s.completed_phases=[];s.active_tasks=[];fs.writeFileSync(f,JSON.stringify(s,null,2))"
t19(){ rm -rf "$H19/.lock"; STUCK_TICKS=999 HB_MAX_CONCURRENCY=2 bash "$H19/tick.sh"; }
t19 >/dev/null; t19 >/dev/null; o19=$(t19)
check "T19.1 cap=2 → 2 DISTINCT tasks leased in parallel" '[ "$(ls "$H19/leases" | wc -l)" -eq 2 ]'
check "T19.2 3rd task ready but cap reached → at_capacity" 'echo "$o19" | grep -q at_capacity'
check "T19.3 no double-claim (atomic mkdir lease)" '! mkdir "$H19/leases/A" 2>/dev/null'
f19=$(ls "$H19/leases" | head -1); node "$H19/hb.js" done "$f19" >/dev/null
check "T19.4 hb done frees a slot → remaining task served" 'o=$(t19); echo "$o" | grep -q next_task'

grp "T20 — mid-session heartbeat (fast reclaim of hung leases)"
P20="$TMP/p20"; bash "$HB_SRC/plugin/bootstrap.sh" "$P20" >/dev/null 2>&1 </dev/null; H20="$P20/.hb"
mkdir -p "$H20/leases/P0T1"
node "$H20/hb.js" heartbeat P0T1 >/dev/null
check "T20.1 hb heartbeat → beat marker created" '[ -f "$H20/leases/P0T1/beat" ]'
touch -d "1 hour ago" "$H20/leases/P0T1/beat"
rm -rf "$H20/.lock"; HEARTBEAT_STALE_S=120 bash "$H20/tick.sh" >/dev/null 2>&1
check "T20.2 stale beat (>HEARTBEAT_STALE_S, <LOCK_STALE_S) → fast reclaim" \
  'grep lease_expired "$H20/events.jsonl" | grep -q P0T1'
mkdir -p "$H20/leases/P0T3"; node "$H20/hb.js" heartbeat P0T3 >/dev/null
rm -rf "$H20/.lock"; HEARTBEAT_STALE_S=120 bash "$H20/tick.sh" >/dev/null 2>&1
check "T20.3 fresh beat → lease kept alive" '[ -d "$H20/leases/P0T3" ]'
mkdir -p "$H20/leases/P0T4"
rm -rf "$H20/.lock"; HEARTBEAT_STALE_S=120 bash "$H20/tick.sh" >/dev/null 2>&1
check "T20.4 lease without beat & recent → kept (LOCK_STALE_S fallback, no false reclaim)" \
  '[ -d "$H20/leases/P0T4" ] && ! ( grep lease_expired "$H20/events.jsonl" | grep -q P0T4 )'

grp "T21 — hb-lint advisory warnings (v1.4, #1)"
LINT="$HB_SRC/plugin/templates/hb-lint.js"
warns(){ node "$LINT" "$1" --json | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>process.stdout.write((JSON.parse(d).warnings||[]).join('\n')))"; }
check "T21.1 dag template → 'skeleton' warning (placeholder)" \
  'node "$LINT" "$HB_SRC/plugin/templates/dag.json" --json | grep -qi skeleton'
check "T21.2 gate references a file not produced → dangling warning" \
  'warns "$FX/lint-dangling.json" | grep -q "ghost.spec.js"'
check "T21.3 file produced by a task → NO warning" \
  '! ( warns "$FX/lint-dangling.json" | grep -q "src/app.js" )'
check "T21.4 warnings do not change the exit (valid DAG → 0)" \
  'node "$LINT" "$FX/lint-dangling.json" >/dev/null 2>&1'
check "T21.5 structural error → always exit 1" \
  '! node "$LINT" "$FX/lint-dup-ids.json" >/dev/null 2>&1'

grp "T22 — notify hook (v1.4, #2)"
P22="$TMP/p22"; bash "$HB_SRC/plugin/bootstrap.sh" "$P22" >/dev/null 2>&1 </dev/null; H22="$P22/.hb"
NF22="$TMP/notify22.log"; : > "$NF22"
NCMD22="printf '%s|%s|%s\n' \"\$1\" \"\$2\" \"\$3\" >> $NF22"
setb22(){ node -e "const fs=require('fs');const f='$H22/state.json';const s=JSON.parse(fs.readFileSync(f,'utf8'));s.build_stuck_count=5;fs.writeFileSync(f,JSON.stringify(s,null,2))"; }
setb22; rm -rf "$H22/.lock"; HB_NOTIFY_CMD="$NCMD22" bash "$H22/tick.sh" >/dev/null 2>&1
check "T22.1 wake human-needed → HB_NOTIFY_CMD receives reason|project|detail" \
  'grep -q "build_stuck|p22|count=5" "$NF22"'
rm -rf "$H22/.lock"; HB_NOTIFY_CMD="$NCMD22" bash "$H22/tick.sh" >/dev/null 2>&1
check "T22.2 next tick → NO re-notification (fire-once)" \
  '[ "$(wc -l < "$NF22")" -eq 1 ]'
setb22; rm -f "$H22/.stuck-alerted"; rm -rf "$H22/.lock"
out=$(bash "$H22/tick.sh" 2>&1); rc=$?
check "T22.3 HB_NOTIFY_CMD unset → tick unchanged (no-op)" \
  '[ $rc -eq 0 ] && echo "$out" | grep -q build_stuck'
rm -f "$H22/.stuck-alerted"; rm -rf "$H22/.lock"
out=$(HB_NOTIFY_CMD="nope_xyz; exit 7" bash "$H22/tick.sh" 2>&1); rc=$?
check "T22.4 failing notify → never interrupts the tick" \
  '[ $rc -eq 0 ] && echo "$out" | grep -q build_stuck'

grp "T23 — hb ready & parallelism (v1.4, #4)"
P23="$TMP/p23"; bash "$HB_SRC/plugin/bootstrap.sh" "$P23" >/dev/null 2>&1 </dev/null; H23="$P23/.hb"
node -e "const fs=require('fs');const f='$H23/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));d.phases=[{id:'P0',title:'P',gate_entry:null,gate_exit:'GATE_P0',tasks:[{id:'A',title:'a',requires:[]},{id:'B',title:'b',requires:[]},{id:'C',title:'c',requires:['A']}]}];d.gates={GATE_P0:{desc:'g',criteria:[{id:'g',desc:'ok',cmd:'true'}]}};fs.writeFileSync(f,JSON.stringify(d,null,2))"
node "$H23/hb.js" rebuild >/dev/null
ids23(){ node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>process.stdout.write(JSON.parse(d).map(t=>t.id).sort().join(',')))"; }
len23(){ node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>process.stdout.write(String(JSON.parse(d).length)))"; }
check "T23.1 ready → independent tasks (A,B), not C (requires A)" \
  'test "$(node "$H23/hb.js" ready | ids23)" = "A,B"'
check "T23.2 ready N respects the limit" \
  'test "$(node "$H23/hb.js" ready 1 | len23)" = "1"'
mkdir -p "$H23/leases/A"
check "T23.3 ready excludes leased tasks" \
  'test "$(node "$H23/hb.js" ready | ids23)" = "B"'
rm -rf "$H23/leases"; node "$H23/hb.js" start A >/dev/null; node "$H23/hb.js" done A >/dev/null
check "T23.4 dependency satisfied → task unblocked (B,C ready)" \
  'test "$(node "$H23/hb.js" ready | ids23)" = "B,C"'

grp "T24 — adversarial gate / second agent (v1.4, #3)"
hasP0(){ node "$1" state | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>process.exit(JSON.parse(d).completed_phases.includes('P0')?0:1))"; }
P24="$TMP/p24"; bash "$HB_SRC/plugin/bootstrap.sh" "$P24" >/dev/null 2>&1 </dev/null; H24="$P24/.hb"
node -e "const fs=require('fs');const f='$H24/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));d.phases=[{id:'P0',title:'P',gate_entry:null,gate_exit:'GATE_P0',tasks:[{id:'A',title:'a',requires:[]}]}];d.gates={GATE_P0:{desc:'g',review:{prompt:'Refute that P0 is done'},criteria:[{id:'g',desc:'ok',cmd:'true'}]}};fs.writeFileSync(f,JSON.stringify(d,null,2))"
node "$H24/hb.js" rebuild >/dev/null
reason24(){ rm -rf "$H24/.lock"; bash "$H24/tick.sh" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>process.stdout.write(JSON.parse(d).data.reason))"; }
node "$H24/hb.js" start A >/dev/null; node "$H24/hb.js" done A >/dev/null
check "T24.1 tasks done → gate_pending" 'test "$(reason24)" = "gate_pending"'
bash "$H24/gate.sh" GATE_P0 >/dev/null 2>&1
check "T24.2 deterministic gate passed but review due → phase NOT advanced" '! hasP0 "$H24/hb.js"'
check "T24.3 tick → review_pending" 'test "$(reason24)" = "review_pending"'
node "$H24/hb.js" review GATE_P0 fail hollow >/dev/null
check "T24.4 review fail → gate_blocked (re-gate)" 'test "$(reason24)" = "gate_blocked"'
bash "$H24/gate.sh" GATE_P0 >/dev/null 2>&1
printf 'Refutation attempt for GATE_P0 / phase P0: searched for hollow criteria and faked output, re-ran the gate. No hole found.\n' > "$P24/refute.md"
node "$H24/hb.js" review GATE_P0 pass --artifact "$P24/refute.md" >/dev/null
check "T24.5 review pass → phase advanced (P0 completed)" 'hasP0 "$H24/hb.js"'
P24b="$TMP/p24b"; bash "$HB_SRC/plugin/bootstrap.sh" "$P24b" >/dev/null 2>&1 </dev/null; H24b="$P24b/.hb"
node "$H24b/hb.js" start P0T1 >/dev/null; node "$H24b/hb.js" done P0T1 >/dev/null
node "$H24b/hb.js" start P0T2 >/dev/null; node "$H24b/hb.js" done P0T2 >/dev/null
bash "$H24b/gate.sh" GATE_P0 >/dev/null 2>&1
check "T24.6 back-compat: gate WITHOUT review → advances on deterministic pass alone" 'hasP0 "$H24b/hb.js"'

grp "T25 — DAG schema & per-task timing (v1.4, #5)"
SCHEMA="$HB_SRC/plugin/dag.schema.json"; TDAG="$HB_SRC/plugin/templates/dag.json"
check "T25.1 dag.schema.json valid + required gates/phases" \
  'node -e "const s=require(\"$SCHEMA\");process.exit(s.type===\"object\"&&s.required.includes(\"gates\")&&s.required.includes(\"phases\")?0:1)"'
check "T25.2 dag template conforms to schema (structure: tasks<=8, criteria id+cmd)" \
  'node -e "const d=require(\"$TDAG\");let ok=d.gates&&typeof d.gates===\"object\"&&Array.isArray(d.phases);for(const p of d.phases){if(!Array.isArray(p.tasks)||p.tasks.length>8)ok=false;}for(const g of Object.values(d.gates))for(const c of g.criteria){if(!c.id||!c.cmd)ok=false;}process.exit(ok?0:1)"'
P25="$TMP/p25"; bash "$HB_SRC/plugin/bootstrap.sh" "$P25" >/dev/null 2>&1 </dev/null; H25="$P25/.hb"
node "$H25/hb.js" start P0T1 >/dev/null; node "$H25/hb.js" done P0T1 >/dev/null
check "T25.3 --json report includes task_durations for P0T1" \
  'node "$HB_SRC/plugin/templates/hb-report.js" "$H25" --json | node -e "let d=\"\";process.stdin.on(\"data\",c=>d+=c).on(\"end\",()=>process.exit((JSON.parse(d).task_durations||[]).some(t=>t.task===\"P0T1\")?0:1))"'
check "T25.4 text report shows the task durations section" \
  'node "$HB_SRC/plugin/templates/hb-report.js" "$H25" | grep -qi "longest tasks"'

grp "T26 — git init at bootstrap & commit-on-gate-pass (v1.4)"
if command -v git >/dev/null 2>&1; then
  PG26="$TMP/p26"; HB_NO_GIT="" bash "$HB_SRC/plugin/bootstrap.sh" "$PG26" >/dev/null 2>&1 </dev/null
  check "T26.1 bootstrap → git repository initialized" '[ -d "$PG26/.git" ]'
  check "T26.2 .gitignore HeartBeat (runtime ignored)" 'grep -q "HeartBeat runtime" "$PG26/.gitignore"'
  check "T26.3 initial commit present" 'git -C "$PG26" rev-parse HEAD >/dev/null 2>&1'
  n26a=$(git -C "$PG26" rev-list --count HEAD)
  HB_NO_GIT="" bash "$PG26/.hb/gate.sh" GATE_P0 >/dev/null 2>&1
  check "T26.4 gate passed → gate tag (restore point)" 'git -C "$PG26" rev-parse GATE_P0 >/dev/null 2>&1'
  check "T26.5 gate passed → new commit" '[ "$(git -C "$PG26" rev-list --count HEAD)" -gt "$n26a" ]'
  check "T26.8 commit subject is descriptive (phase id + title + gate)" \
    '[ "$(git -C "$PG26" log -1 --format=%s)" = "heartbeat(P0): Foundation [GATE_P0]" ]'
  PG26b="$TMP/p26b"; bash "$HB_SRC/plugin/bootstrap.sh" "$PG26b" --no-git >/dev/null 2>&1 </dev/null
  check "T26.6 --no-git → no repository" '[ ! -d "$PG26b/.git" ]'
  PG26c="$TMP/p26c"; HB_NO_GIT="" bash "$HB_SRC/plugin/bootstrap.sh" "$PG26c" >/dev/null 2>&1 </dev/null
  n26c=$(git -C "$PG26c" rev-list --count HEAD)
  HB_NO_GIT=1 bash "$PG26c/.hb/gate.sh" GATE_P0 >/dev/null 2>&1
  check "T26.7 HB_NO_GIT=1 → gate.sh does not commit" '[ "$(git -C "$PG26c" rev-list --count HEAD)" = "$n26c" ]'
else
  echo "  (git absent — T26 skipped)"
fi

grp "T27 — hb doctor : rot detection (v1.5)"
P27="$TMP/p27"; bash "$HB_SRC/plugin/bootstrap.sh" "$P27" >/dev/null 2>&1 </dev/null; H27="$P27/.hb"
node -e "const fs=require('fs');const f='$H27/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));d.phases=[{id:'P0',title:'P',gate_entry:null,gate_exit:'GATE_P0',tasks:[{id:'A',title:'spec',description:'author tests/e2e/x.spec.js',requires:[]}]}];d.gates={GATE_P0:{desc:'g',criteria:[{id:'g1',desc:'spec',cmd:'node \"\$PROJECT_DIR/tests/e2e/x.spec.js\"'}]}};fs.writeFileSync(f,JSON.stringify(d,null,2))"
node "$H27/hb.js" rebuild >/dev/null
mkdir -p "$P27/tests/e2e"; echo "process.exit(0)" > "$P27/tests/e2e/x.spec.js"
check "T27.1 file present → doctor healthy (exit 0)" 'node "$H27/hb.js" doctor >/dev/null 2>&1'
node "$H27/hb.js" start A >/dev/null; node "$H27/hb.js" done A >/dev/null; bash "$H27/gate.sh" GATE_P0 >/dev/null 2>&1
rm -f "$P27/tests/e2e/x.spec.js"
check "T27.2 phase DONE + file removed → doctor reports rot (exit 1)" '! node "$H27/hb.js" doctor >/dev/null 2>&1'
check "T27.3 doctor names the missing file + 'reproducible'" \
  'o=$(node "$H27/hb.js" doctor 2>&1 || true); echo "$o" | grep -q "x.spec.js" && echo "$o" | grep -qi reproducible'

grp "T28 — gate.sh --check / --all read-only (v1.5)"
P28="$TMP/p28"; bash "$HB_SRC/plugin/bootstrap.sh" "$P28" >/dev/null 2>&1 </dev/null; H28="$P28/.hb"
E28=$(wc -l < "$H28/events.jsonl")
check "T28.1 --check GATE_P0 (passes) → exit 0" 'bash "$H28/gate.sh" --check GATE_P0 >/dev/null 2>&1'
check "T28.2 --check is READ-ONLY (no event added)" '[ "$(wc -l < "$H28/events.jsonl")" -eq "$E28" ]'
node -e "const fs=require('fs');const f='$H28/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));d.gates.GATE_X={desc:'x',criteria:[{id:'x',desc:'no',cmd:'false'}]};fs.writeFileSync(f,JSON.stringify(d,null,2))"
check "T28.3 --check failing gate → exit 1" '! bash "$H28/gate.sh" --check GATE_X >/dev/null 2>&1'
check "T28.4 --all re-evaluates all gates read-only (no event)" \
  'EB=$(wc -l < "$H28/events.jsonl"); bash "$H28/gate.sh" --all >/dev/null 2>&1; [ "$(wc -l < "$H28/events.jsonl")" -eq "$EB" ]'

grp "T29 — review no-progress → review_stuck (v1.6, thread 2)"
P29="$TMP/p29"; bash "$HB_SRC/plugin/bootstrap.sh" "$P29" >/dev/null 2>&1 </dev/null; H29="$P29/.hb"
node -e "const fs=require('fs');const f='$H29/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));d.phases=[{id:'P0',title:'P',gate_entry:null,gate_exit:'GATE_P0',tasks:[{id:'A',title:'a',requires:[]}]}];d.gates={GATE_P0:{desc:'g',review:{prompt:'r'},criteria:[{id:'g',desc:'ok',cmd:'true'}]}};fs.writeFileSync(f,JSON.stringify(d,null,2))"
node "$H29/hb.js" rebuild >/dev/null
node "$H29/hb.js" start A >/dev/null; node "$H29/hb.js" done A >/dev/null; bash "$H29/gate.sh" GATE_P0 >/dev/null 2>&1
rr29(){ rm -rf "$H29/.lock"; STUCK_TICKS=3 bash "$H29/tick.sh" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>process.stdout.write(JSON.parse(d).data.reason))"; }
rr29 >/dev/null; rr29 >/dev/null; rr29 >/dev/null
o29=$(rr29)
check "T29.1 review unresolved N times → review_stuck" 'test "$o29" = "review_stuck"'
check "T29.2 next tick → silence (review_waiting)" 'test "$(rr29)" = "review_waiting"'
printf 'Refutation attempt for GATE_P0 / phase P0: inspected the criteria and output, re-ran the gate. No hole found.\n' > "$P29/refute.md"
node "$H29/hb.js" review GATE_P0 pass --artifact "$P29/refute.md" >/dev/null
check "T29.3 hb review pass → phase advanced (P0)" \
  'node "$H29/hb.js" state | node -e "let d=\"\";process.stdin.on(\"data\",c=>d+=c).on(\"end\",()=>process.exit(JSON.parse(d).completed_phases.includes(\"P0\")?0:1))"'

grp "T30 — rot detection : wake at tick (v1.6, thread 1)"
P30="$TMP/p30"; bash "$HB_SRC/plugin/bootstrap.sh" "$P30" >/dev/null 2>&1 </dev/null; H30="$P30/.hb"
node -e "const fs=require('fs');const f='$H30/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));d.phases=[{id:'P0',title:'P',gate_entry:null,gate_exit:'GATE_P0',tasks:[{id:'A',title:'a',description:'tests/x.spec.js',requires:[]}]}];d.gates={GATE_P0:{desc:'g',criteria:[{id:'g',desc:'ok',cmd:'node \"\$PROJECT_DIR/tests/x.spec.js\"'}]}};fs.writeFileSync(f,JSON.stringify(d,null,2))"
node "$H30/hb.js" rebuild >/dev/null
mkdir -p "$P30/tests"; echo "process.exit(0)" > "$P30/tests/x.spec.js"
node "$H30/hb.js" start A >/dev/null; node "$H30/hb.js" done A >/dev/null; bash "$H30/gate.sh" GATE_P0 >/dev/null 2>&1
rm -f "$P30/tests/x.spec.js"
check "T30.1 file of a COMPLETED phase removed → tick wakes gate_rot" \
  'rm -rf "$H30/.lock"; HB_ROT_CHECK=1 bash "$H30/tick.sh" | node -e "let d=\"\";process.stdin.on(\"data\",c=>d+=c).on(\"end\",()=>process.exit(JSON.parse(d).data.reason===\"gate_rot\"?0:1))"'
check "T30.2 next tick → gate_rot_waiting (silence)" \
  'rm -rf "$H30/.lock"; HB_ROT_CHECK=1 bash "$H30/tick.sh" | node -e "let d=\"\";process.stdin.on(\"data\",c=>d+=c).on(\"end\",()=>{const j=JSON.parse(d);process.exit(j.data.reason===\"gate_rot_waiting\"&&j.wakeAgent===false?0:1)})"'
check "T30.3 HB_ROT_CHECK=0 → no gate_rot" \
  'rm -rf "$H30/.lock" "$H30/.rot-alerted"; HB_ROT_CHECK=0 bash "$H30/tick.sh" | node -e "let d=\"\";process.stdin.on(\"data\",c=>d+=c).on(\"end\",()=>process.exit(/gate_rot/.test(JSON.parse(d).data.reason)?1:0))"'

grp "T31 — pre-commit rot guard (v1.6, thread 1)"
if command -v git >/dev/null 2>&1; then
  P31="$TMP/p31"; HB_NO_GIT="" bash "$HB_SRC/plugin/bootstrap.sh" "$P31" >/dev/null 2>&1 </dev/null; H31="$P31/.hb"
  check "T31.1 pre-commit hook installed" '[ -x "$P31/.git/hooks/pre-commit" ]'
  node -e "const fs=require('fs');const f='$H31/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));d.phases=[{id:'P0',title:'P',gate_entry:null,gate_exit:'GATE_P0',tasks:[{id:'A',title:'a',requires:[]}]}];d.gates={GATE_P0:{desc:'g',criteria:[{id:'g',desc:'ok',cmd:'test -f \"\$PROJECT_DIR/keep.txt\"'}]}};fs.writeFileSync(f,JSON.stringify(d,null,2))"
  node "$H31/hb.js" rebuild >/dev/null; echo keep > "$P31/keep.txt"
  node "$H31/hb.js" start A >/dev/null; node "$H31/hb.js" done A >/dev/null; bash "$H31/gate.sh" GATE_P0 >/dev/null 2>&1
  rm -f "$P31/keep.txt"; echo x > "$P31/extra.txt"; git -C "$P31" add -A >/dev/null 2>&1
  check "T31.2 commit breaking a COMPLETED gate → blocked by the hook" \
    '! git -c user.email=t@t -c user.name=t -C "$P31" commit -m x >/dev/null 2>&1'
  check "T31.3 --no-verify bypasses the hook" \
    'git -c user.email=t@t -c user.name=t -C "$P31" commit --no-verify -m x >/dev/null 2>&1'
else
  echo "  (git absent — T31 skipped)"
fi

grp "T32 — protocol source of truth (v1.7, #1)"
P32="$TMP/p32"; bash "$HB_SRC/plugin/bootstrap.sh" "$P32" >/dev/null 2>&1 </dev/null; H32="$P32/.hb"
check "T32.1 hb protocol lists all reasons" 'test "$(node "$H32/hb.js" protocol | wc -l)" -ge 12'
check "T32.2 hb protocol <reason> returns that reason" 'node "$H32/hb.js" protocol review_pending | grep -q REFUTE'
check "T32.3 --oneline is a single bare line (no reason prefix)" \
  'test "$(node "$H32/hb.js" protocol gate_blocked --oneline | wc -l)" -eq 1 && ! node "$H32/hb.js" protocol gate_blocked --oneline | grep -q "^gate_blocked:"'
check "T32.4 --md renders a table" \
  'node "$H32/hb.js" protocol --md | grep -q "tick protocol" && node "$H32/hb.js" protocol --md | grep -q next_task'
check "T32.5 unknown reason → exit 1" '! node "$H32/hb.js" protocol nope >/dev/null 2>&1'

grp "T33 — self-describing ticks + PROTOCOL.md (v1.7, #1)"
P33="$TMP/p33"; bash "$HB_SRC/plugin/bootstrap.sh" "$P33" >/dev/null 2>&1 </dev/null; H33="$P33/.hb"
check "T33.1 next_task tick embeds data.action" \
  'rm -rf "$H33/.lock"; bash "$H33/tick.sh" | node -e "let d=\"\";process.stdin.on(\"data\",c=>d+=c).on(\"end\",()=>{const j=JSON.parse(d);process.exit(j.data.action&&/hb start/.test(j.data.action)?0:1)})"'
check "T33.2 bootstrap writes .hb/PROTOCOL.md with reasons" \
  '[ -f "$H33/PROTOCOL.md" ] && grep -q next_task "$H33/PROTOCOL.md" && grep -q review_pending "$H33/PROTOCOL.md"'
check "T33.3 hb.js is safely requirable (no CLI side effects)" \
  'node -e "const hb=require(\"$H33/hb.js\");process.exit(hb.PROTOCOL&&hb.PROTOCOL.next_task?0:1)"'
# review_pending tick self-describes with a REFUTE action
P33b="$TMP/p33b"; bash "$HB_SRC/plugin/bootstrap.sh" "$P33b" >/dev/null 2>&1 </dev/null; H33b="$P33b/.hb"
node -e "const fs=require('fs');const f='$H33b/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));d.phases=[{id:'P0',title:'P',gate_entry:null,gate_exit:'GATE_P0',tasks:[{id:'A',title:'a',requires:[]}]}];d.gates={GATE_P0:{desc:'g',review:{prompt:'r'},criteria:[{id:'g',desc:'ok',cmd:'true'}]}};fs.writeFileSync(f,JSON.stringify(d,null,2))"
node "$H33b/hb.js" rebuild >/dev/null; node "$H33b/hb.js" start A >/dev/null; node "$H33b/hb.js" done A >/dev/null; bash "$H33b/gate.sh" GATE_P0 >/dev/null 2>&1
check "T33.4 review_pending tick embeds a REFUTE action" \
  'rm -rf "$H33b/.lock"; bash "$H33b/tick.sh" | node -e "let d=\"\";process.stdin.on(\"data\",c=>d+=c).on(\"end\",()=>{const j=JSON.parse(d);process.exit(j.data.action&&/refute/i.test(j.data.action)?0:1)})"'
check "T33.5 every wake reason is covered by PROTOCOL (drift guard)" \
  'node -e "const {PROTOCOL}=require(\"$HB_SRC/plugin/templates/hb.js\");const need=[\"next_task\",\"gate_pending\",\"review_pending\",\"gate_blocked\",\"deadlock\",\"unsanctioned_drift\",\"gate_rot\",\"build_stuck\",\"review_stuck\",\"all_done\",\"state_corrupted\",\"dag_corrupted\"];process.exit(need.every(r=>PROTOCOL[r])?0:1)"'

grp "T34 — hb diagnose : computed root-cause (v1.7, #2)"
P34="$TMP/p34"; bash "$HB_SRC/plugin/bootstrap.sh" "$P34" >/dev/null 2>&1 </dev/null; H34="$P34/.hb"
node -e "const fs=require('fs');const f='$H34/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));d.gates.GATE_P0.criteria=[{id:'G0_1',desc:'must exist',cmd:'test -f \"\$PROJECT_DIR/nope.txt\"'}];fs.writeFileSync(f,JSON.stringify(d,null,2))"
node "$H34/hb.js" rebuild >/dev/null; bash "$H34/gate.sh" GATE_P0 >/dev/null 2>&1
check "T34.1 diagnose gate_blocked names the failing criterion" 'node "$H34/hb.js" diagnose gate_blocked | grep -q G0_1'
check "T34.2 diagnose is READ-ONLY (no new events)" \
  'E=$(wc -l < "$H34/events.jsonl"); node "$H34/hb.js" diagnose gate_blocked >/dev/null 2>&1; [ "$(wc -l < "$H34/events.jsonl")" -eq "$E" ]'
P34b="$TMP/p34b"; bash "$HB_SRC/plugin/bootstrap.sh" "$P34b" >/dev/null 2>&1 </dev/null; H34b="$P34b/.hb"
node -e "const fs=require('fs');const f='$H34b/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));d.phases[0].tasks[1].requires=['GHOST'];fs.writeFileSync(f,JSON.stringify(d,null,2))"
node "$H34b/hb.js" rebuild >/dev/null; node "$H34b/hb.js" start P0T1 >/dev/null; node "$H34b/hb.js" done P0T1 >/dev/null
check "T34.3 diagnose deadlock → cause dag_invalid" 'node "$H34b/hb.js" diagnose deadlock | grep -q dag_invalid'
check "T34.4 diagnose (no arg) infers the blocker" 'node "$H34b/hb.js" diagnose | grep -q deadlock'
if command -v git >/dev/null 2>&1; then
  P34c="$TMP/p34c"; HB_NO_GIT="" bash "$HB_SRC/plugin/bootstrap.sh" "$P34c" >/dev/null 2>&1 </dev/null; H34c="$P34c/.hb"
  node -e "const fs=require('fs');const f='$H34c/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));d.phases=[{id:'P0',title:'P',gate_entry:null,gate_exit:'GATE_P0',tasks:[{id:'A',title:'a',requires:[]}]}];d.gates={GATE_P0:{desc:'g',criteria:[{id:'g1',desc:'spec',cmd:'node \"\$PROJECT_DIR/spec.js\"'}]}};fs.writeFileSync(f,JSON.stringify(d,null,2))"
  node "$H34c/hb.js" rebuild >/dev/null; echo "process.exit(0)" > "$P34c/spec.js"
  git -C "$P34c" add spec.js; git -c user.email=t@t -c user.name=t -C "$P34c" commit -q --no-verify -m "add spec" >/dev/null 2>&1
  node "$H34c/hb.js" start A >/dev/null; node "$H34c/hb.js" done A >/dev/null; bash "$H34c/gate.sh" GATE_P0 >/dev/null 2>&1
  git -C "$P34c" rm -q spec.js; git -c user.email=t@t -c user.name=t -C "$P34c" commit -q --no-verify -m "remove spec" >/dev/null 2>&1
  check "T34.5 diagnose gate_rot traces the deleting commit (git backward-trace)" \
    'node "$H34c/hb.js" diagnose gate_rot | grep -qi "deleted in"'
else
  echo "  (git absent — T34.5 skipped)"
fi

grp "T35 — SessionStart hook (v1.7, #1)"
check "T35.1 hooks.json valid + registers SessionStart" \
  'node -e "const h=require(\"$HB_SRC/plugin/hooks/hooks.json\");process.exit(h.hooks&&h.hooks.SessionStart?0:1)"'
P35="$TMP/p35"; bash "$HB_SRC/plugin/bootstrap.sh" "$P35" >/dev/null 2>&1 </dev/null
check "T35.2 hook fires (prints pointer) on a .hb/ project" \
  'CLAUDE_PROJECT_DIR="$P35" bash "$HB_SRC/plugin/hooks/heartbeat-detect.sh" | grep -qi "HeartBeat"'
check "T35.3 hook is silent on a non-HeartBeat dir" \
  '[ -z "$(CLAUDE_PROJECT_DIR="$TMP" bash "$HB_SRC/plugin/hooks/heartbeat-detect.sh")" ]'

grp "T36 — hb-exec driver: pluggable Stage B (v1.8)"
EXEC_SRC="$HB_SRC/plugin/templates/hb-exec.js"
check "T36.1 hb-exec.js is requirable and exports run()" \
  'node -e "const m=require(\"'"$EXEC_SRC"'\");process.exit(typeof m.run===\"function\"?0:1)"'
# A python-free stub backend: execute writes the task id to done.log (cwd=PROJECT_DIR);
# refute returns a configurable verdict. STUB_FAIL forces an execute failure.
STUB="$TMP/stub.sh"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
mode="$1"; payload="$(cat)"
case "$mode" in
  execute)
    [ "${STUB_FAIL:-0}" = 1 ] && { echo '{"ok":false,"summary":"forced fail"}'; exit 0; }
    id=$(printf '%s' "$payload" | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).task.id' 2>/dev/null)
    if [ "${STUB_DISTINCT:-0}" = 1 ]; then printf 'done\n' > "$id.out"; else printf '%s\n' "$id" >> done.log; fi
    printf '{"ok":true,"summary":"did %s"}\n' "$id" ;;
  refute) printf '{"refuted":%s,"findings":"Attempted to refute: inspected done.log for the task output, checked the gate criteria for hollowness, re-ran the behavioral check. No hole found."}\n' "${STUB_REFUTE:-false}" ;;
esac
STUBEOF
# set_dag <hbdir> <js> — overwrite dag.json (strip skeleton) and reproject.
set_dag(){ node -e "const fs=require('fs');const f='$1/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));delete d._meta;$2;fs.writeFileSync(f,JSON.stringify(d,null,2))"; node "$1/hb.js" rebuild >/dev/null 2>&1; }

# — happy path: two phases, behavioral gates, driven to all_done —
P36="$TMP/p36"; bash "$HB_SRC/plugin/bootstrap.sh" "$P36" >/dev/null 2>&1 </dev/null; H36="$P36/.hb"
set_dag "$H36" "d.phases=[{id:'X0',title:'p0',gate_entry:null,gate_exit:'GX0',tasks:[{id:'X0T1',title:'write X0T1 to done.log',requires:[]}]},{id:'X1',title:'p1',gate_entry:'GX0',gate_exit:'GX1',tasks:[{id:'X1T1',title:'write X1T1 to done.log',requires:[]}]}];d.gates={GX0:{desc:'p0',criteria:[{id:'c',desc:'X0T1 recorded',cmd:'grep -q X0T1 \"\$PROJECT_DIR/done.log\"'}]},GX1:{desc:'p1',criteria:[{id:'c',desc:'X1T1 recorded',cmd:'grep -q X1T1 \"\$PROJECT_DIR/done.log\"'}]}}"
out36=$(HB_EXEC_CMD="bash $STUB" HB_EXEC_MAX_ITERS=25 node "$H36/hb-exec.js" run 2>&1)
check "T36.2 driver runs the stub backend to completion (all_done)" 'echo "$out36" | grep -q "HB-EXEC DONE"'
check "T36.3 both phases advanced through their gates" \
  'node -e "const s=require(\"'"$H36"'/state.json\");process.exit(s.completed_phases.includes(\"X0\")&&s.completed_phases.includes(\"X1\")?0:1)"'
check "T36.4 backend actually did the work (both task ids in done.log)" \
  'grep -q X0T1 "$P36/done.log" && grep -q X1T1 "$P36/done.log"'

# — per-task attempt cap → escalate (never loops forever) —
P36c="$TMP/p36c"; bash "$HB_SRC/plugin/bootstrap.sh" "$P36c" >/dev/null 2>&1 </dev/null; H36c="$P36c/.hb"
set_dag "$H36c" "d.phases=[{id:'Y0',title:'p',gate_entry:null,gate_exit:'GY0',tasks:[{id:'Y0T1',title:'write Y0T1 to done.log',requires:[]}]}];d.gates={GY0:{desc:'p',criteria:[{id:'c',desc:'done',cmd:'grep -q Y0T1 \"\$PROJECT_DIR/done.log\"'}]}}"
out36c=$(STUB_FAIL=1 HB_EXEC_CMD="bash $STUB" HB_EXEC_ATTEMPT_CAP=3 HB_EXEC_MAX_ITERS=20 node "$H36c/hb-exec.js" run 2>&1)
check "T36.5 repeated backend failure hits the attempt cap and escalates" 'echo "$out36c" | grep -q "STOP: attempts_exhausted"'

# — strict mode refuses a non-behavioral gate —
P36s="$TMP/p36s"; bash "$HB_SRC/plugin/bootstrap.sh" "$P36s" >/dev/null 2>&1 </dev/null; H36s="$P36s/.hb"
set_dag "$H36s" "d.phases=[{id:'Z0',title:'p',gate_entry:null,gate_exit:'GZ0',tasks:[{id:'Z0T1',title:'do',requires:[]}]}];d.gates={GZ0:{desc:'p',criteria:[{id:'c',desc:'exists',cmd:'test -f \"\$PROJECT_DIR/whatever\"'}]}}"
node "$H36s/hb.js" start Z0T1 >/dev/null; node "$H36s/hb.js" done Z0T1 >/dev/null   # tasks done → gate_pending
out36s=$(HB_EXEC_STRICT=1 HB_EXEC_CMD="bash $STUB" HB_EXEC_MAX_ITERS=5 node "$H36s/hb-exec.js" run 2>&1)
check "T36.6 strict mode escalates on a non-behavioral (test -f) gate" 'echo "$out36s" | grep -q "STOP: strict_gate"'

# — adversarial review: refuter can't refute → phase advances —
P36r="$TMP/p36r"; bash "$HB_SRC/plugin/bootstrap.sh" "$P36r" >/dev/null 2>&1 </dev/null; H36r="$P36r/.hb"
set_dag "$H36r" "d.phases=[{id:'R0',title:'p',gate_entry:null,gate_exit:'GR0',tasks:[{id:'R0T1',title:'write R0T1 to done.log',requires:[]}]}];d.gates={GR0:{desc:'p',review:{prompt:'Refute R0.'},criteria:[{id:'c',desc:'done',cmd:'grep -q R0T1 \"\$PROJECT_DIR/done.log\"'}]}}"
out36r=$(STUB_REFUTE=false HB_EXEC_CMD="bash $STUB" HB_EXEC_MAX_ITERS=25 node "$H36r/hb-exec.js" run 2>&1)
check "T36.7 review_pending → refuter fails to refute → phase completes" \
  'echo "$out36r" | grep -q "HB-EXEC DONE" && node -e "const s=require(\"'"$H36r"'/state.json\");process.exit(s.completed_phases.includes(\"R0\")?0:1)"'

# — adversarial review: refuter DOES refute → routes to gate_blocked → escalate —
P36f="$TMP/p36f"; bash "$HB_SRC/plugin/bootstrap.sh" "$P36f" >/dev/null 2>&1 </dev/null; H36f="$P36f/.hb"
set_dag "$H36f" "d.phases=[{id:'F0',title:'p',gate_entry:null,gate_exit:'GF0',tasks:[{id:'F0T1',title:'write F0T1 to done.log',requires:[]}]}];d.gates={GF0:{desc:'p',review:{prompt:'Refute F0.'},criteria:[{id:'c',desc:'done',cmd:'grep -q F0T1 \"\$PROJECT_DIR/done.log\"'}]}}"
out36f=$(STUB_REFUTE=true HB_EXEC_CMD="bash $STUB" HB_EXEC_MAX_ITERS=25 node "$H36f/hb-exec.js" run 2>&1)
check "T36.8 refuter finds a hole → review fail → escalates gate_blocked" 'echo "$out36f" | grep -q "STOP: gate_blocked"'

grp "T37 — Agno backend adapter (v1.8)"
AGNO="$HB_SRC/plugin/templates/executors/agno_exec.py"
if command -v python3 >/dev/null 2>&1; then
  check "T37.1 agno_exec.py is valid python" 'python3 -c "import ast; ast.parse(open(\"'"$AGNO"'\").read())"'
  if python3 -c "import agno" 2>/dev/null; then
    echo "  (agno installed — degrade-path assertions skipped)"
  else
    check "T37.2 execute degrades to protocol-valid JSON (ok:false) without agno" \
      'printf "{}" | python3 "'"$AGNO"'" execute | grep -q "\"ok\": false"'
    check "T37.3 refute degrades to protocol-valid JSON (refuted:false) without agno" \
      'printf "{}" | python3 "'"$AGNO"'" refute | grep -q "\"refuted\": false"'
  fi
else
  echo "  (python3 absent — T37 skipped)"
fi

grp "T38 — CrewAI backend adapter (v1.8)"
CREW="$HB_SRC/plugin/templates/executors/crewai_exec.py"
if command -v python3 >/dev/null 2>&1; then
  check "T38.1 crewai_exec.py is valid python" 'python3 -c "import ast; ast.parse(open(\"'"$CREW"'\").read())"'
  if python3 -c "import crewai" 2>/dev/null; then
    echo "  (crewai installed — degrade-path assertions skipped)"
  else
    check "T38.2 execute degrades to protocol-valid JSON (ok:false) without crewai" \
      'printf "{}" | python3 "'"$CREW"'" execute | grep -q "\"ok\": false"'
    check "T38.3 refute degrades to protocol-valid JSON (refuted:false) without crewai" \
      'printf "{}" | python3 "'"$CREW"'" refute | grep -q "\"refuted\": false"'
  fi
else
  echo "  (python3 absent — T38 skipped)"
fi

grp "T39 — packaging: bootstrap ships the executor (v1.8)"
P39="$TMP/p39"; bash "$HB_SRC/plugin/bootstrap.sh" "$P39" >/dev/null 2>&1 </dev/null
check "T39.1 bootstrap copies hb-exec.js into .hb/" '[ -f "$P39/.hb/hb-exec.js" ]'
check "T39.2 bootstrap copies the backend adapters into .hb/executors/" \
  '[ -f "$P39/.hb/executors/agno_exec.py" ] && [ -f "$P39/.hb/executors/crewai_exec.py" ] && [ -f "$P39/.hb/executors/claude-exec.sh" ] && [ -f "$P39/.hb/executors/langgraph_exec.py" ] && [ -f "$P39/.hb/executors/openai_agents_exec.py" ] && [ -f "$P39/.hb/executors/autogen_exec.py" ] && [ -f "$P39/.hb/executors/smolagents_exec.py" ] && [ -f "$P39/.hb/executors/pydanticai_exec.py" ]'
check "T39.3 SKILL help documents the exec command" \
  'grep -q "heartbeat exec" "$HB_SRC/plugin/skills/heartbeat/SKILL.md"'
check "T39.4 plugin version is consistent with the marketplace entry" \
  'test "$(grep -oE "\"version\": \"[0-9.]+\"" "$HB_SRC/plugin/.claude-plugin/plugin.json" | head -1)" = "$(grep -oE "\"version\": \"[0-9.]+\"" "$HB_SRC/.claude-plugin/marketplace.json" | head -1)"'

grp "T40 — parallel fan-out (v1.8)"
# In-place parallel: one phase, three independent tasks, driven concurrently by the stub.
P40="$TMP/p40"; bash "$HB_SRC/plugin/bootstrap.sh" "$P40" >/dev/null 2>&1 </dev/null; H40="$P40/.hb"
set_dag "$H40" "d.phases=[{id:'PA',title:'fan',gate_entry:null,gate_exit:'GPA',tasks:[{id:'PA1',title:'write PA1 to done.log',requires:[]},{id:'PA2',title:'write PA2 to done.log',requires:[]},{id:'PA3',title:'write PA3 to done.log',requires:[]}]}];d.gates={GPA:{desc:'all three',criteria:[{id:'c',desc:'all recorded',cmd:'grep -q PA1 \"\$PROJECT_DIR/done.log\" && grep -q PA2 \"\$PROJECT_DIR/done.log\" && grep -q PA3 \"\$PROJECT_DIR/done.log\"'}]}}"
out40=$(HB_MAX_CONCURRENCY=3 HB_EXEC_CMD="bash $STUB" HB_EXEC_MAX_ITERS=15 node "$H40/hb-exec.js" run 2>&1)
check "T40.1 parallel run fans out and drives the phase to all_done" \
  'echo "$out40" | grep -q "fan-out 3" && echo "$out40" | grep -q "HB-EXEC DONE"'
check "T40.2 all three concurrent tasks did their work" \
  'grep -q PA1 "$P40/done.log" && grep -q PA2 "$P40/done.log" && grep -q PA3 "$P40/done.log"'
# Worktree isolation: git enabled, two tasks writing DISTINCT files → clean merge into main.
if command -v git >/dev/null 2>&1; then
  P40w="$TMP/p40w"; HB_NO_GIT="" bash "$HB_SRC/plugin/bootstrap.sh" "$P40w" >/dev/null 2>&1 </dev/null; H40w="$P40w/.hb"
  set_dag "$H40w" "d.phases=[{id:'WP',title:'iso',gate_entry:null,gate_exit:'GWP',tasks:[{id:'WA',title:'produce WA.out',requires:[]},{id:'WB',title:'produce WB.out',requires:[]}]}];d.gates={GWP:{desc:'both merged',criteria:[{id:'c',desc:'both files',cmd:'test -f \"\$PROJECT_DIR/WA.out\" && test -f \"\$PROJECT_DIR/WB.out\"'}]}}"
  out40w=$(HB_NO_GIT="" STUB_DISTINCT=1 HB_MAX_CONCURRENCY=2 HB_EXEC_CMD="bash $STUB" HB_EXEC_MAX_ITERS=15 node "$H40w/hb-exec.js" run 2>&1)
  check "T40.3 worktree-isolated fan-out merges both tasks' files into the main tree" \
    'echo "$out40w" | grep -q "worktree-isolated" && [ -f "$P40w/WA.out" ] && [ -f "$P40w/WB.out" ]'
  check "T40.4 worktrees and temp branches are cleaned up afterward" \
    '[ -z "$(ls -A "$H40w/wt" 2>/dev/null)" ] && [ -z "$(git -C "$P40w" branch --list "hb-exec/*")" ]'
else
  echo "  (git absent — T40.3/T40.4 skipped)"
fi

grp "T41 — Ollama backend adapter (v1.8)"
OLL="$HB_SRC/plugin/templates/executors/ollama_exec.py"
if command -v python3 >/dev/null 2>&1; then
  check "T41.1 ollama_exec.py is valid python" 'python3 -c "import ast; ast.parse(open(\"'"$OLL"'\").read())"'
  # Point at a dead port so the degrade path is deterministic (no model needed).
  check "T41.2 execute degrades to protocol-valid JSON when the server is unreachable" \
    'OLLAMA_HOST=http://127.0.0.1:9 bash -c "printf {} | python3 \"'"$OLL"'\" execute" | grep -q "\"ok\": false"'
  check "T41.3 refute degrades to protocol-valid JSON when the server is unreachable" \
    'OLLAMA_HOST=http://127.0.0.1:9 bash -c "printf {} | python3 \"'"$OLL"'\" refute" | grep -q "\"refuted\": false"'
else
  echo "  (python3 absent — T41 skipped)"
fi

grp "T42 — DAG auditor: gate-quality (adversarial plan review)"
AUD="$HB_SRC/plugin/templates/hb-audit.js"
FIX="$HB_SRC/tests/fixtures/audit"
check "T42.1 hb-audit.js is requirable and exports audit()" \
  'node -e "const m=require(\"'"$AUD"'\");process.exit(typeof m.audit===\"function\"?0:1)"'
check "T42.2 flags a hollow (always-true) gate → error, exit 1" \
  'out=$(node "$AUD" "$FIX/hollow.json"); rc=$?; [ "$rc" -eq 1 ] && printf "%s" "$out" | grep -q hollow_gate'
check "T42.3 flags an existence-only gate as hollow (test -f)" \
  'out=$(node "$AUD" "$FIX/existence.json"); printf "%s" "$out" | grep -q existence && printf "%s" "$out" | grep -q hollow_gate'
check "T42.4 behavioral-but-flaky gate → nondeterministic warning, no error (exit 0)" \
  'node "$AUD" "$FIX/nondeterministic.json" | grep -q nondeterministic && node "$AUD" "$FIX/nondeterministic.json" >/dev/null 2>&1'
check "T42.5 a good (behavioral) DAG passes clean, no errors" \
  'node "$AUD" "$FIX/good.json" >/dev/null 2>&1 && [ "$(node "$AUD" "$FIX/good.json" --json | node -pe "JSON.parse(require(\"fs\").readFileSync(0)).errors")" = "0" ]'
check "T42.6 a phase with a behavioral criterion is NOT hollow even with a sibling test -f" \
  'node -e "const {audit}=require(\"'"$AUD"'\");const d={phases:[{id:\"P\",gate_exit:\"G\",tasks:[{id:\"t\",title:\"x\"}]}],gates:{G:{criteria:[{id:\"a\",cmd:\"grep -q ok f\"},{id:\"b\",cmd:\"test -f f\"}]}}};process.exit(audit(d).errors===0?0:1)"'

grp "T43 — node ↔ python parity (lint / audit / state projection)"
if command -v python3 >/dev/null 2>&1; then
  check "T43.1 node ≡ python on all parity fixtures" 'bash "$HB_SRC/tests/parity.sh" >/dev/null 2>&1'
  check "T43.2 parity covers audit, lint, and the state projection" \
    'out=$(bash "$HB_SRC/tests/parity.sh"); echo "$out" | grep -q "audit parity" && echo "$out" | grep -q "lint parity" && echo "$out" | grep -q "state projection parity"'
else
  echo "  (python3 absent — T43 skipped)"
fi

grp "T44 — /heartbeat plan acceptance folds in the auditor (v1.11)"
SK="$HB_SRC/plugin/skills/heartbeat/SKILL.md"
check "T44.1 plan acceptance runs hb-audit (gate quality)" \
  'awk "/heartbeat plan/{f=1} f&&/hb-audit/{found=1} END{exit !found}" "$SK"'
check "T44.2 plan acceptance requires refuting the plan (SOUND) before proposing" \
  'grep -q "refute the plan" "$SK" && grep -q "SOUND" "$SK"'

grp "T45 — review-evidence hardening (holes stay closed)"
P45="$TMP/p45"; bash "$HB_SRC/plugin/bootstrap.sh" "$P45" >/dev/null 2>&1 </dev/null; H45="$P45/.hb"
# a criteria-less gate must FAIL at the runtime, not just in audit
set_dag "$H45" "d.gates.GEMPTY={desc:'empty',criteria:[]};d.phases.push({id:'PE',title:'e',gate_entry:'GATE_P1',gate_exit:'GEMPTY',tasks:[{id:'PET1',title:'t',requires:[]}]})"
check "T45.1 gate.sh FAILS a zero-criteria gate (hollow floor)" '! bash "$H45/gate.sh" GEMPTY >/dev/null 2>&1'
check "T45.2 gate.sh --check also refuses it" '! bash "$H45/gate.sh" --check GEMPTY >/dev/null 2>&1'
# review pass without an artifact is rejected
P45b="$TMP/p45b"; bash "$HB_SRC/plugin/bootstrap.sh" "$P45b" >/dev/null 2>&1 </dev/null; H45b="$P45b/.hb"
set_dag "$H45b" "d.phases=[{id:'A0',title:'p',gate_entry:null,gate_exit:'GA0',tasks:[{id:'A0T1',title:'write A0T1 to done.log',requires:[]}]}];d.gates={GA0:{desc:'p',review:{prompt:'Refute A0.'},criteria:[{id:'c',desc:'done',cmd:'grep -q A0T1 \"\$PROJECT_DIR/done.log\"'}]}}"
printf 'A0T1\n' > "$P45b/done.log"
node "$H45b/hb.js" start A0T1 >/dev/null; node "$H45b/hb.js" done A0T1 >/dev/null; bash "$H45b/gate.sh" GA0 >/dev/null 2>&1
check "T45.3 review pass WITHOUT --artifact is rejected" '! node "$H45b/hb.js" review GA0 pass >/dev/null 2>&1'
check "T45.4 phase did NOT advance on the rejected self-pass" \
  'node -e "const s=require(\"'"$H45b"'/state.json\");process.exit(s.completed_phases.includes(\"A0\")?1:0)"'
printf 'ok\n' > "$P45b/thin.md"
check "T45.5 review pass with a THIN artifact is rejected (no rubber-stamp)" \
  '! node "$H45b/hb.js" review GA0 pass --artifact "$P45b/thin.md" >/dev/null 2>&1'
printf 'Refutation attempt for GA0: searched for hollow criteria and faked output, re-ran the behavioral gate, inspected done.log. No hole found.\n' > "$P45b/real.md"
node "$H45b/hb.js" review GA0 pass --artifact "$P45b/real.md" >/dev/null 2>&1
check "T45.6 review pass WITH a substantive artifact advances the phase" \
  'node -e "const s=require(\"'"$H45b"'/state.json\");process.exit(s.completed_phases.includes(\"A0\")?0:1)"'
check "T45.7 the backing artifact is stored under .hb/reviews/" '[ -f "$H45b/reviews/GA0.md" ]'
rm -f "$H45b/reviews/GA0.md" 2>/dev/null
check "T45.8 doctor flags a review_passed whose artifact vanished (Sev-1 rot)" \
  'd458=$(node "$H45b/hb.js" doctor 2>&1); echo "$d458" | grep -qi "artifact"'
# a self-fabricating criterion is flagged by the auditor
P45c="$TMP/p45c"; bash "$HB_SRC/plugin/bootstrap.sh" "$P45c" >/dev/null 2>&1 </dev/null; H45c="$P45c/.hb"
set_dag "$H45c" "d.phases=[{id:'S0',title:'p',gate_entry:null,gate_exit:'GS0',tasks:[{id:'S0T1',title:'produce result',requires:[]}]}];d.gates={GS0:{desc:'p',criteria:[{id:'c',desc:'self-made',cmd:'echo ok > \"\$PROJECT_DIR/out.json\"; test -f \"\$PROJECT_DIR/out.json\"'}]}}"
check "T45.9 auditor flags a self-fabricating (side-effecting) criterion" \
  'node "$HB_SRC/plugin/templates/hb-audit.js" "$H45c/dag.json" 2>&1 | grep -qi "side_effect\|OBSERVE"'
set_dag "$H45c" "d.gates.GS0.criteria=[{id:'c',desc:'coin',cmd:'[ \$((RANDOM % 2)) -eq 0 ]'}]"
check "T45.10 auditor flags arithmetic-context RANDOM as nondeterministic" \
  'node "$HB_SRC/plugin/templates/hb-audit.js" "$H45c/dag.json" 2>&1 | grep -qi "nondetermin"'

grp "T46 — review substance & identity (self-review)"
P46="$TMP/p46"; bash "$HB_SRC/plugin/bootstrap.sh" "$P46" >/dev/null 2>&1 </dev/null; H46="$P46/.hb"
set_dag "$H46" "d.phases=[{id:'A0',title:'p',gate_entry:null,gate_exit:'GA0',tasks:[{id:'A0T1',title:'write A0T1 to done.log',requires:[]}]}];d.gates={GA0:{desc:'p',review:{prompt:'Refute A0.'},criteria:[{id:'c',desc:'done',cmd:'grep -q A0T1 \"\$PROJECT_DIR/done.log\"'}]}}"
printf 'A0T1\n' > "$P46/done.log"
HB_ACTOR=agent-A node "$H46/hb.js" start A0T1 >/dev/null; HB_ACTOR=agent-A node "$H46/hb.js" done A0T1 >/dev/null; bash "$H46/gate.sh" GA0 >/dev/null 2>&1
printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' > "$P46/pad.md"
check "T46.1 padded artifact citing nothing real is rejected" \
  'o=$(HB_ACTOR=agent-B node "$H46/hb.js" review GA0 pass --artifact "$P46/pad.md" 2>&1); echo "$o" | grep -qi "cites nothing\|does not reference"'
printf 'Refutation for GA0: inspected A0T1 in done.log, re-ran the gate, no hole.\n' > "$P46/real.md"
check "T46.2 self-review (same actor did the work) is rejected" \
  'o=$(HB_ACTOR=agent-A node "$H46/hb.js" review GA0 pass --artifact "$P46/real.md" 2>&1); echo "$o" | grep -qi "self-review"'
check "T46.3 self-review did NOT advance the phase" \
  'node -e "const s=require(\"'"$H46"'/state.json\");process.exit(s.completed_phases.includes(\"A0\")?1:0)"'
check "T46.4 distinct reviewer with anchored findings advances the phase" \
  'HB_ACTOR=agent-B node "$H46/hb.js" review GA0 pass --artifact "$P46/real.md" >/dev/null 2>&1; node -e "const s=require(\"'"$H46"'/state.json\");process.exit(s.completed_phases.includes(\"A0\")?0:1)"'
check "T46.5 the review event records reviewer identity + citations" \
  'grep review "$H46/events.jsonl" | grep -q "\"reviewer\":\"agent-B\"" && grep review "$H46/events.jsonl" | grep -q "\"cited\""'

grp "T47 — LangGraph backend adapter"
LG="$HB_SRC/plugin/templates/executors/langgraph_exec.py"
if command -v python3 >/dev/null 2>&1; then
  check "T47.1 langgraph_exec.py is valid python" 'python3 -c "import ast; ast.parse(open(\"'"$LG"'\").read())"'
  if python3 -c "import langgraph" 2>/dev/null; then
    echo "  (langgraph installed — degrade-path assertions skipped)"
  else
    check "T47.2 execute degrades to protocol-valid JSON without langgraph" \
      'printf "{}" | python3 "'"$LG"'" execute | grep -q "\"ok\": false"'
    check "T47.3 refute degrades to protocol-valid JSON without langgraph" \
      'printf "{}" | python3 "'"$LG"'" refute | grep -q "\"refuted\": false"'
  fi
else
  echo "  (python3 absent — T47 skipped)"
fi

grp "T48 — OpenAI Agents SDK backend adapter"
OA="$HB_SRC/plugin/templates/executors/openai_agents_exec.py"
if command -v python3 >/dev/null 2>&1; then
  check "T48.1 openai_agents_exec.py is valid python" 'python3 -c "import ast; ast.parse(open(\"'"$OA"'\").read())"'
  if python3 -c "import agents" 2>/dev/null; then
    echo "  (openai-agents installed — degrade-path assertions skipped)"
  else
    check "T48.2 execute degrades to protocol-valid JSON without openai-agents" \
      'printf "{}" | python3 "'"$OA"'" execute | grep -q "\"ok\": false"'
    check "T48.3 refute degrades to protocol-valid JSON without openai-agents" \
      'printf "{}" | python3 "'"$OA"'" refute | grep -q "\"refuted\": false"'
  fi
else
  echo "  (python3 absent — T48 skipped)"
fi

for spec in "T49:autogen:autogen_exec.py:autogen_agentchat" "T50:smolagents:smolagents_exec.py:smolagents" "T51:pydantic-ai:pydanticai_exec.py:pydantic_ai"; do
  TN="${spec%%:*}"; rest="${spec#*:}"; NAME="${rest%%:*}"; rest="${rest#*:}"; SCRIPT="${rest%%:*}"; IMP="${rest#*:}"
  P="$HB_SRC/plugin/templates/executors/$SCRIPT"
  grp "$TN — ${NAME} backend adapter"
  if command -v python3 >/dev/null 2>&1; then
    check "$TN.1 $SCRIPT is valid python" 'python3 -c "import ast; ast.parse(open(\"'"$P"'\").read())"'
    if python3 -c "import $IMP" 2>/dev/null; then
      echo "  ($NAME installed — degrade-path assertions skipped)"
    else
      check "$TN.2 execute degrades to protocol-valid JSON without $NAME" \
        'printf "{}" | python3 "'"$P"'" execute | grep -q "\"ok\": false"'
      check "$TN.3 refute degrades to protocol-valid JSON without $NAME" \
        'printf "{}" | python3 "'"$P"'" refute | grep -q "\"refuted\": false"'
    fi
  else
    echo "  (python3 absent — $TN skipped)"
  fi
done

grp "T52 — outcome-asserting coverage marker"
# A coverage gate should assert a group PASSED, not that its header exists. The marker
# lists only groups with zero failing checks, so `grep 'GROUPS-PASSED:.* T3 '` fails on a
# red T3 (unlike `grep T3`, which matches the header on a red suite too).
check "T52.1 real groups are tracked (T1 in the group set)" \
  'printf "%s" "$_ALLG" | tr " " "\n" | grep -qx T1'
check "T52.2 the passed-set computation EXCLUDES a failed group, keeps a passed one" \
  'declare -A gf; gf[TX]=1; all="TX TY"; gp=""; for g in $all; do [ -z "${gf[$g]:-}" ] && gp="$gp $g"; done; echo "$gp" | grep -qw TY && ! echo "$gp" | grep -qw TX'

grp "T53 — behavioral-gate HowTo proofs (docs/howto)"
GEX="$HB_SRC/docs/howto/gate-examples"
if command -v python3 >/dev/null 2>&1; then
  check "T53.1 every weakness example is proven (ALL-EXAMPLES-PROVEN)" \
    'bash "'"$GEX"'/run.sh" 2>&1 | grep -q "ALL-EXAMPLES-PROVEN:"'
  check "T53.2 the runner rejects an injected hollow example (--selftest)" \
    'bash "'"$GEX"'/run.sh" --selftest 2>&1 | grep -q "SELFTEST-CAUGHT:"'
  check "T53.3 the discovery harness runs deterministically (--dry)" \
    'bash "'"$GEX"'/discover.sh" --dry 2>&1 | grep -q "DISCOVERY:"'
else
  echo "  (python3 absent — T53 skipped)"
fi

grp "T54 — behavioral-gate HowTo mechanism demos (docs/howto)"
if command -v python3 >/dev/null 2>&1; then
  check "T54.1 the refutation guard demo drives the real hb CLI end-to-end" \
    'bash "'"$GEX"'/refutation-demo.sh" 2>&1 | grep -q "REFUTATION-GUARDS-OK"'
  check "T54.2 the example corpus is deterministic across runs and within budget" \
    'bash "'"$GEX"'/fast-determinism-check.sh" 2>&1 | grep -q "FAST-DETERMINISTIC-OK"'
else
  echo "  (python3 absent — T54 skipped)"
fi

grp "T55 — parity self-test + recovery proofs (docs/howto)"
if command -v python3 >/dev/null 2>&1; then
  check "T55.1 parity.sh flags an injected node<->python divergence (self-test)" \
    'bash "'"$GEX"'/parity-selftest.sh" 2>&1 | grep -q "PARITY-SELFTEST-CAUGHT"'
  check "T55.2 recovery: doctor flags drift + rot, rebuild heals (real CLI)" \
    'bash "'"$GEX"'/recovery-demo.sh" 2>&1 | grep -q "RECOVERY-GUARDS-OK"'
else
  echo "  (python3 absent — T55 skipped)"
fi

grp "T56 — driver / liveness / auditor howto proofs (docs/howto)"
if command -v python3 >/dev/null 2>&1; then
  check "T56.1 the driver keeps Stage B untrusted (escalate, reject junk, kill hung gate)" \
    'bash "'"$GEX"'/driver-guarantees.sh" 2>&1 | grep -q "STAGE-B-UNTRUSTED-OK"'
  check "T56.2 liveness alarms fire (build_stuck, stale-lease reclaim, review_stuck)" \
    'bash "'"$GEX"'/liveness-demo.sh" 2>&1 | grep -q "LIVENESS-OK"'
  check "T56.3 the auditor catches each weakness and doesn't cry wolf" \
    'bash "'"$GEX"'/audit-rules-check.sh" 2>&1 | grep -q "AUDIT-RULES-PROVEN"'
else
  echo "  (python3 absent — T56 skipped)"
fi

grp "T57 — portability / conformance / diagnose howto proofs (docs/howto)"
if command -v python3 >/dev/null 2>&1; then
  check "T57.1 the same DAG completes under different backends; coupling detected" \
    'bash "'"$GEX"'/portability-selftest.sh" 2>&1 | grep -q "PORTABILITY-OK"'
  check "T57.2 every shipped adapter conforms; non-conformant backends rejected" \
    'bash "'"$GEX"'/backend-conformance.sh" 2>&1 | grep -q "BACKEND-CONFORMANCE-OK"'
  check "T57.3 diagnose names the specific cause of a blocked project" \
    'bash "'"$GEX"'/diagnose-accuracy.sh" 2>&1 | grep -q "DIAGNOSE-ACCURACY-OK"'
else
  echo "  (python3 absent — T57 skipped)"
fi

grp "T58 — re-verify / restore-points / tick-economics howto proofs (docs/howto)"
if command -v python3 >/dev/null 2>&1; then
  check "T58.1 a completed gate re-verifies read-only; a decayed proof is caught" \
    'bash "'"$GEX"'/gate-reverify.sh" 2>&1 | grep -q "REVERIFY-OK"'
  check "T58.2 a gate pass tags a restore point; reset restores the passing state" \
    'bash "'"$GEX"'/restore-points.sh" 2>&1 | grep -q "RESTORE-POINTS-OK"'
  check "T58.3 the tick wakes on work and sleeps while a task is in flight" \
    'bash "'"$GEX"'/tick-economics.sh" 2>&1 | grep -q "TICK-ECONOMICS-OK"'
else
  echo "  (python3 absent — T58 skipped)"
fi

grp "T59 — adoption on-ramp howto proofs (docs/howto)"
if command -v python3 >/dev/null 2>&1; then
  check "T59.1 the quickstart runs end-to-end (init -> gate -> done)" \
    'bash "'"$GEX"'/quickstart-e2e.sh" 2>&1 | grep -q "QUICKSTART-OK"'
  check "T59.2 a worked DAG lints+audits+runs; a hollow-gate DAG is rejected" \
    'bash "'"$GEX"'/dag-authoring-check.sh" 2>&1 | grep -q "DAG-AUTHORING-OK"'
  check "T59.3 completed work survives a dead session; the run continues" \
    'bash "'"$GEX"'/stop-resume.sh" 2>&1 | grep -q "STOP-RESUME-OK"'
  check "T59.4 the real ollama backend completes a gated task (mock model)" \
    'bash "'"$GEX"'/ollama-backend.sh" 2>&1 | grep -q "OLLAMA-BACKEND-OK"'
  check "T59.5 the real claude-code adapter completes a gated task (stub CLI)" \
    'bash "'"$GEX"'/claude-backend.sh" 2>&1 | grep -q "CLAUDE-BACKEND-OK"'
else
  echo "  (python3 absent — T59 skipped)"
fi

grp "T60 — best-practice howto proofs (docs/howto)"
if command -v python3 >/dev/null 2>&1; then
  check "T60.1 a hand-edited state.json is flagged and the log overwrites it" \
    'bash "'"$GEX"'/never-hand-edit-state.sh" 2>&1 | grep -q "STATE-DISCIPLINE-OK"'
  check "T60.2 a failing task is retried up to the cap, then the driver escalates" \
    'bash "'"$GEX"'/escalate-vs-retry.sh" 2>&1 | grep -q "ESCALATE-VS-RETRY-OK"'
  check "T60.3 a review block holds a phase; a non-review phase advances" \
    'bash "'"$GEX"'/selective-refutation.sh" 2>&1 | grep -q "SELECTIVE-REFUTATION-OK"'
  check "T60.4 the worker context is recomputed from settled state" \
    'bash "'"$GEX"'/context-from-state.sh" 2>&1 | grep -q "CONTEXT-FROM-STATE-OK"'
else
  echo "  (python3 absent — T60 skipped)"
fi

grp "T61 — CI / event-log / embed / refutation-loop howto proofs (docs/howto)"
if command -v python3 >/dev/null 2>&1; then
  check "T61.1 CI can gate on exit codes (audit fails hollow; exec 0/non-zero)" \
    'bash "'"$GEX"'/ci-flow.sh" 2>&1 | grep -q "CI-FLOW-OK"'
  check "T61.2 the event log is valid, ordered, and the state reprojects from it" \
    'bash "'"$GEX"'/event-log.sh" 2>&1 | grep -q "EVENT-LOG-OK"'
  check "T61.3 a project runs to completion via the Python library API" \
    'bash "'"$GEX"'/embed-python.sh" 2>&1 | grep -q "EMBED-PYTHON-OK"'
  check "T61.4 a review fail holds; a valid distinct-actor pass advances" \
    'bash "'"$GEX"'/handle-refutation.sh" 2>&1 | grep -q "HANDLE-REFUTATION-OK"'
else
  echo "  (python3 absent — T61 skipped)"
fi

grp "T62 — launch prose guides (integrity + selftest) (docs/howto)"
if command -v python3 >/dev/null 2>&1; then
  check "T62.1 the prose-check selftest holds (good passes; bad rejected)" \
    'bash "'"$GEX"'/prose-check.sh" --selftest 2>&1 | grep -q "PROSE-CHECK-SELFTEST-OK"'
  check "T62.2 the seven prose guides pass integrity (links + real commands)" \
    'bash "'"$GEX"'/prose-check.sh" "$HB_SRC/docs/howto/size-a-task.md" "$HB_SRC/docs/howto/size-a-phase.md" "$HB_SRC/docs/howto/choose-runtime.md" "$HB_SRC/docs/howto/choose-a-backend.md" "$HB_SRC/docs/howto/when-not-to-use-heartbeat.md" "$HB_SRC/docs/howto/run-heartbeat-fully-locally.md" "$HB_SRC/docs/howto/schedule-heartbeat-unattended.md" 2>&1 | grep -q "ALL-PROSE-OK:7"'
else
  echo "  (python3 absent — T62 skipped)"
fi

grp "T63 — exec config: cross-runtime behavioral parity (prints, does not run)"
if command -v python3 >/dev/null 2>&1; then
  P63="$TMP/p63"; HB_NO_GIT=1 bash "$HB_SRC/plugin/bootstrap.sh" "$P63" >/dev/null 2>&1 </dev/null
  # Python: exec config prints a JSON object naming the backend.
  check "T63.1 python exec config prints a backend" \
    'HB_NO_GIT=1 PYTHONPATH="$HB_SRC/py/src" python3 -m heartbeat.cli exec config --dir "$P63" | python3 -c "import sys,json;sys.exit(0 if json.load(sys.stdin).get(\"backend\") else 1)"'
  # Python: exec config must NOT run — the event log is unchanged.
  check "T63.2 python exec config does not run (events unchanged)" \
    'b=$(wc -l < "$P63/.hb/events.jsonl"); HB_NO_GIT=1 PYTHONPATH="$HB_SRC/py/src" python3 -m heartbeat.cli exec config --dir "$P63" >/dev/null 2>&1; a=$(wc -l < "$P63/.hb/events.jsonl"); [ "$b" = "$a" ]'
  # Plugin: hb-exec.js config prints a backend too (the behavior Python now matches).
  check "T63.3 plugin hb-exec.js config prints a backend" \
    'HB_DIR="$P63/.hb" node "$P63/.hb/hb-exec.js" config | python3 -c "import sys,json;sys.exit(0 if json.load(sys.stdin).get(\"backend\") else 1)"'
else
  echo "  (python3 absent — T63 skipped)"
fi

grp "T64 — framework proof harness (Docker-free) + guides (docs/howto)"
FWK="$HB_SRC/tests/frameworks"
check "T64.1 harness --check validates the exemplars (Docker-free)" \
  'bash "'"$FWK"'/run.sh" --check crewai 2>&1 | grep -q "FRAMEWORK-HARNESS-OK:crewai" && bash "'"$FWK"'/run.sh" --check langgraph 2>&1 | grep -q "FRAMEWORK-HARNESS-OK:langgraph"'
check "T64.2 harness derives from source: a real backend without an extra is rejected, matrix all-ok" \
  'o=$(bash "'"$FWK"'/run.sh" --check ollama 2>&1); printf "%s" "$o" | grep -q "not a real backend" && bash "'"$FWK"'/run.sh" --check-all 2>&1 | grep -q "HARNESS-ALL-OK"'
check "T64.3 the suite never invokes the docker CLI (harness stays Docker-free)" \
  '! grep -qE "docker (build|run|pull|images)" "'"$HB_SRC"'/tests/run-tests.sh"'
if command -v python3 >/dev/null 2>&1; then
  check "T64.4 crewai + langgraph adapters conform/degrade (deterministic)" \
    'bash "'"$GEX"'/backend-conformance.sh" 2>&1 | grep -q "BACKEND-CONFORMANCE-OK"'
  check "T64.5 the two framework guides pass prose-integrity" \
    'bash "'"$GEX"'/prose-check.sh" "'"$HB_SRC"'/docs/howto/use-heartbeat-with-crewai.md" "'"$HB_SRC"'/docs/howto/use-heartbeat-with-langgraph.md" 2>&1 | grep -q "ALL-PROSE-OK:2"'
else
  echo "  (python3 absent — T64.4/5 skipped)"
fi

grp "T65 — framework fan-out (5 more): harness (Docker-free) + guides"
check "T65.1 --check validates the five fan-out frameworks (Docker-free)" \
  'ok=1; for f in agno openai-agents autogen smolagents pydantic-ai; do bash "'"$FWK"'/run.sh" --check "$f" 2>&1 | grep -q "FRAMEWORK-HARNESS-OK:$f" || ok=0; done; [ "$ok" = 1 ]'
if command -v python3 >/dev/null 2>&1; then
  check "T65.2 all shipped adapters conform/degrade (deterministic)" \
    'bash "'"$GEX"'/backend-conformance.sh" 2>&1 | grep -q "BACKEND-CONFORMANCE-OK"'
  check "T65.3 the five fan-out guides pass prose-integrity" \
    'bash "'"$GEX"'/prose-check.sh" "'"$HB_SRC"'/docs/howto/use-heartbeat-with-agno.md" "'"$HB_SRC"'/docs/howto/use-heartbeat-with-openai-agents.md" "'"$HB_SRC"'/docs/howto/use-heartbeat-with-autogen.md" "'"$HB_SRC"'/docs/howto/use-heartbeat-with-smolagents.md" "'"$HB_SRC"'/docs/howto/use-heartbeat-with-pydantic-ai.md" 2>&1 | grep -q "ALL-PROSE-OK:5"'
else
  echo "  (python3 absent — T65.2/3 skipped)"
fi

grp "T66 — codex backend (stub proof, Docker-free) + guide"
if command -v python3 >/dev/null 2>&1; then
  check "T66.1 the real codex adapter drives a gated task via a stub CLI (fail-stub does not)" \
    'bash "'"$GEX"'/codex-backend.sh" 2>&1 | grep -q "CODEX-BACKEND-OK"'
  check "T66.2 both runtimes register codex (registry + plugin defaultCmd/executor)" \
    'cd "'"$HB_SRC"'/py" && PYTHONPATH=src python3 -c "from heartbeat.backends import get; assert get(\"codex\").__name__.endswith(\"codex\")" && grep -q "codex-exec.sh" "'"$HB_SRC"'/plugin/templates/hb-exec.js" && [ -f "'"$HB_SRC"'/plugin/templates/executors/codex-exec.sh" ]'
  check "T66.3 the codex guide passes prose-integrity" \
    'bash "'"$GEX"'/prose-check.sh" "'"$HB_SRC"'/docs/howto/use-heartbeat-with-codex.md" 2>&1 | grep -q "ALL-PROSE-OK"'
else
  echo "  (python3 absent — T66 skipped)"
fi

grp "T67 — MCP server (hb mcp-serve, stdio, Docker-free) + guide"
if command -v python3 >/dev/null 2>&1; then
  bash "$GEX/mcp-server.sh" > "$TMP/mcp.out" 2>&1
  check "T67.1 read tools over stdio match the CLI (handshake + tick/next/state)" \
    'grep -q "MCP-READ-OK" "'"$TMP"'/mcp.out"'
  check "T67.2 act tools record via the log and advance; a failing gate does not" \
    'grep -q "MCP-ACT-OK" "'"$TMP"'/mcp.out"'
  check "T67.3 the mutate-only-through-the-log invariant holds (state.json = projection)" \
    'grep -q "MCP-INVARIANT-OK" "'"$TMP"'/mcp.out"'
  check "T67.4 the mcp guide passes prose-integrity" \
    'bash "'"$GEX"'/prose-check.sh" "'"$HB_SRC"'/docs/howto/drive-heartbeat-over-mcp.md" 2>&1 | grep -q "ALL-PROSE-OK"'
else
  echo "  (python3 absent — T67 skipped)"
fi

grp "T68 — MCP HTTP transport (hb mcp-serve --http, Docker-free)"
if command -v python3 >/dev/null 2>&1; then
  # capture once (the script prints multiple markers; a piped `grep -q` on an early one would
  # SIGPIPE the still-writing script and, under pipefail, fail the check — so grep a file).
  bash "$GEX/mcp-http.sh" > "$TMP/http.out" 2>&1
  check "T68.1 a real HTTP JSON-RPC client drives hb mcp-serve --http (read + act, matching the CLI)" \
    'grep -q "MCP-HTTP-OK" "'"$TMP"'/http.out"'
else
  echo "  (python3 absent — T68 skipped)"
fi

grp "T69 — plugin registers the MCP server (surface B) + install guide"
if command -v python3 >/dev/null 2>&1; then
  check "T69.1 the plugin registers hb mcp-serve (static; codex-live where present, isolated + offline)" \
    'bash "'"$GEX"'/plugin-mcp.sh" 2>&1 | grep -q "PLUGIN-MCP-OK"'
  check "T69.2 the install guide passes prose-integrity" \
    'bash "'"$GEX"'/prose-check.sh" "'"$HB_SRC"'/docs/howto/install-the-heartbeat-plugin.md" 2>&1 | grep -q "ALL-PROSE-OK"'
  check "T69.3 the install guide's structural claims hold (venv fallback, hb console, mcp-serve, manifest)" \
    'bash "'"$GEX"'/install-guide.sh" 2>&1 | grep -q "INSTALL-GUIDE-OK"'
else
  echo "  (python3 absent — T69 skipped)"
fi

grp "T70 — MCP 2026-07-28 dual-stack (server/discover, negotiation, HTTP security), Docker-free"
if command -v python3 >/dev/null 2>&1; then
  bash "$GEX/mcp-2026.sh" > "$TMP/2026.out" 2>&1        # capture (multi-line); grep a file, not a pipe
  check "T70.1 server/discover + version negotiation + modern-only result semantics (old byte-identical)" \
    'grep -q "MCP-2026-OK" "'"$TMP"'/2026.out"'
  check "T70.2 HTTP transport hardened (Origin 403 + --allow-remote gate + modern header)" \
    'grep -q "MCP-HTTP-SECURE-OK" "'"$TMP"'/http.out"'
  check "T70.3 the classic handshake path is unregressed by the dual-stack change" \
    'grep -q "MCP-INVARIANT-OK" "'"$TMP"'/mcp.out"'
else
  echo "  (python3 absent — T70 skipped)"
fi

grp "T71 — MCP security note (prose-integrity, proof-referenced), Docker-free"
if command -v python3 >/dev/null 2>&1; then
  check "T71.1 the security note references its proof and passes prose-integrity" \
    'grep -q "mcp-http" "'"$HB_SRC"'/docs/howto/secure-the-mcp-server.md" && bash "'"$GEX"'/prose-check.sh" "'"$HB_SRC"'/docs/howto/secure-the-mcp-server.md" 2>&1 | grep -q "ALL-PROSE-OK"'
else
  echo "  (python3 absent — T71 skipped)"
fi

grp "T72 — opencode backend (stub proof) + MCP wiring, Docker-free"
if command -v python3 >/dev/null 2>&1; then
  check "T72.1 the real opencode adapter drives a gated task via a stub CLI (fail-stub does not)" \
    'bash "'"$GEX"'/opencode-backend.sh" 2>&1 | grep -q "OPENCODE-BACKEND-OK"'
  check "T72.2 both runtimes register opencode (registry resolves + plugin defaultCmd/executor)" \
    'cd "'"$HB_SRC"'/py" && PYTHONPATH=src python3 -c "from heartbeat.backends import get; assert get(\"opencode\").__name__.endswith(\"opencode\")" && grep -q "opencode-exec.sh" "'"$HB_SRC"'/plugin/templates/hb-exec.js" && [ -f "'"$HB_SRC"'/plugin/templates/executors/opencode-exec.sh" ]'
  check "T72.3 the opencode.json mcp config is valid + the wired hb mcp-serve command spins a server" \
    'bash "'"$GEX"'/opencode-mcp.sh" 2>&1 | grep -q "OPENCODE-MCP-OK"'
  check "T72.4 the opencode guide passes prose-integrity" \
    'bash "'"$GEX"'/prose-check.sh" "'"$HB_SRC"'/docs/howto/use-heartbeat-with-opencode.md" 2>&1 | grep -q "ALL-PROSE-OK"'
else
  echo "  (python3 absent — T72 skipped)"
fi

grp "T73 — cross-model refuter (distinct model refutes; both runtimes), Docker-free"
if command -v python3 >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  check "T73.1 the refuter runs on a distinct backend/model from the doer (both runtimes; distinct actor; backward-compat control)" \
    'bash "'"$GEX"'/cross-model-refuter.sh" 2>&1 | grep -q "CROSS-MODEL-REFUTER-OK"'
  check "T73.2 both runtimes' exec config expose the refute config" \
    'cd "'"$HB_SRC"'/py" && PYTHONPATH=src python3 -m heartbeat.cli exec config 2>&1 | grep -qi "refute" && node "'"$HB_SRC"'/plugin/templates/hb-exec.js" config 2>&1 | grep -qi "refute"'
  check "T73.3 the cross-model guide passes prose-integrity" \
    'bash "'"$GEX"'/prose-check.sh" "'"$HB_SRC"'/docs/howto/cross-model-verification.md" 2>&1 | grep -q "ALL-PROSE-OK"'
else
  echo "  (python3/node absent — T73 skipped)"
fi

grp "T74 — agent benchmark harness (hb bench; same DAG, N backends), Docker-free"
if command -v python3 >/dev/null 2>&1; then
  check "T74.1 hb bench scores the same DAG across backends from the event log (good/bad/flaky; review-honest; source unmutated; no env leak)" \
    'bash "'"$GEX"'/agent-bench.sh" 2>&1 | grep -q "AGENT-BENCH-OK"'
  check "T74.2 hb bench is a real subcommand" \
    'cd "'"$HB_SRC"'/py" && PYTHONPATH=src python3 -m heartbeat.cli bench --help >/dev/null 2>&1'
  check "T74.3 the benchmark guide passes prose-integrity" \
    'bash "'"$GEX"'/prose-check.sh" "'"$HB_SRC"'/docs/howto/benchmark-agents.md" 2>&1 | grep -q "ALL-PROSE-OK"'
else
  echo "  (python3 absent — T74 skipped)"
fi

grp "T75 — parity differential-testing oracle (tests/parity-fuzz.sh; seeded generator, node==python across cases)"
if command -v python3 >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  check "T75.1 node == python across many generated cases (the oracle agrees)" \
    'bash "'"$HB_SRC"'/tests/parity-fuzz.sh" 12 2>&1 | grep -q "FUZZ-PARITY-OK:"'
  check "T75.2 the oracle passes clean AND catches an injected node<->python divergence in one run (teeth)" \
    'o=$(bash "'"$HB_SRC"'/tests/parity-fuzz.sh" --selftest 2>&1); echo "$o" | grep -q "SELFTEST-CLEAN-OK" && echo "$o" | grep -q "SELFTEST-CAUGHT:"'
  check "T75.3 the case generator is deterministic (same seed -> identical output)" \
    '[ "$(python3 "'"$HB_SRC"'/tests/gen-parity-case.py" 3 -)" = "$(python3 "'"$HB_SRC"'/tests/gen-parity-case.py" 3 -)" ]'
else
  echo "  (python3/node absent — T75 skipped)"
fi

grp "T76 — verifiable-reward + model-regression (hb reward; hb bench --baseline), Docker-free"
if command -v python3 >/dev/null 2>&1; then
  check "T76.1 reward records carry the deterministic log verdict + derived phase; regression flags worse and clears equal" \
    'bash "'"$GEX"'/reward-regression.sh" 2>&1 | grep -q "REWARD-REGRESSION-OK"'
  check "T76.2 hb reward is a real subcommand" \
    'cd "'"$HB_SRC"'/py" && PYTHONPATH=src python3 -m heartbeat.cli reward --help >/dev/null 2>&1'
  check "T76.3 hb bench exposes --baseline (model-regression)" \
    'cd "'"$HB_SRC"'/py" && PYTHONPATH=src python3 -m heartbeat.cli bench --help 2>&1 | grep -q "baseline"'
else
  echo "  (python3 absent — T76 skipped)"
fi

grp "T77 — operational how-to proofs (parallel/worktree, existing-repo, sparse-deps, unsafe-gate), Docker-free"
if command -v python3 >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  check "T77.1 parallel fan-out isolates in worktrees, merges distinct files, cleans up; hb ready gives only the runnable set" \
    'bash "'"$GEX"'/parallel-fanout.sh" 2>&1 | grep -q "PARALLEL-FANOUT-OK"'
  check "T77.2 the parallel guide passes prose-integrity" \
    'bash "'"$GEX"'/prose-check.sh" "'"$HB_SRC"'/docs/howto/run-tasks-in-parallel.md" 2>&1 | grep -q "ALL-PROSE-OK"'
  check "T77.3 hb init is non-destructive in an existing repo (files + history intact)" \
    'bash "'"$GEX"'/existing-repo.sh" 2>&1 | grep -q "EXISTING-REPO-OK"'
  check "T77.4 the existing-repo guide passes prose-integrity" \
    'bash "'"$GEX"'/prose-check.sh" "'"$HB_SRC"'/docs/howto/add-heartbeat-to-an-existing-repo.md" 2>&1 | grep -q "ALL-PROSE-OK"'
  check "T77.5 over-constrained requires serialize the ready set (1 vs 3), both lint clean" \
    'bash "'"$GEX"'/sparse-deps.sh" 2>&1 | grep -q "SPARSE-DEPS-OK"'
  check "T77.6 the sparse-dependencies guide passes prose-integrity" \
    'bash "'"$GEX"'/prose-check.sh" "'"$HB_SRC"'/docs/howto/write-sparse-dependencies.md" 2>&1 | grep -q "ALL-PROSE-OK"'
  check "T77.7 the auditor flags an unsafe gate (side_effecting + nondeterministic) and clears a safe one" \
    'bash "'"$GEX"'/unsafe-gate.sh" 2>&1 | grep -q "UNSAFE-GATE-OK"'
  check "T77.8 the unsafe-gate guide passes prose-integrity" \
    'bash "'"$GEX"'/prose-check.sh" "'"$HB_SRC"'/docs/howto/review-an-unsafe-gate.md" 2>&1 | grep -q "ALL-PROSE-OK"'
else
  echo "  (python3/node absent — T77 skipped)"
fi

grp "T78 — gated-docs skill (docs-as-verified-claims methodology)"
if command -v python3 >/dev/null 2>&1; then
  check "T78.1 the gated-docs skill passes prose-integrity (links resolve, real commands)" \
    'bash "'"$GEX"'/prose-check.sh" "'"$HB_SRC"'/plugin/skills/gated-docs/SKILL.md" 2>&1 | grep -q "ALL-PROSE-OK"'
  check "T78.2 the skill declares valid frontmatter and points at the real gate machinery" \
    'grep -q "^name: gated-docs" "'"$HB_SRC"'/plugin/skills/gated-docs/SKILL.md" && grep -q "prose-check.sh" "'"$HB_SRC"'/plugin/skills/gated-docs/SKILL.md" && grep -q "writing-behavioral-gates" "'"$HB_SRC"'/plugin/skills/gated-docs/SKILL.md"'
else
  echo "  (python3 absent — T78 skipped)"
fi

grp "T79 — whole how-to library prose integrity (EVERY guide gated, not just a subset)"
if command -v python3 >/dev/null 2>&1; then
  check "T79.1 every docs/howto/*.md guide passes prose-integrity (count == file count)" \
    'D="'"$HB_SRC"'/docs/howto"; n=$(ls "$D"/*.md | wc -l); bash "'"$GEX"'/prose-check.sh" "$D"/*.md 2>&1 | grep -q "ALL-PROSE-OK:$n"'
  check "T79.2 the prose-check selftest still holds after the marker-precision fix" \
    'bash "'"$GEX"'/prose-check.sh" --selftest 2>&1 | grep -q "PROSE-CHECK-SELFTEST-OK"'
else
  echo "  (python3 absent — T79 skipped)"
fi

grp "T80 — relative --dir resolves to an absolute PROJECT_DIR/HB_DIR (both runtimes)"
if command -v python3 >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  check "T80.1 a relative-dir gate (PROJECT_DIR + HB_DIR criteria) passes on both python and node" \
    'bash "'"$GEX"'/relative-dir.sh" 2>&1 | grep -q "RELATIVE-DIR-OK"'
else
  echo "  (python3/node absent — T80 skipped)"
fi

grp "T81 — scheduled self-audit (corpus prose + referenced-proof integrity)"
if command -v python3 >/dev/null 2>&1; then
  check "T81.1 the corpus self-audit passes (prose + referenced-proof integrity, count-matched)" \
    'g=$(ls "'"$HB_SRC"'"/docs/howto/*.md | wc -l); bash "'"$GEX"'/self-audit.sh" 2>&1 | grep -qE "SELF-AUDIT-OK:$g/[1-9][0-9]*"'
  check "T81.2 the self-audit has teeth (catches a missing AND an unwired proof)" \
    'bash "'"$GEX"'/self-audit.sh" --selftest 2>&1 | grep -q "SELF-AUDIT-SELFTEST-OK"'
  check "T81.3 the self-audit guide passes prose-integrity" \
    'bash "'"$GEX"'/prose-check.sh" "'"$HB_SRC"'/docs/howto/run-a-scheduled-self-audit.md" 2>&1 | grep -q "ALL-PROSE-OK"'
else
  echo "  (python3 absent — T81 skipped)"
fi

grp "T82 — tick decision parity (both runtimes emit the same data.reason, incl. review_stuck)"
if command -v python3 >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  check "T82.1 node ≡ python on tick data.reason across fixtures (incl. review_stuck escalation)" \
    'bash "'"$GEX"'/tick-parity.sh" 2>&1 | grep -q "TICK-PARITY-OK"'
  if python3 -c "import pytest" >/dev/null 2>&1; then
    check "T82.2 the Python review_stuck escalation fires at the threshold" \
      'cd "'"$HB_SRC"'/py" && PYTHONPATH=src python3 -m pytest -q tests/test_tick.py -k review_stuck 2>&1 | grep -qE "[1-9][0-9]* passed"'
  else
    echo "  (pytest absent — T82.2 skipped)"
  fi
else
  echo "  (python3/node absent — T82 skipped)"
fi

grp "T83 — gate-runner parity (pass/fail/hollow-floor/timeout, both runtimes)"
if command -v python3 >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  check "T83.1 node ≡ python gate-runner verdicts" \
    'bash "'"$GEX"'/gate-parity.sh" 2>&1 | grep -q "GATE-PARITY-OK"'
else
  echo "  (python3/node absent — T83 skipped)"
fi

grp "T84 — doctor/rot parity (both runtimes agree on rot detection)"
if command -v python3 >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  check "T84.1 node ≡ python rot detection (clean -> none; rotted -> flagged on both)" \
    'bash "'"$GEX"'/doctor-parity.sh" 2>&1 | grep -q "DOCTOR-PARITY-OK"'
else
  echo "  (python3/node absent — T84 skipped)"
fi

grp "T85 — backends-registry parity (same canonical set, both runtimes)"
if command -v python3 >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  check "T85.1 node ≡ python backend registry (canonical set; python-only claude alias normalized)" \
    'bash "'"$GEX"'/registry-parity.sh" 2>&1 | grep -q "REGISTRY-PARITY-OK"'
else
  echo "  (python3/node absent — T85 skipped)"
fi

grp "T86 — hb viz --serve (live dashboard: fresh re-read + Origin-403 + non-loopback refusal + snapshot regression)"
if command -v node >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  check "T86.1 live serve proof passes (viz-serve.sh → VIZ-SERVE-OK)" \
    'bash "'"$GEX"'/viz-serve.sh" 2>&1 | grep -q "VIZ-SERVE-OK"'
else
  echo "  (node/curl absent — T86 skipped)"
fi

grp "T87 — heartbeat-code dep-lint adapter (Seam 1: missing/redundant/collision, transitive-closure, advisory/strict)"
if command -v node >/dev/null 2>&1; then
  check "T87.1 dep-lint proof passes (code-deplint.sh → CODE-DEPLINT-OK)" \
    'bash "'"$GEX"'/code-deplint.sh" 2>&1 | grep -q "CODE-DEPLINT-OK"'
  check "T87.2 codegraph-map proof passes (code-map.sh → CODE-MAP-OK)" \
    'bash "'"$GEX"'/code-map.sh" 2>&1 | grep -q "CODE-MAP-OK"'
else
  echo "  (node absent — T87 skipped)"
fi

grp "T88 — heartbeat-code Seam 2: context provider emits a subgraph (touched symbols + neighbors, not an echo)"
if command -v node >/dev/null 2>&1; then
  check "T88.1 code-context proof passes (code-context.sh → CODE-CONTEXT-OK)" \
    'bash "'"$GEX"'/code-context.sh" 2>&1 | grep -q "CODE-CONTEXT-OK"'
else
  echo "  (node absent — T88 skipped)"
fi

grp "T89 — Seam 2 context-injection parity (both executors inject a configured context_cmd identically)"
if command -v node >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  check "T89.1 node ≡ python inject the context_cmd output into the task payload" \
    'bash "'"$GEX"'/context-inject-parity.sh" 2>&1 | grep -q "CONTEXT-INJECT-PARITY-OK"'
else
  echo "  (node/python absent — T89 skipped)"
fi

grp "T90 — docs adapter (2nd domain): citation graph → codemap, UNCHANGED deplint generalizes"
if command -v node >/dev/null 2>&1; then
  check "T90.1 docs Seam-1 proof passes (docs-deplint.sh → DOCS-DEPLINT-OK)" \
    'bash "'"$GEX"'/docs-deplint.sh" 2>&1 | grep -q "DOCS-DEPLINT-OK"'
else
  echo "  (node absent — T90 skipped)"
fi

grp "T91 — docs adapter Seam 2: docs-context renders a task's direct-cited section text (not 2-hop/self)"
if command -v node >/dev/null 2>&1; then
  check "T91.1 docs context proof passes (docs-context.sh → DOCS-CONTEXT-OK)" \
    'bash "'"$GEX"'/docs-context.sh" 2>&1 | grep -q "DOCS-CONTEXT-OK"'
else
  echo "  (node absent — T91 skipped)"
fi

grp "T92 — adapter skill-integrity (every adapter ships a skill naming real, wired proofs)"
check "T92.1 skill-integrity passes (skill-integrity.sh → SKILL-INTEGRITY-OK)" \
  'bash "'"$GEX"'/skill-integrity.sh" 2>&1 | grep -q "SKILL-INTEGRITY-OK"'
check "T92.2 the integrity checker has teeth (selftest catches missing-skill + unwired-proof)" \
  'bash "'"$GEX"'/skill-integrity.sh" --selftest 2>&1 | grep -q "SKILL-INTEGRITY-SELFTEST-OK"'

grp "T93 — EVERY markdown file under docs/ AND the root claim-docs are prose-gated (README, SECURITY, INSTALL, AGENTS, STATUS, …)"
check "T93.1 all docs/**/*.md + root *.md pass prose-integrity (count == file count; CLAUDE.md excluded — a thin @import pointer to AGENTS.md, itself gated)" \
  'D="'"$HB_SRC"'/docs"; R="'"$HB_SRC"'"; FILES="$(find "$D" -name "*.md"; ls "$R"/*.md | grep -v "/CLAUDE\.md$")"; n=$(printf "%s\n" $FILES | wc -l); bash "'"$GEX"'/prose-check.sh" $(printf "%s\n" $FILES | sort) 2>&1 | grep -q "ALL-PROSE-OK:$n"'

grp "T94 — code adapter parity (node ≡ python: deplint byte-identical, map set-equal, context byte-equal)"
if command -v node >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  check "T94.1 deplint node ≡ python (byte-identical stdout + identical --strict exit, incl. multi-finding order)" \
    'bash "'"$GEX"'/deplint-parity.sh" 2>&1 | grep -q "DEPLINT-PARITY-OK"'
  check "T94.2 codegraph-map node ≡ python (same edges, set-equal)" \
    'bash "'"$GEX"'/codegraph-map-parity.sh" 2>&1 | grep -q "CODEGRAPH-MAP-PARITY-OK"'
  check "T94.3 codegraph-context node ≡ python (byte-identical)" \
    'bash "'"$GEX"'/codegraph-context-parity.sh" 2>&1 | grep -q "CODEGRAPH-CONTEXT-PARITY-OK"'
else
  echo "  (node/python absent — T94 skipped)"
fi

grp "T95 — docs adapter parity (node ≡ python: docs-map set-equal, docs-context byte-equal)"
if command -v node >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  check "T95.1 docs-map node ≡ python (edges + tasks, set-equal)" \
    'bash "'"$GEX"'/docs-map-parity.sh" 2>&1 | grep -q "DOCS-MAP-PARITY-OK"'
  check "T95.2 docs-context node ≡ python (byte-identical, incl. a task citing 2 sections)" \
    'bash "'"$GEX"'/docs-context-parity.sh" 2>&1 | grep -q "DOCS-CONTEXT-PARITY-OK"'
else
  echo "  (node/python absent — T95 skipped)"
fi

grp "T96 — the adapter capability is available NODE-FREE (Python adapters + python context_cmd, no Node)"
if command -v python3 >/dev/null 2>&1; then
  check "T96.1 adapters run with node provably off PATH (adapters-nodefree.sh → ADAPTERS-NODEFREE-OK)" \
    'bash "'"$GEX"'/adapters-nodefree.sh" 2>&1 | grep -q "ADAPTERS-NODEFREE-OK"'
else
  echo "  (python3 absent — T96 skipped)"
fi

grp "T97 — MCP adapter tools (deplint + code_context on the real mcp-serve server, == the Python adapter)"
if command -v python3 >/dev/null 2>&1; then
  check "T97.1 MCP deplint/code_context tools match the Python adapters (mcp-adapters.sh → MCP-ADAPTERS-OK)" \
    'bash "'"$GEX"'/mcp-adapters.sh" 2>&1 | grep -q "MCP-ADAPTERS-OK"'
else
  echo "  (python3 absent — T97 skipped)"
fi

grp "T98 — code adapter DISCOVERY mode (transitive reachability, node ≡ python)"
check "T98.1 discovery reachability correct in all directions (code-discover.sh → CODE-DISCOVER-OK)" \
  'bash "'"$GEX"'/code-discover.sh" 2>&1 | grep -q "CODE-DISCOVER-OK"'
if command -v python3 >/dev/null 2>&1; then
  check "T98.2 discovery is node ≡ python (code-discover-parity.sh → CODE-DISCOVER-PARITY-OK)" \
    'bash "'"$GEX"'/code-discover-parity.sh" 2>&1 | grep -q "CODE-DISCOVER-PARITY-OK"'
else
  echo "  (python3 absent — T98.2 skipped)"
fi

grp "T99 — MCP code_discover tool (on the real mcp-serve server, == the discovery function)"
if command -v python3 >/dev/null 2>&1; then
  check "T99.1 MCP code_discover matches the discovery function (code-discover-mcp.sh → MCP-DISCOVER-OK)" \
    'bash "'"$GEX"'/code-discover-mcp.sh" 2>&1 | grep -q "MCP-DISCOVER-OK"'
else
  echo "  (python3 absent — T99 skipped)"
fi

grp "T100 — deplint-accept: plan-acceptance wrapper (codemap resolution + skip; node ≡ python)"
check "T100.1 acceptance wrapper delegates/skips correctly (deplint-accept.sh → CODE-DEPLINT-ACCEPT-OK)" \
  'bash "'"$GEX"'/deplint-accept.sh" 2>&1 | grep -q "CODE-DEPLINT-ACCEPT-OK"'
if command -v python3 >/dev/null 2>&1; then
  check "T100.2 deplint-accept is node ≡ python (deplint-accept-parity.sh → DEPLINT-ACCEPT-PARITY-OK)" \
    'bash "'"$GEX"'/deplint-accept-parity.sh" 2>&1 | grep -q "DEPLINT-ACCEPT-PARITY-OK"'
else
  echo "  (python3 absent — T100.2 skipped)"
fi

grp "T101 — deplint: no REDUNDANT for a task with no resolved symbols (spec-first / new files)"
if command -v python3 >/dev/null 2>&1; then
  check "T101.1 empty-symbol REDUNDANT suppressed, genuine kept, node ≡ python (deplint-redundant-empty.sh → REDUNDANT-EMPTY-OK)" \
    'bash "'"$GEX"'/deplint-redundant-empty.sh" 2>&1 | grep -q "REDUNDANT-EMPTY-OK"'
else echo "  (python3 absent — T101 skipped)"; fi

grp "T102 — codegraph-exclude-hb: keep CodeGraph off HeartBeat's .hb/ scaffold (idempotent, node ≡ python)"
if command -v python3 >/dev/null 2>&1; then
  check "T102.1 helper excludes .hb/ in codegraph.json, idempotent, preserves config (codegraph-exclude-hb.sh → EXCLUDE-HB-OK)" \
    'bash "'"$GEX"'/codegraph-exclude-hb.sh" 2>&1 | grep -q "EXCLUDE-HB-OK"'
else
  echo "  (python3 absent — T102 skipped)"
fi

grp "T103 — checkpoint lifecycle: a review-gated GATE_x is tagged only at review acceptance (node ≡ python)"
check "T103.1 review-gated tag deferred to review pass; non-review tags at deterministic pass (gate-review-checkpoint.sh → CHECKPOINT-LIFECYCLE-OK)" \
  'bash "'"$GEX"'/gate-review-checkpoint.sh" 2>&1 | grep -q "CHECKPOINT-LIFECYCLE-OK"'

grp "T104 — hb-audit --questions: falsification questions derived per criterion class (node ≡ python)"
if command -v python3 >/dev/null 2>&1; then
  check "T104.1 per-class review questions + general phase question, node ≡ python (review-questions.sh → REVIEW-QUESTIONS-OK)" \
    'bash "'"$GEX"'/review-questions.sh" 2>&1 | grep -q "REVIEW-QUESTIONS-OK"'
else
  echo "  (python3 absent — T104 skipped)"
fi

grp "T105 — gate evidence provenance: gate_passed records {criteria,commit,runtime}, hb evidence reads it (node ≡ python)"
check "T105.1 gate pass records provenance + hb evidence surfaces it (evidence-provenance.sh → EVIDENCE-PROVENANCE-OK)" \
  'bash "'"$GEX"'/evidence-provenance.sh" 2>&1 | grep -q "EVIDENCE-PROVENANCE-OK"'

grp "T106 — codegraph-coverage: per-task symbol coverage + GRAPH-BLIND list (node ≡ python)"
if command -v python3 >/dev/null 2>&1; then
  check "T106.1 coverage lists graph-blind tasks, not covered ones, node ≡ python (code-coverage.sh → CODE-COVERAGE-OK)" \
    'bash "'"$GEX"'/code-coverage.sh" 2>&1 | grep -q "CODE-COVERAGE-OK"'
else
  echo "  (python3 absent — T106 skipped)"
fi

grp "T107 — docs adapter: docs-map recognizes reference-style links, not just inline (node ≡ python)"
if command -v python3 >/dev/null 2>&1; then
  check "T107.1 reference-style + collapsed citations captured; inline still works (docs-map-reflinks.sh → DOCS-REFLINKS-OK)" \
    'bash "'"$GEX"'/docs-map-reflinks.sh" 2>&1 | grep -q "DOCS-REFLINKS-OK"'
else
  echo "  (python3 absent — T107 skipped)"
fi

grp "T108 — docs adapter: docs-map over the repo's OWN docs is a non-empty graph (real-corpus regression guard, node ≡ python)"
if command -v python3 >/dev/null 2>&1; then
  check "T108.1 docs-map over docs/howto/ → non-empty, node ≡ python (real-docs-map.sh → REAL-DOCS-MAP-OK)" \
    'bash "'"$GEX"'/real-docs-map.sh" 2>&1 | grep -q "REAL-DOCS-MAP-OK"'
else
  echo "  (python3 absent — T108 skipped)"
fi

grp "T109 — docs change-impact reuses the neutral discover engine (reverse-citation reachability)"
check "T109.1 discover over the docs citation codemap = who transitively cites a section (docs-discover.sh → DOCS-DISCOVER-OK)" \
  'bash "'"$GEX"'/docs-discover.sh" 2>&1 | grep -q "DOCS-DISCOVER-OK"'

grp "T110 — research adapter: ground-check verifies claims are grounded in stored sources (fabricated/ungrounded/stale)"
check "T110.1 grounding verifier classifies grounded/fabricated/ungrounded/stale, --strict blocks (ground-check.sh → GROUND-CHECK-OK)" \
  'bash "'"$GEX"'/ground-check.sh" 2>&1 | grep -q "GROUND-CHECK-OK"'

grp "T111 — research adapter: ground-check is node ≡ python (byte-identical grounding report)"
if command -v python3 >/dev/null 2>&1; then
  check "T111.1 ground-check node ≡ python (ground-check-parity.sh → GROUND-CHECK-PARITY-OK)" \
    'bash "'"$GEX"'/ground-check-parity.sh" 2>&1 | grep -q "GROUND-CHECK-PARITY-OK"'
else
  echo "  (python3 absent — T111 skipped)"
fi

grp "T112 — research adapter: research-context renders a section's grounded claims for the writer (node ≡ python)"
if command -v python3 >/dev/null 2>&1; then
  check "T112.1 research-context renders only its section's claims + excerpts, node ≡ python (research-context.sh → RESEARCH-CONTEXT-OK)" \
    'bash "'"$GEX"'/research-context.sh" 2>&1 | grep -q "RESEARCH-CONTEXT-OK"'
else echo "  (python3 absent — T112 skipped)"; fi

grp "T113 — research adapter: stamp-evidence records honest source shas so ground-check can verify (node ≡ python)"
if command -v python3 >/dev/null 2>&1; then
  check "T113.1 stamp-evidence stamps the real sha, ground-check then GROUNDED, a later edit is STALE (stamp-evidence.sh → STAMP-EVIDENCE-OK)" \
    'bash "'"$GEX"'/stamp-evidence.sh" 2>&1 | grep -q "STAMP-EVIDENCE-OK"'
else echo "  (python3 absent — T113 skipped)"; fi

grp "T114 — research adapter: red-team corpus proves ground-check catches mechanical fabrication and stays silent on truth"
if command -v python3 >/dev/null 2>&1; then
  check "T114.1 all mechanical failure modes classified, two grounded-but-wrong claims unflagged, node ≡ python (ground-check-redteam.sh → RED-TEAM-OK)" \
    'bash "'"$GEX"'/ground-check-redteam.sh" 2>&1 | grep -q "RED-TEAM-OK grounded=3 issues=5"'
else echo "  (python3 absent — T114 skipped)"; fi

grp "T115 — research adapter: node ≡ python on a large generated corpus (60 sources / 200 claims, unicode, line-wraps)"
if command -v python3 >/dev/null 2>&1; then
  check "T115.1 ground-check + research-context byte-identical, stamp-evidence same map, within a timeout ceiling (research-scale-parity.sh → SCALE-PARITY-OK)" \
    'bash "'"$GEX"'/research-scale-parity.sh" 2>&1 | grep -q "SCALE-PARITY-OK sources=60 claims=200 grounded=160 issues=40"'
else echo "  (python3 absent — T115 skipped)"; fi

grp "T116 — reference doc stays in sync: every shipped adapter tool is documented in adapters.md"
check "T116.1 each plugin/adapters/<domain>/*.js is named in docs/adapters.md (anti-drift, derived from the filesystem) (adapters-doc-coverage.sh → ADAPTERS-DOC-OK)" \
  'bash "'"$GEX"'/adapters-doc-coverage.sh" 2>&1 | grep -q "ADAPTERS-DOC-OK"'

grp "T117 — bootstrap installs a BLOCKING pre-push gate guard (blocks on a failing gate, non-clobber, HB_NO_HOOK bypass, existing repos)"
check "T117.1 the pre-push hook blocks iff gate re-verify fails, never clobbers, honors HB_NO_HOOK, installs on existing repos (pre-push-hook.sh → PRE-PUSH-HOOK-OK)" \
  'bash "'"$GEX"'/pre-push-hook.sh" 2>&1 | grep -q "PRE-PUSH-HOOK-OK"'

grp "T118 — pre-push gate guard is behavioral node ≡ python (both bootstraps install a blocking hook)"
if command -v python3 >/dev/null 2>&1; then
  check "T118.1 node bootstrap.sh and python hb init both install a hook that blocks iff gate re-verify fails (pre-push-hook-parity.sh → PRE-PUSH-PARITY-OK)" \
    'bash "'"$GEX"'/pre-push-hook-parity.sh" 2>&1 | grep -q "PRE-PUSH-PARITY-OK"'
else
  echo "  (python3 absent — T118 skipped)"
fi

grp "T119 — review integrity: a degraded refuter never passes (sentinel → review_error), a genuine review isn't discarded, robust verdict (both runtimes)"
if command -v python3 >/dev/null 2>&1; then
  check "T119.1 py backends degrade to a sentinel (no bool refuted); node claude-exec.sh degrade→sentinel, clear carries real findings, verdict by final token (refute-integrity.sh → REFUTE-INTEGRITY-OK)" \
    'bash "'"$GEX"'/refute-integrity.sh" 2>&1 | grep -q "REFUTE-INTEGRITY-OK"'
else
  echo "  (python3 absent — T119 skipped)"
fi

grp "T120 — hb init preserves the append-only event log unless --force (parity with node bootstrap)"
if command -v python3 >/dev/null 2>&1; then
  check "T120.1 re-init without --force does not wipe events.jsonl (init-preserves-log.sh → INIT-LOG-SAFE-OK)" \
    'bash "'"$GEX"'/init-preserves-log.sh" 2>&1 | grep -q "INIT-LOG-SAFE-OK"'
else
  echo "  (python3 absent — T120 skipped)"
fi

grp "T121 — gate criteria run under the same shell in both runtimes (bash, not dash) + failure output not swallowed"
if command -v python3 >/dev/null 2>&1; then
  check "T121.1 a [[ ]] criterion passes identically under gate.sh and gate.py; a failing gate surfaces a diagnostic (gate-shell-parity.sh → GATE-SHELL-PARITY-OK)" \
    'bash "'"$GEX"'/gate-shell-parity.sh" 2>&1 | grep -q "GATE-SHELL-PARITY-OK"'
else
  echo "  (python3 absent — T121 skipped)"
fi

grp "T122 — the pre-push hook is self-contained/honest (tested as it runs: no PYTHONPATH, hb-absent = skip not import-error-block)"
if command -v python3 >/dev/null 2>&1; then
  check "T122.1 node hook self-contained (blocks under a clean PATH); py hook skips with a message when hb absent (pre-push-selfcontained.sh → PRE-PUSH-SELFCONTAINED-OK)" \
    'bash "'"$GEX"'/pre-push-selfcontained.sh" 2>&1 | grep -q "PRE-PUSH-SELFCONTAINED-OK"'
else
  echo "  (python3 absent — T122 skipped)"
fi

grp "T123 — real CI: a .github/workflows wires the three suites (run-tests.sh + pytest + parity.sh)"
check "T123.1 a valid CI workflow exists and invokes the three suites on push/PR (ci-workflow.sh → CI-WORKFLOW-OK)" \
  'bash "'"$GEX"'/ci-workflow.sh" 2>&1 | grep -q "CI-WORKFLOW-OK"'

grp "T124 — anti-drift: the how-to index + dev-tests T-table stay derived-consistent with source"
check "T124.1 every guide is listed and every suite group is in the dev-tests table (index-coverage.sh → INDEX-COVERAGE-OK)" \
  'bash "'"$GEX"'/index-coverage.sh" 2>&1 | grep -q "INDEX-COVERAGE-OK"'

grp "T125 — honest claims: LICENSE (MIT) ships + no unpublished pip-install presented as an install line"
check "T125.1 LICENSE exists (MIT) and no doc uses \`pip install heartbeat-hb\` as an install line (claim-honesty.sh → CLAIM-HONESTY-OK)" \
  'bash "'"$GEX"'/claim-honesty.sh" 2>&1 | grep -q "CLAIM-HONESTY-OK"' 

grp "T126 — kernel: rot-lint precision (sed/abspath criteria don't false-trip gate_rot; a real deletion still does)"
check "T126.1 extractPaths excludes shell constructs + absolute paths, keeps real relative artifacts (rot-lint-precision.sh → ROT-LINT-PRECISION-OK)" \
  'bash "'"$GEX"'/rot-lint-precision.sh" 2>&1 | grep -q "ROT-LINT-PRECISION-OK"'

grp "T127 — kernel: state.json is a deterministic projection (byte-stable across rebuilds)"
if command -v python3 >/dev/null 2>&1; then
  check "T127.1 two rebuilds produce byte-identical state.json (state-determinism.sh → STATE-DETERMINISM-OK)" \
    'bash "'"$GEX"'/state-determinism.sh" 2>&1 | grep -q "STATE-DETERMINISM-OK"'
else echo "  (python3 absent — T127 skipped)"; fi

grp "T128 — kernel: a gate passes on a git-less machine (git is optional, no crash)"
if command -v python3 >/dev/null 2>&1; then
  check "T128.1 gate PASS with git absent from PATH does not crash + records the pass (gate-gitless.sh → GATE-GITLESS-OK)" \
    'bash "'"$GEX"'/gate-gitless.sh" 2>&1 | grep -q "GATE-GITLESS-OK"'
else echo "  (python3 absent — T128 skipped)"; fi

grp "T129 — kernel: gate_blocked circuit breaker (stops re-waking after a bound)"
if command -v python3 >/dev/null 2>&1; then
  check "T129.1 a persistently blocked gate emits a terminal waiting signal instead of re-waking every tick (gate-blocked-breaker.sh → GATE-BLOCKED-BREAKER-OK)" \
    'bash "'"$GEX"'/gate-blocked-breaker.sh" 2>&1 | grep -q "GATE-BLOCKED-BREAKER-OK"' 
else echo "  (python3 absent — T129 skipped)"; fi

grp "T130 — safety: python backends decide the verdict by the final REFUTED/CLEAR token (shared helper)"
if command -v python3 >/dev/null 2>&1; then
  check "T130.1 verdict_refuted: prose mentioning REFUTED but ending CLEAR is not a refutation; final token wins (verdict-robust.sh → VERDICT-ROBUST-OK)" \
    'bash "'"$GEX"'/verdict-robust.sh" 2>&1 | grep -q "VERDICT-ROBUST-OK"'
else echo "  (python3 absent — T130 skipped)"; fi

grp "T131 — safety: subprocess/JS take data via argv, not source-splicing (no injection via a crafted path)"
if command -v python3 >/dev/null 2>&1; then
  check "T131.1 doctor rot-trace runs no injected command via a \$(...) project path; bootstrap node -e is argv-safe (injection-safe.sh → INJECTION-SAFE-OK)" \
    'bash "'"$GEX"'/injection-safe.sh" 2>&1 | grep -q "INJECTION-SAFE-OK"'
else echo "  (python3 absent — T131 skipped)"; fi

grp "T132 — portability: drift hashing works on macOS (shasum fallback) and is not a silent no-op"
check "T132.1 with sha256sum absent, drift still hashes (shasum) and a changed watched file yields a different hash (drift-portable.sh → DRIFT-PORTABLE-OK)" \
  'bash "'"$GEX"'/drift-portable.sh" 2>&1 | grep -q "DRIFT-PORTABLE-OK"'

grp "T133 — portability: adapter-skill runnable commands resolve from an installed plugin (\${CLAUDE_PLUGIN_ROOT})"
check "T133.1 no adapter skill runs a bare repo-relative plugin/adapters path (skill-paths.sh → SKILL-PATHS-OK)" \
  'bash "'"$GEX"'/skill-paths.sh" 2>&1 | grep -q "SKILL-PATHS-OK"'

grp "T134 — portability: MCP entry is runtime-honest + the command-surface decision is realized"
check "T134.1 .mcp.json declares the server, a doc states it needs the Python hb, and R9 (commands/ OR skill-documented) holds (mcp-json-runtime.sh → MCP-JSON-RUNTIME-OK)" \
  'bash "'"$GEX"'/mcp-json-runtime.sh" 2>&1 | grep -q "MCP-JSON-RUNTIME-OK"' 

grp "T135 — honesty: a coverage floor prevents a silent ALL-GREEN when most groups skipped"
check "T135.1 run-tests emits GROUPS-SKIPPED + a _coverage_check floor marks a mostly-skipped run INCOMPLETE (coverage-floor.sh → COVERAGE-FLOOR-OK)" \
  'bash "'"$GEX"'/coverage-floor.sh" 2>&1 | grep -q "COVERAGE-FLOOR-OK"'

grp "T136 — honesty: every example DAG (planning/*.dag.json) lints clean + audits 0 hollow"
check "T136.1 all planning/*.dag.json lint 0-error and audit 0-hollow (example-dags-gated.sh → EXAMPLE-DAGS-GATED-OK)" \
  'bash "'"$GEX"'/example-dags-gated.sh" 2>&1 | grep -q "EXAMPLE-DAGS-GATED-OK"'

grp "T137 — honesty: the audit-fixture count in the docs matches what parity.sh iterates"
check "T137.1 docs state the same audit-fixture count parity.sh uses (doc-fixture-count.sh → DOC-FIXTURE-COUNT-OK)" \
  'bash "'"$GEX"'/doc-fixture-count.sh" 2>&1 | grep -q "DOC-FIXTURE-COUNT-OK"'

grp "T138 — anti-drift: must-not-drift logic is single-sourced (protocol keys + nonBehavioral)"
if command -v python3 >/dev/null 2>&1; then
  check "T138.1 SKILL.md reason table == protocol.py keys AND hb-exec imports hb-audit's nonBehavioral, not a fork (single-source.sh → SINGLE-SOURCE-OK)" \
    'bash "'"$GEX"'/single-source.sh" 2>&1 | grep -q "SINGLE-SOURCE-OK"'
else echo "  (python3 absent — T138 skipped)"; fi

grp "T139 — safety: the write-lock gives real mutual exclusion over a read-modify-write, both runtimes"
if command -v python3 >/dev/null 2>&1; then
  check "T139.1 two concurrent workers through withWlock/with_wlock serialize an RMW (counter==2, no lost update); gutting the lock turns it RED (wlock-tested.sh → WLOCK-TESTED-OK)" \
    'bash "'"$GEX"'/wlock-tested.sh" 2>&1 | grep -q "WLOCK-TESTED-OK"'
else echo "  (python3 absent — T139 skipped)"; fi

grp "T140 — safety: tick.sh's lock-free appends don't corrupt events.jsonl (atomic O_APPEND), with teeth"
if command -v python3 >/dev/null 2>&1; then
  check "T140.1 60 concurrent >> appends + real concurrent ticks keep events.jsonl valid & complete (tick-append-safe.sh → TICK-APPEND-SAFE-OK)" \
    'bash "'"$GEX"'/tick-append-safe.sh" 2>&1 | grep -q "TICK-APPEND-SAFE-OK"'
  check "T140.2 the check has teeth: a non-atomic read-concat-write loses updates under the same concurrency (tick-append-safe.sh --selftest → SELFTEST-OK)" \
    'bash "'"$GEX"'/tick-append-safe.sh" --selftest 2>&1 | grep -q "SELFTEST-OK"'
else echo "  (python3 absent — T140 skipped)"; fi

grp "T141 — parity: git-snapshot on review acceptance commits + tags in BOTH runtimes (cross-runtime pair)"
if command -v python3 >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
  check "T141.1 driving hb review GATE_P0 pass creates the GATE_P0 commit+tag in node AND python; a missing tag is RED (git-snapshot-parity.sh → GIT-SNAPSHOT-PARITY-OK)" \
    'bash "'"$GEX"'/git-snapshot-parity.sh" 2>&1 | grep -q "GIT-SNAPSHOT-PARITY-OK"'
else echo "  (python3/git absent — T141 skipped)"; fi

grp "T142 — honesty: docs reflect current code (review_policy single-source, no stale moved-fixture paths, versions consistent)"
if command -v python3 >/dev/null 2>&1; then
  check "T142.1 dev docs describe review_policy/accept_review + GROUPS-SKIPPED, no doc references the moved fixtures, plugin==marketplace version (docs-currency.sh → DOCS-CURRENT-OK)" \
    'bash "'"$GEX"'/docs-currency.sh" 2>&1 | grep -q "DOCS-CURRENT-OK"'
  check "T142.2 the check has teeth: RED on a planted stale audit-fixtures path AND on a missing positive token (docs-currency.sh --selftest → SELFTEST-OK)" \
    'bash "'"$GEX"'/docs-currency.sh" --selftest 2>&1 | grep -q "SELFTEST-OK"'
else echo "  (python3 absent — T142 skipped)"; fi

grp "T143 — reliability: the SessionStart hook teaches an agent to DRIVE the loop (not react to one tick)"
check "T143.1 on a .hb/ project the hook instructs re-running tick.sh in a loop + names stop conditions (all_done + human-needed); silent off-project (hook-drives-loop.sh → HOOK-DRIVES-LOOP-OK)" \
  'bash "'"$GEX"'/hook-drives-loop.sh" 2>&1 | grep -q "HOOK-DRIVES-LOOP-OK"'
check "T143.2 the check has teeth: a reactive-only hook is rejected, a drive-hook passes, no leakage off-project (hook-drives-loop.sh --selftest → SELFTEST-OK)" \
  'bash "'"$GEX"'/hook-drives-loop.sh" --selftest 2>&1 | grep -q "SELFTEST-OK"'

grp "T144 — reliability: the MCP tick tool teaches an interactive client to DRIVE the loop (Python-only surface)"
if command -v python3 >/dev/null 2>&1; then
  check "T144.1 driving the real hb mcp-serve: the tick tool description teaches driving + a pending tick nudges (data.next) + an all_done tick does not (mcp-drives-loop.sh → MCP-DRIVES-LOOP-OK)" \
    'bash "'"$GEX"'/mcp-drives-loop.sh" 2>&1 | grep -q "MCP-DRIVES-LOOP-OK"'
  check "T144.2 the check has teeth: each description check + the nudge/no-nudge rule is individually load-bearing (mcp-drives-loop.sh --selftest → SELFTEST-OK)" \
    'bash "'"$GEX"'/mcp-drives-loop.sh" --selftest 2>&1 | grep -q "SELFTEST-OK"'
else echo "  (python3 absent — T144 skipped)"; fi

grp "T145 — refuter profiles: the resolver turns a NAME into a normalized profile (node ≡ python), default always resolvable, unknown errors"
if command -v python3 >/dev/null 2>&1; then
  check "T145.1 a named profile resolves its fields, a built-in default is always resolvable, an unknown explicit name errors, precedence (explicit > env > project-file > built-in) holds, node ≡ python (refuter-profile-resolve.sh → REFUTER-RESOLVE-OK)" \
    'bash "'"$GEX"'/refuter-profile-resolve.sh" 2>&1 | grep -q "REFUTER-RESOLVE-OK"'
  check "T145.2 the check has teeth: each field, each precedence tier (incl. the env default and the project shadow of default), and the unknown-errors path is individually load-bearing (refuter-profile-resolve.sh --selftest → SELFTEST-OK)" \
    'bash "'"$GEX"'/refuter-profile-resolve.sh" --selftest 2>&1 | grep -q "SELFTEST-OK"'
else echo "  (python3 absent — T145 skipped)"; fi

grp "T146 — refuter profiles: shareable library — shipped refuters seeded by bootstrap (no-clobber shadow), behavioral integrity, hb refuters discovery node ≡ python"
if command -v python3 >/dev/null 2>&1; then
  check "T146.1 a shipped refuter is seeded into .hb/refuters/ and resolves, a project file shadows a shipped one and survives re-bootstrap, every shipped refuter is valid+resolvable, and hb refuters lists identically node ≡ python (refuter-library.sh → REFUTER-LIBRARY-OK)" \
    'bash "'"$GEX"'/refuter-library.sh" 2>&1 | grep -q "REFUTER-LIBRARY-OK"'
  check "T146.2 the check has teeth: seeding, override (no-clobber), discovery-parity, and behavioral integrity are each individually load-bearing (refuter-library.sh --selftest → SELFTEST-OK)" \
    'bash "'"$GEX"'/refuter-library.sh" --selftest 2>&1 | grep -q "SELFTEST-OK"'
else echo "  (python3 absent — T146 skipped)"; fi

grp "T147 — refuter profiles: ONE hb refute-prompt compose serves the refute path — backward-compat byte-identical, named profile appends persona+questions, unknown errors at dispatch, node ≡ python"
if command -v python3 >/dev/null 2>&1; then
  check "T147.1 no-profile is byte-identical to today; a named profile injects persona + BASE review_questions (appended, not replaced) + review.prompt; profile.model reaches the dispatch; an unknown profile fails closed; node ≡ python (refuter-compose.sh → REFUTER-COMPOSE-OK)" \
    'bash "'"$GEX"'/refuter-compose.sh" 2>&1 | grep -q "REFUTER-COMPOSE-OK"'
  check "T147.2 the check has teeth: backward-compat (no leaked profile material), coverage-narrowing (append not replace), and unknown-errors are each individually load-bearing (refuter-compose.sh --selftest → SELFTEST-OK)" \
    'bash "'"$GEX"'/refuter-compose.sh" --selftest 2>&1 | grep -q "SELFTEST-OK"'
else echo "  (python3 absent — T147 skipped)"; fi

grp "T148 — refuter profiles: perspective-diverse panel verdict — a profile's verdict {panel:N, refute_if} runs N refuters and aggregates (majority/any/all), fail-closed, node ≡ python"
if command -v python3 >/dev/null 2>&1; then
  check "T148.1 panel aggregation runs N refuters and decides by majority/any/all, the no-panel single path is unchanged, a non-bool panelist fails closed; identical in both runtimes (refuter-panel.sh → REFUTER-PANEL-OK)" \
    'bash "'"$GEX"'/refuter-panel.sh" 2>&1 | grep -q "REFUTER-PANEL-OK"'
  check "T148.2 the check has teeth: majority/any/all each produce a distinct outcome on a crafted verdict set, and a non-bool verdict is an error (refuter-panel.sh --selftest → SELFTEST-OK)" \
    'bash "'"$GEX"'/refuter-panel.sh" --selftest 2>&1 | grep -q "SELFTEST-OK"'
else echo "  (python3 absent — T148 skipped)"; fi

grp "T149 — refuter profiles: a panel verdict is read from the PROFILE only — a gate/review-level verdict is silently inert (both runtimes)"
if command -v python3 >/dev/null 2>&1; then
  check "T149.1 verdict{panel:3} on the profile drives 3 refute dispatches; the same verdict on the gate's review block drives 1 (ignored); both runtimes (refuter-verdict-placement.sh → REFUTER-VERDICT-PLACEMENT-OK)" \
    'bash "'"$GEX"'/refuter-verdict-placement.sh" 2>&1 | grep -q "REFUTER-VERDICT-PLACEMENT-OK"'
  check "T149.2 the check has teeth: profile-inert (1 dispatch) and gate-honoured (3 dispatches) are each rejected (refuter-verdict-placement.sh --selftest → SELFTEST-OK)" \
    'bash "'"$GEX"'/refuter-verdict-placement.sh" --selftest 2>&1 | grep -q "SELFTEST-OK"'
else echo "  (python3 absent — T149 skipped)"; fi

grp "T150 — refuter profiles: skill-format authoring — a folder <name>/SKILL.md and a lite <name>.md resolve to the same dict as .json (shared no-YAML parser, node ≡ python), listed + collision-safe"
if command -v python3 >/dev/null 2>&1; then
  check "T150.1 a canonical <name>/SKILL.md folder AND a lite <name>.md resolve to the same normalized dict as .json (non-trivial fixture), both are listed by hb refuters (a references/ subdir is not), per-trap parity holds, a cross-format collision errors (refuter-skill-format.sh → REFUTER-SKILL-OK)" \
    'bash "'"$GEX"'/refuter-skill-format.sh" 2>&1 | grep -q "REFUTER-SKILL-OK"'
  check "T150.2 the check has teeth: each flat-parser divergence trap is caught by the parity check, and the folder-listing / non-SKILL.md-subdir checks are load-bearing (refuter-skill-format.sh --selftest → SELFTEST-OK)" \
    'bash "'"$GEX"'/refuter-skill-format.sh" --selftest 2>&1 | grep -q "SELFTEST-OK"'
  check "T150.3 seeding is collision-safe: the shipped library defines no name in >1 format, a bootstrapped project resolves every seeded refuter incl. a folder one, re-bootstrap manufactures no collision (refuter-skill-format.sh --seeding → SEEDING-SAFE-OK)" \
    'bash "'"$GEX"'/refuter-skill-format.sh" --seeding 2>&1 | grep -q "SEEDING-SAFE-OK"'
else echo "  (python3 absent — T150 skipped)"; fi

grp "T151 — refuter profiles: quick scaffolder — hb refuters new <name> [--from <starter>] [--lite] writes a resolvable refuter, no-clobber, byte-identical node ≡ python"
if command -v python3 >/dev/null 2>&1; then
  check "T151.1 hb refuters new scaffolds a canonical folder (or --lite file) that resolves, --from carries the starter lens, unknown starter + path-separator name error, no-clobber across formats, byte-identical node ≡ python, bare list still works (refuter-scaffold.sh → REFUTER-SCAFFOLD-OK)" \
    'bash "'"$GEX"'/refuter-scaffold.sh" 2>&1 | grep -q "REFUTER-SCAFFOLD-OK"'
  check "T151.2 the check has teeth: resolvable-output, unknown-starter-errors, no-clobber, byte-parity, and bare-list-still-works each individually load-bearing (refuter-scaffold.sh --selftest → SELFTEST-OK)" \
    'bash "'"$GEX"'/refuter-scaffold.sh" --selftest 2>&1 | grep -q "SELFTEST-OK"'
else echo "  (python3 absent — T151 skipped)"; fi

grp "T152 — refuter profiles: hb report surfaces REFUTER IMPACT from the event log (catches vs clears, per gate + lens), node ≡ python"
if command -v python3 >/dev/null 2>&1; then
  check "T152.1 review_failed=catch / review_passed=clear, counted per gate with its review.profile lens + findings; a review-less project reports zero and renders no section; node ≡ python canonical summary (refuter-impact.sh → REFUTER-IMPACT-OK)" \
    'bash "'"$GEX"'/refuter-impact.sh" 2>&1 | grep -q "REFUTER-IMPACT-OK"'
  check "T152.2 the check has teeth: the caught-count, lens, findings, and parity checks are each individually load-bearing (refuter-impact.sh --selftest → SELFTEST-OK)" \
    'bash "'"$GEX"'/refuter-impact.sh" --selftest 2>&1 | grep -q "SELFTEST-OK"'
else echo "  (python3 absent — T152 skipped)"; fi

grp "T153 — gate integrity: a criterion cmd with an embedded newline (heredoc) is counted correctly, not misparsed into bogus passing records (gate.sh RS-delimited transport), node ≡ python"
if command -v python3 >/dev/null 2>&1; then
  check "T153.1 a 3-fail gate whose middle criterion is a multi-line heredoc reports 0 passed / 3 failed with no bogus heredoc-body entries and the newline criterion correctly fails; node/bash ≡ python (gate-newline-cmd.sh → GATE-NEWLINE-CMD-OK)" \
    'bash "'"$GEX"'/gate-newline-cmd.sh" 2>&1 | grep -q "GATE-NEWLINE-CMD-OK"'
  check "T153.2 the check has teeth: the pass-count and bogus-heredoc-body detectors are each load-bearing (gate-newline-cmd.sh --selftest → SELFTEST-OK)" \
    'bash "'"$GEX"'/gate-newline-cmd.sh" --selftest 2>&1 | grep -q "SELFTEST-OK"'
else echo "  (python3 absent — T153 skipped)"; fi

grp "T154 — gate integrity: the auditor flags a \\x1e/\\x1f control byte in a cmd/desc as a LOUD error (defense-in-depth for the transport), node ≡ python"
if command -v python3 >/dev/null 2>&1; then
  check "T154.1 a criterion cmd carrying a \\x1e/\\x1f control byte is an audit error (exit 1) named control_char; a clean dag is fine; node ≡ python findings (audit-ctrl-byte.sh → AUDIT-CTRL-BYTE-OK)" \
    'bash "'"$GEX"'/audit-ctrl-byte.sh" 2>&1 | grep -q "AUDIT-CTRL-BYTE-OK"'
  check "T154.2 the check has teeth: the detector discriminates (clean not flagged) and BOTH \\x1e and \\x1f trigger it (audit-ctrl-byte.sh --selftest → SELFTEST-OK)" \
    'bash "'"$GEX"'/audit-ctrl-byte.sh" --selftest 2>&1 | grep -q "SELFTEST-OK"'
else echo "  (python3 absent — T154 skipped)"; fi

grp "T155 — bootstrap: re-bootstrap with a live-but-silent pipe on stdin refuses instead of hanging ([-t 0] guard); non-tty refuses (no overwrite); --force still overwrites; portable (no timeout(1))"
check "T155.1 non-interactive re-bootstrap returns rather than blocking on a silent pipe, refuses (no overwrite), and --force overwrites (bootstrap-noninteractive.sh → BOOTSTRAP-NI-OK)" \
  'bash "'"$GEX"'/bootstrap-noninteractive.sh" 2>/dev/null | grep -q "BOOTSTRAP-NI-OK"'
check "T155.2 the check has teeth: the silent-pipe detector flags the unguarded read AND clears the [-t 0]-guarded one (bootstrap-noninteractive.sh --selftest → SELFTEST-OK)" \
  'bash "'"$GEX"'/bootstrap-noninteractive.sh" --selftest 2>/dev/null | grep -q "SELFTEST-OK"'

grp "T156 — gate integrity: gate.sh bounds every criterion even with NO timeout(1)/gtimeout (stock macOS) — a portable shell-level bound kills a hanging criterion (✗) instead of running unbounded; parity with the python runner"
check "T156.1 under a curated PATH lacking timeout/gtimeout, a sleep-past-GATE_TIMEOUT_S criterion is killed → gate blocks (fast), a quick criterion still passes (gate-timeout-portable.sh → GATE-TIMEOUT-PORTABLE-OK)" \
  'bash "'"$GEX"'/gate-timeout-portable.sh" 2>/dev/null | grep -q "GATE-TIMEOUT-PORTABLE-OK"'
check "T156.2 the check has teeth: run_bounded flags a hang AND clears a quick cmd, and the curated PATH truly excludes timeout/gtimeout while keeping bash/node/sleep (gate-timeout-portable.sh --selftest → SELFTEST-OK)" \
  'bash "'"$GEX"'/gate-timeout-portable.sh" --selftest 2>/dev/null | grep -q "SELFTEST-OK"'

# Outcome marker: groups with zero failing checks (a coverage gate keys on this).
_gp=""; for g in $_ALLG; do [ -z "${_GFAIL[$g]:-}" ] && _gp="$_gp $g"; done
echo "GROUPS-PASSED:$_gp "
# H1: groups that registered but ran NO checks were skipped (a tool/dep was absent).
_ran=0; _skipped=0
for g in $_ALLG; do if [ -n "${_GCHECKS[$g]:-}" ]; then _ran=$((_ran+1)); else _skipped=$((_skipped+1)); fi; done
echo "GROUPS-RAN: $_ran  GROUPS-SKIPPED: $_skipped"
_coverage_check "$_ran" "$_skipped" || COVER_INCOMPLETE=1

echo ""
echo "═══════════════════════════════════════"
echo "  RESULT: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
if [ "$FAIL" -ne 0 ]; then echo "❌ FAILURES"; exit 1
elif [ "${COVER_INCOMPLETE:-0}" = 1 ]; then echo "❌ INCOMPLETE — coverage floor (too many groups skipped)"; exit 3
else echo "✅ ALL GREEN"; exit 0; fi
