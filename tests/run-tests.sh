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
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
ko(){ echo "  ✗ $1"; FAIL=$((FAIL+1)); }
check(){ if eval "$2" >/dev/null 2>&1; then ok "$1"; else ko "$1"; fi; }
set_state(){ node -e "const fs=require('fs');const f=process.argv[1];const s=JSON.parse(fs.readFileSync(f,'utf8'));${1};fs.writeFileSync(f,JSON.stringify(s,null,2));" "$HB/state.json"; }
tick(){ rm -rf "$HB/.lock"; bash "$HB/tick.sh"; }

echo "═══ T1 — bootstrap (non-interactive) ═══"
bash "$HB_SRC/plugin/bootstrap.sh" "$P" >/dev/null 2>&1 </dev/null
check "T1.1 .hb/ created with the 6 files" \
  '[ -f "$HB/tick.sh" ] && [ -f "$HB/gate.sh" ] && [ -f "$HB/hb-next-task.js" ] && [ -f "$HB/dag.json" ] && [ -f "$HB/state.json" ] && [ -f "$HB/events.jsonl" ]'
bash "$HB_SRC/plugin/bootstrap.sh" "$P" >/dev/null 2>&1 </dev/null
check "T1.2 re-bootstrap without tty → clean refusal (no crash)" '[ $? -eq 0 ]'

echo "═══ T2 — gate.sh out-of-the-box (bug #1) ═══"
# v1.3: gate.sh now reprojects state (a passing gate advances the phase), so run
# it on a dedicated throwaway project — the shared $HB must stay pristine for T3+.
PG="$TMP/gate"; bash "$HB_SRC/plugin/bootstrap.sh" "$PG" >/dev/null 2>&1 </dev/null; HBG="$PG/.hb"
out=$(bash "$HBG/gate.sh" GATE_P0 2>&1); rc=$?
check "T2.1 GATE_P0 passes (exit 0)" '[ "$rc" -eq 0 ]'
check "T2.2 the 2 criteria are evaluated (PROJECT_DIR set)" 'echo "$out" | grep -q "2 passed, 0 failed"'
out=$(bash "$HBG/gate.sh" GATE_NONEXISTENT 2>&1); rc=$?
check "T2.3 unknown gate → exit 2 + message" '[ "$rc" -eq 2 ] && echo "$out" | grep -q "Unknown gate"'

echo "═══ T3 — resolver gate-aware (bug #2) ═══"
set_state 's.completed_tasks=["P0T1","P0T2"]'
next=$(node "$HB/hb-next-task.js" "$HB/state.json")
check "T3.1 P0 done, gate NOT passed → gate_pending (not P1T1)" \
  'echo "$next" | grep -q gate_pending && echo "$next" | grep -qv P1T1'
check "T3.2 gate_pending points at GATE_P0" 'echo "$next" | grep -q GATE_P0'
set_state 's.completed_phases=["P0"]'
next=$(node "$HB/hb-next-task.js" "$HB/state.json")
check "T3.3 phase P0 closed → P1T1 served" 'echo "$next" | grep -q P1T1'

echo "═══ T4 — state.json corrupted → auto-repair (v1.3, #2) ═══"
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

echo "═══ T5 — leases & handout lock (v1.3, #5) ═══"
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

echo "═══ T6 — circuit breaker (single alert) ═══"
set_state 's.build_stuck_count=5'
out1=$(tick)
check "T6.1 first tick → build_stuck wake" 'echo "$out1" | grep -q build_stuck && echo "$out1" | grep -q "\"wakeAgent\":true"'
out2=$(tick)
check "T6.2 second tick → SILENCE (stuck_waiting_human)" \
  'echo "$out2" | grep -q stuck_waiting_human && echo "$out2" | grep -q "\"wakeAgent\":false"'
set_state 's.build_stuck_count=0'
tick >/dev/null
check "T6.3 human reset → alert flag cleared" '[ ! -f "$HB/.stuck-alerted" ]'

echo "═══ T7 — gate_blocked ═══"
set_state 's.gate.errors=1'
out=$(tick)
check "T7.1 gate failing → gate_blocked wake" 'echo "$out" | grep -q gate_blocked'
set_state 's.gate.errors=0'

