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
declare -A _GFAIL; _CURG=""; _ALLG=""
# grp "<Tnn — title>" — start a group; enables an outcome marker (GROUPS-PASSED) so a
# coverage gate can assert a group PASSED, not just that its header exists.
grp(){ _CURG="${1%% *}"; case " $_ALLG " in *" $_CURG "*) ;; *) _ALLG="$_ALLG $_CURG";; esac; echo "═══ $1 ═══"; }
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
ko(){ echo "  ✗ $1"; FAIL=$((FAIL+1)); [ -n "$_CURG" ] && _GFAIL["$_CURG"]=1; }
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
check "T39.4 plugin version bumped to 1.16.0" \
  'grep -q "1.16.0" "$HB_SRC/plugin/.claude-plugin/plugin.json"'

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
FIX="$HB_SRC/planning/audit-fixtures"
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
  check "T62.2 the five launch prose guides pass integrity (links + real commands)" \
    'bash "'"$GEX"'/prose-check.sh" "$HB_SRC/docs/howto/size-a-task.md" "$HB_SRC/docs/howto/size-a-phase.md" "$HB_SRC/docs/howto/choose-runtime.md" "$HB_SRC/docs/howto/choose-a-backend.md" "$HB_SRC/docs/howto/when-not-to-use-heartbeat.md" 2>&1 | grep -q "ALL-PROSE-OK:5"'
else
  echo "  (python3 absent — T62 skipped)"
fi

# Outcome marker: groups with zero failing checks (a coverage gate keys on this).
_gp=""; for g in $_ALLG; do [ -z "${_GFAIL[$g]:-}" ] && _gp="$_gp $g"; done
echo "GROUPS-PASSED:$_gp "

echo ""
echo "═══════════════════════════════════════"
echo "  RESULT: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] && { echo "✅ ALL GREEN"; exit 0; } || { echo "❌ FAILURES"; exit 1; }