echo "═══ T8 — drift + freeze ═══"
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

echo "═══ T9 — all_done (single alert) ═══"
set_state 's.completed_tasks=["P0T1","P0T2","P1T1","P1T2","P1T3"];s.completed_phases=["P0","P1"]'
out1=$(tick)
check "T9.1 project done → ONE all_done wake (final report)" 'echo "$out1" | grep -q all_done && echo "$out1" | grep -q "\"wakeAgent\":true"'
out2=$(tick)
check "T9.2 subsequent ticks → project_complete, silence" \
  'echo "$out2" | grep -q project_complete && echo "$out2" | grep -q "\"wakeAgent\":false"'

echo "═══ T10 — documentation consistency ═══"
check "T10.1 README documents the tick checks and --freeze" \
  'grep -qi "priority checks" "$HB_SRC/README.md" && grep -q -- "--freeze" "$HB_SRC/README.md"'
check "T10.2 STATUS is current (v1.6) and covers doctor/rot" \
  'grep -q "v1.6" "$HB_SRC/STATUS.md" && grep -qi "rot" "$HB_SRC/STATUS.md"'
check "T10.3 README documents the hb CLI tick protocol" \
  'grep -q "hb.js start" "$HB_SRC/README.md" && grep -qi "tick protocol" "$HB_SRC/README.md"'

echo "═══ T11 — hb-lint (v1.2) ═══"
FX="$HB_SRC/tests/fixtures"
check "T11.1 duplicate IDs detected" '! node "$HB_SRC/plugin/templates/hb-lint.js" "$FX/lint-dup-ids.json"'
check "T11.2 cycle detected" '! node "$HB_SRC/plugin/templates/hb-lint.js" "$FX/lint-cycle.json"'
check "T11.3 broken requires detected" '! node "$HB_SRC/plugin/templates/hb-lint.js" "$FX/lint-missing-ref.json"'
check "T11.4 undefined gate detected" '! node "$HB_SRC/plugin/templates/hb-lint.js" "$FX/lint-undefined-gate.json"'
check "T11.5 phase >8 tasks = warning only" 'node "$HB_SRC/plugin/templates/hb-lint.js" "$FX/lint-big-phase.json"'
check "T11.6 dag template valid" 'node "$HB_SRC/plugin/templates/hb-lint.js" "$HB_SRC/plugin/templates/dag.json"'
check "T11.7 bootstrap lints the dag" 'grep -q hb-lint "$HB_SRC/plugin/bootstrap.sh" && [ -f "$HB/hb-lint.js" ]'

echo "═══ T12 — deadlock & corrupted dag (v1.2) ═══"
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

echo "═══ T13 — hb-report (v1.2) ═══"
check "T13.1 text report generated with phases" 'node "$HB_SRC/plugin/templates/hb-report.js" "$HB" | grep -q "P0"'
check "T13.2 --json report parseable" 'node "$HB_SRC/plugin/templates/hb-report.js" "$HB" --json > "$TMP/r.json" && node -e "JSON.parse(require(\"fs\").readFileSync(\"$TMP/r.json\",\"utf8\"))"'
check "T13.3 incidents counted (T6 stuck visible)" 'node "$HB_SRC/plugin/templates/hb-report.js" "$HB" | grep -q circuit_breaker_tripped'

echo "═══ T14 — hb-viz (v1.2) ═══"
node "$HB_SRC/plugin/templates/hb-viz.js" "$HB" >/dev/null
check "T14.1 dag-view.html generated" '[ -f "$HB/dag-view.html" ]'
check "T14.2 self-contained (no external URL)" '! grep -qE "https?://" "$HB/dag-view.html"'
check "T14.3 task statuses embedded" 'grep -q "t-done" "$HB/dag-view.html" && grep -q P0T1 "$HB/dag-view.html"'

echo "═══ T15 — packaging Claude Code (plugin + install script) ═══"
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

echo "═══ T16 — hb CLI & event-sourced projection (v1.3, #1/#2) ═══"
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

echo "═══ T17 — objective no-progress detection (v1.3, #3) ═══"
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

echo "═══ T18 — gate criteria timeout (v1.3, #4) ═══"
P18="$TMP/p18"; bash "$HB_SRC/plugin/bootstrap.sh" "$P18" >/dev/null 2>&1 </dev/null; H18="$P18/.hb"
node -e "const fs=require(\"fs\");const f=\"$H18/dag.json\";const d=JSON.parse(fs.readFileSync(f,\"utf8\"));d.gates.GATE_SLOW={desc:\"s\",criteria:[{id:\"S\",desc:\"hang\",cmd:\"sleep 10\"}]};fs.writeFileSync(f,JSON.stringify(d,null,2))"
s18=$(date +%s); GATE_TIMEOUT_S=1 bash "$H18/gate.sh" GATE_SLOW >/dev/null 2>&1; rc18=$?; e18=$(date +%s)
check "T18.1 slow criterion → gate blocked (exit 1)" '[ "$rc18" -eq 1 ]'
check "T18.2 fast timeout (< 5s — no frozen tick)" '[ $((e18-s18)) -lt 5 ]'

echo "═══ T19 — leases & bounded concurrency (v1.3, #5) ═══"
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

echo "═══ T20 — mid-session heartbeat (fast reclaim of hung leases) ═══"
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

echo "═══ T21 — hb-lint advisory warnings (v1.4, #1) ═══"
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

echo "═══ T22 — notify hook (v1.4, #2) ═══"
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

echo "═══ T23 — hb ready & parallelism (v1.4, #4) ═══"
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

echo "═══ T24 — adversarial gate / second agent (v1.4, #3) ═══"
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
bash "$H24/gate.sh" GATE_P0 >/dev/null 2>&1; node "$H24/hb.js" review GATE_P0 pass >/dev/null
check "T24.5 review pass → phase advanced (P0 completed)" 'hasP0 "$H24/hb.js"'
P24b="$TMP/p24b"; bash "$HB_SRC/plugin/bootstrap.sh" "$P24b" >/dev/null 2>&1 </dev/null; H24b="$P24b/.hb"
node "$H24b/hb.js" start P0T1 >/dev/null; node "$H24b/hb.js" done P0T1 >/dev/null
node "$H24b/hb.js" start P0T2 >/dev/null; node "$H24b/hb.js" done P0T2 >/dev/null
bash "$H24b/gate.sh" GATE_P0 >/dev/null 2>&1
check "T24.6 back-compat: gate WITHOUT review → advances on deterministic pass alone" 'hasP0 "$H24b/hb.js"'

echo "═══ T25 — DAG schema & per-task timing (v1.4, #5) ═══"
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

echo "═══ T26 — git init at bootstrap & commit-on-gate-pass (v1.4) ═══"
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

echo "═══ T27 — hb doctor : rot detection (v1.5) ═══"
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

echo "═══ T28 — gate.sh --check / --all read-only (v1.5) ═══"
P28="$TMP/p28"; bash "$HB_SRC/plugin/bootstrap.sh" "$P28" >/dev/null 2>&1 </dev/null; H28="$P28/.hb"
E28=$(wc -l < "$H28/events.jsonl")
check "T28.1 --check GATE_P0 (passes) → exit 0" 'bash "$H28/gate.sh" --check GATE_P0 >/dev/null 2>&1'
check "T28.2 --check is READ-ONLY (no event added)" '[ "$(wc -l < "$H28/events.jsonl")" -eq "$E28" ]'
node -e "const fs=require('fs');const f='$H28/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));d.gates.GATE_X={desc:'x',criteria:[{id:'x',desc:'no',cmd:'false'}]};fs.writeFileSync(f,JSON.stringify(d,null,2))"
check "T28.3 --check failing gate → exit 1" '! bash "$H28/gate.sh" --check GATE_X >/dev/null 2>&1'
check "T28.4 --all re-evaluates all gates read-only (no event)" \
  'EB=$(wc -l < "$H28/events.jsonl"); bash "$H28/gate.sh" --all >/dev/null 2>&1; [ "$(wc -l < "$H28/events.jsonl")" -eq "$EB" ]'

echo "═══ T29 — review no-progress → review_stuck (v1.6, thread 2) ═══"
P29="$TMP/p29"; bash "$HB_SRC/plugin/bootstrap.sh" "$P29" >/dev/null 2>&1 </dev/null; H29="$P29/.hb"
node -e "const fs=require('fs');const f='$H29/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));d.phases=[{id:'P0',title:'P',gate_entry:null,gate_exit:'GATE_P0',tasks:[{id:'A',title:'a',requires:[]}]}];d.gates={GATE_P0:{desc:'g',review:{prompt:'r'},criteria:[{id:'g',desc:'ok',cmd:'true'}]}};fs.writeFileSync(f,JSON.stringify(d,null,2))"
node "$H29/hb.js" rebuild >/dev/null
node "$H29/hb.js" start A >/dev/null; node "$H29/hb.js" done A >/dev/null; bash "$H29/gate.sh" GATE_P0 >/dev/null 2>&1
rr29(){ rm -rf "$H29/.lock"; STUCK_TICKS=3 bash "$H29/tick.sh" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>process.stdout.write(JSON.parse(d).data.reason))"; }
rr29 >/dev/null; rr29 >/dev/null; rr29 >/dev/null
o29=$(rr29)
check "T29.1 review unresolved N times → review_stuck" 'test "$o29" = "review_stuck"'
check "T29.2 next tick → silence (review_waiting)" 'test "$(rr29)" = "review_waiting"'
node "$H29/hb.js" review GATE_P0 pass >/dev/null
check "T29.3 hb review pass → phase advanced (P0)" \
  'node "$H29/hb.js" state | node -e "let d=\"\";process.stdin.on(\"data\",c=>d+=c).on(\"end\",()=>process.exit(JSON.parse(d).completed_phases.includes(\"P0\")?0:1))"'

echo "═══ T30 — rot detection : wake at tick (v1.6, thread 1) ═══"
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

echo "═══ T31 — pre-commit rot guard (v1.6, thread 1) ═══"
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

echo "═══ T32 — protocol source of truth (v1.7, #1) ═══"
P32="$TMP/p32"; bash "$HB_SRC/plugin/bootstrap.sh" "$P32" >/dev/null 2>&1 </dev/null; H32="$P32/.hb"
check "T32.1 hb protocol lists all reasons" 'test "$(node "$H32/hb.js" protocol | wc -l)" -ge 12'
check "T32.2 hb protocol <reason> returns that reason" 'node "$H32/hb.js" protocol review_pending | grep -q REFUTE'
check "T32.3 --oneline is a single bare line (no reason prefix)" \
  'test "$(node "$H32/hb.js" protocol gate_blocked --oneline | wc -l)" -eq 1 && ! node "$H32/hb.js" protocol gate_blocked --oneline | grep -q "^gate_blocked:"'
check "T32.4 --md renders a table" \
  'node "$H32/hb.js" protocol --md | grep -q "tick protocol" && node "$H32/hb.js" protocol --md | grep -q next_task'
check "T32.5 unknown reason → exit 1" '! node "$H32/hb.js" protocol nope >/dev/null 2>&1'

echo "═══ T33 — self-describing ticks + PROTOCOL.md (v1.7, #1) ═══"
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

echo "═══ T34 — hb diagnose : computed root-cause (v1.7, #2) ═══"
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

echo "═══ T35 — SessionStart hook (v1.7, #1) ═══"
check "T35.1 hooks.json valid + registers SessionStart" \
  'node -e "const h=require(\"$HB_SRC/plugin/hooks/hooks.json\");process.exit(h.hooks&&h.hooks.SessionStart?0:1)"'
P35="$TMP/p35"; bash "$HB_SRC/plugin/bootstrap.sh" "$P35" >/dev/null 2>&1 </dev/null
check "T35.2 hook fires (prints pointer) on a .hb/ project" \
  'CLAUDE_PROJECT_DIR="$P35" bash "$HB_SRC/plugin/hooks/heartbeat-detect.sh" | grep -qi "HeartBeat"'
check "T35.3 hook is silent on a non-HeartBeat dir" \
  '[ -z "$(CLAUDE_PROJECT_DIR="$TMP" bash "$HB_SRC/plugin/hooks/heartbeat-detect.sh")" ]'

echo ""
echo "═══════════════════════════════════════"
echo "  RESULT: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] && { echo "✅ ALL GREEN"; exit 0; } || { echo "❌ FAILURES"; exit 1; }
