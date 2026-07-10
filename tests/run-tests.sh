#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# HeartBeat v1.1 — Suite de régression
# Couvre les 3 bugs v1.0 + les correctifs de fiabilité v1.1.
# Usage: bash tests/run-tests.sh    (exit 0 = tout vert)
# ══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

HB_SRC="$(cd "$(dirname "$0")/.." && pwd)"
# v1.3: keep objective no-progress detection (#3) from tripping in tests that tick
# repeatedly on a pending task without running an agent. The dedicated no-progress
# test sets STUCK_TICKS low locally.
export STUCK_TICKS=999
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

echo "═══ T1 — bootstrap (non-interactif) ═══"
bash "$HB_SRC/plugin/bootstrap.sh" "$P" >/dev/null 2>&1 </dev/null
check "T1.1 .hb/ créé avec les 6 fichiers" \
  '[ -f "$HB/tick.sh" ] && [ -f "$HB/gate.sh" ] && [ -f "$HB/hb-next-task.js" ] && [ -f "$HB/dag.json" ] && [ -f "$HB/state.json" ] && [ -f "$HB/events.jsonl" ]'
bash "$HB_SRC/plugin/bootstrap.sh" "$P" >/dev/null 2>&1 </dev/null
check "T1.2 re-bootstrap sans tty → refus propre (pas de crash)" '[ $? -eq 0 ]'

echo "═══ T2 — gate.sh out-of-the-box (bug #1) ═══"
# v1.3: gate.sh now reprojects state (a passing gate advances the phase), so run
# it on a dedicated throwaway project — the shared $HB must stay pristine for T3+.
PG="$TMP/gate"; bash "$HB_SRC/plugin/bootstrap.sh" "$PG" >/dev/null 2>&1 </dev/null; HBG="$PG/.hb"
out=$(bash "$HBG/gate.sh" GATE_P0 2>&1); rc=$?
check "T2.1 GATE_P0 passe (exit 0)" '[ "$rc" -eq 0 ]'
check "T2.2 les 2 critères sont évalués (PROJECT_DIR défini)" 'echo "$out" | grep -q "2 passed, 0 failed"'
out=$(bash "$HBG/gate.sh" GATE_INEXISTANTE 2>&1); rc=$?
check "T2.3 gate inconnue → exit 2 + message" '[ "$rc" -eq 2 ] && echo "$out" | grep -q "Unknown gate"'

echo "═══ T3 — resolver gate-aware (bug #2) ═══"
set_state 's.completed_tasks=["P0T1","P0T2"]'
next=$(node "$HB/hb-next-task.js" "$HB/state.json")
check "T3.1 P0 fini, gate NON passée → gate_pending (pas P1T1)" \
  'echo "$next" | grep -q gate_pending && echo "$next" | grep -qv P1T1'
check "T3.2 gate_pending pointe GATE_P0" 'echo "$next" | grep -q GATE_P0'
set_state 's.completed_phases=["P0"]'
next=$(node "$HB/hb-next-task.js" "$HB/state.json")
check "T3.3 phase P0 clôturée → P1T1 servi" 'echo "$next" | grep -q P1T1'

echo "═══ T4 — state.json corrompu → auto-réparation (v1.3, #2) ═══"
cp "$HB/state.json" "$TMP/state.bak"
echo "{broken" > "$HB/state.json"
out=$(tick)
check "T4.1 corruption + log intact → reprojection auto (state.json revalidé, pas de réveil corrupted)" \
  'node -e "JSON.parse(require(\"fs\").readFileSync(\"$HB/state.json\",\"utf8\"))" && ! echo "$out" | grep -q state_corrupted'
mv "$HB/hb.js" "$HB/hb.js.bak"
echo "{broken" > "$HB/state.json"
out=$(tick)
check "T4.2 corruption sans hb.js (projet pré-v1.3) → RÉVEIL state_corrupted (filet)" \
  'echo "$out" | grep -q state_corrupted && echo "$out" | grep -q "\"wakeAgent\":true"'
mv "$HB/hb.js.bak" "$HB/hb.js"
cp "$TMP/state.bak" "$HB/state.json"

echo "═══ T5 — leases & handout lock (v1.3, #5) ═══"
set_state 's.completed_tasks=[];s.completed_phases=[];s.active_tasks=[]'; rm -rf "$HB/leases"
out=$(tick)
check "T5.1 tick avec travail → wakeAgent:true (next_task)" \
  'echo "$out" | grep -q "\"wakeAgent\":true" && echo "$out" | grep -q next_task'
TID=$(echo "$out" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{process.stdout.write(String(JSON.parse(d).data.next_task.id));}catch(e){}})")
check "T5.2 tâche leasée par le tick + handout lock relâché" '[ -d "$HB/leases/$TID" ] && [ ! -d "$HB/.lock" ]'
out=$(tick)
check "T5.3 tâche en cours leasée → at_capacity/busy (pas de 2e agent en parallèle)" \
  'echo "$out" | grep -qE "at_capacity|busy" && echo "$out" | grep -q "\"wakeAgent\":false"'
touch -d "2 hours ago" "$HB/leases/$TID"
out=$(tick)
check "T5.4 lease périmée → reclaim (lease_expired) + tâche re-servie" \
  'grep -q lease_expired "$HB/events.jsonl" && echo "$out" | grep -q "\"wakeAgent\":true"'
rm -rf "$HB/leases"

echo "═══ T6 — circuit breaker (alerte unique) ═══"
set_state 's.build_stuck_count=5'
out1=$(tick)
check "T6.1 premier tick → réveil build_stuck" 'echo "$out1" | grep -q build_stuck && echo "$out1" | grep -q "\"wakeAgent\":true"'
out2=$(tick)
check "T6.2 second tick → SILENCE (stuck_waiting_human)" \
  'echo "$out2" | grep -q stuck_waiting_human && echo "$out2" | grep -q "\"wakeAgent\":false"'
set_state 's.build_stuck_count=0'
tick >/dev/null
check "T6.3 reset humain → flag d'alerte levé" '[ ! -f "$HB/.stuck-alerted" ]'

echo "═══ T7 — gate_blocked ═══"
set_state 's.gate.errors=1'
out=$(tick)
check "T7.1 gate en échec → réveil gate_blocked" 'echo "$out" | grep -q gate_blocked'
set_state 's.gate.errors=0'

echo "═══ T8 — drift + freeze ═══"
mkdir -p "$P/core"; echo "module.exports=1;" > "$P/core/a.js"
sed -i 's|^WATCH_PATHS=.*|WATCH_PATHS="$PROJECT_DIR/core/*.js"|' "$HB/tick.sh"
tick >/dev/null
check "T8.1 baseline auto-gelée au premier run" '[ -f "$HB/architecture.hash" ]'
echo "// drift" >> "$P/core/a.js"
out=$(tick)
check "T8.2 modification non sanctionnée → réveil unsanctioned_drift" 'echo "$out" | grep -q unsanctioned_drift'
bash "$HB/tick.sh" --freeze >/dev/null
out=$(tick)
check "T8.3 après --freeze → plus de drift" 'echo "$out" | grep -qv unsanctioned_drift'

echo "═══ T9 — all_done (alerte unique) ═══"
set_state 's.completed_tasks=["P0T1","P0T2","P1T1","P1T2","P1T3"];s.completed_phases=["P0","P1"]'
out1=$(tick)
check "T9.1 projet fini → UN réveil all_done (rapport final)" 'echo "$out1" | grep -q all_done && echo "$out1" | grep -q "\"wakeAgent\":true"'
out2=$(tick)
check "T9.2 ticks suivants → project_complete, silence" \
  'echo "$out2" | grep -q project_complete && echo "$out2" | grep -q "\"wakeAgent\":false"'

echo "═══ T10 — cohérence documentation ═══"
check "T10.1 README documente les 6 checks et --freeze" \
  'grep -q "6 vérifications" "$HB_SRC/README.md" && grep -q -- "--freeze" "$HB_SRC/README.md"'
check "T10.2 STATUS en v1.1, ordre des checks aligné sur tick.sh" \
  'grep -q "v1.2" "$HB_SRC/STATUS.md" && grep -q "Gate errors" "$HB_SRC/STATUS.md"'
check "T10.3 README : libération du lock par l'agent documentée" \
  'grep -q "rm -rf .hb/.lock" "$HB_SRC/README.md"'

echo "═══ T11 — hb-lint (v1.2) ═══"
FX="$HB_SRC/tests/fixtures"
check "T11.1 IDs dupliqués détectés" '! node "$HB_SRC/plugin/templates/hb-lint.js" "$FX/lint-dup-ids.json"'
check "T11.2 cycle détecté" '! node "$HB_SRC/plugin/templates/hb-lint.js" "$FX/lint-cycle.json"'
check "T11.3 requires cassé détecté" '! node "$HB_SRC/plugin/templates/hb-lint.js" "$FX/lint-missing-ref.json"'
check "T11.4 gate non définie détectée" '! node "$HB_SRC/plugin/templates/hb-lint.js" "$FX/lint-undefined-gate.json"'
check "T11.5 phase >8 tâches = warning seulement" 'node "$HB_SRC/plugin/templates/hb-lint.js" "$FX/lint-big-phase.json"'
check "T11.6 dag template valide" 'node "$HB_SRC/plugin/templates/hb-lint.js" "$HB_SRC/plugin/templates/dag.json"'
check "T11.7 bootstrap linte le dag" 'grep -q hb-lint "$HB_SRC/plugin/bootstrap.sh" && [ -f "$HB/hb-lint.js" ]'

echo "═══ T12 — deadlock & dag corrompu (v1.2) ═══"
next=$(node "$HB_SRC/plugin/templates/hb-next-task.js" "$FX/deadlock-missing-ref/state.json")
check "T12.1 requires cassé → deadlock diagnostiqué (dag_invalid)" 'echo "$next" | grep -q deadlock && echo "$next" | grep -q dag_invalid'
next=$(node "$HB_SRC/plugin/templates/hb-next-task.js" "$FX/deadlock-orphan/state.json")
check "T12.2 tâche active orpheline → active_orphan" 'echo "$next" | grep -q active_orphan'
P2="$TMP/proj2"; bash "$HB_SRC/plugin/bootstrap.sh" "$P2" >/dev/null 2>&1 </dev/null
HB2="$P2/.hb"
node -e "const fs=require('fs');const f='$HB2/dag.json';const d=JSON.parse(fs.readFileSync(f,'utf8'));d.phases[0].tasks[1].requires=['GHOST'];fs.writeFileSync(f,JSON.stringify(d,null,2));"
node -e "const fs=require('fs');const f='$HB2/state.json';const s=JSON.parse(fs.readFileSync(f,'utf8'));s.completed_tasks=['P0T1'];fs.writeFileSync(f,JSON.stringify(s,null,2));"
rm -rf "$HB2/.lock"; out1=$(bash "$HB2/tick.sh")
check "T12.3 tick → UN réveil deadlock" 'echo "$out1" | grep -q "\"reason\":\"deadlock\"" && echo "$out1" | grep -q "\"wakeAgent\":true"'
rm -rf "$HB2/.lock"; out2=$(bash "$HB2/tick.sh")
check "T12.4 second tick → deadlock_waiting, silence" 'echo "$out2" | grep -q deadlock_waiting && echo "$out2" | grep -q "\"wakeAgent\":false"'
echo "{broken" > "$HB2/dag.json"
rm -rf "$HB2/.lock"; out=$(bash "$HB2/tick.sh")
check "T12.5 dag.json corrompu → réveil dag_corrupted" 'echo "$out" | grep -q dag_corrupted'

echo "═══ T13 — hb-report (v1.2) ═══"
check "T13.1 rapport texte généré avec phases" 'node "$HB_SRC/plugin/templates/hb-report.js" "$HB" | grep -q "P0"'
check "T13.2 rapport --json parseable" 'node "$HB_SRC/plugin/templates/hb-report.js" "$HB" --json > "$TMP/r.json" && node -e "JSON.parse(require(\"fs\").readFileSync(\"$TMP/r.json\",\"utf8\"))"'
check "T13.3 incidents comptés (stuck du T6 visible)" 'node "$HB_SRC/plugin/templates/hb-report.js" "$HB" | grep -q circuit_breaker_tripped'

echo "═══ T14 — hb-viz (v1.2) ═══"
node "$HB_SRC/plugin/templates/hb-viz.js" "$HB" >/dev/null
check "T14.1 dag-view.html généré" '[ -f "$HB/dag-view.html" ]'
check "T14.2 autonome (aucune URL externe)" '! grep -qE "https?://" "$HB/dag-view.html"'
check "T14.3 statuts des tâches embarqués" 'grep -q "t-done" "$HB/dag-view.html" && grep -q P0T1 "$HB/dag-view.html"'

echo "═══ T15 — packaging Claude Code (plugin + install script) ═══"
check "T15.1 plugin.json valide + name=heartbeat" \
  'node -e "const m=JSON.parse(require(String.raw\`fs\`).readFileSync(process.argv[1]));process.exit(m.name===\"heartbeat\"?0:1)" "$HB_SRC/plugin/.claude-plugin/plugin.json"'
check "T15.2 marketplace.json valide + liste heartbeat" \
  'node -e "const m=JSON.parse(require(String.raw\`fs\`).readFileSync(process.argv[1]));process.exit(m.plugins.some(p=>p.name===\"heartbeat\")?0:1)" "$HB_SRC/.claude-plugin/marketplace.json"'
check "T15.3 skill présent avec frontmatter name" \
  '[ -f "$HB_SRC/plugin/skills/heartbeat/SKILL.md" ] && head -5 "$HB_SRC/plugin/skills/heartbeat/SKILL.md" | grep -q "^name: heartbeat"'
check "T15.4 aucun chemin /workspace/group dans les fichiers plugin" \
  '! grep -Rq "/workspace/group" "$HB_SRC/plugin" "$HB_SRC/.claude-plugin" "$HB_SRC/CLAUDE-MD-SNIPPET.md"'
check "T15.5 scheduling adapté aux routines (pas de schedule_task dans le skill)" \
  '! grep -q "schedule_task" "$HB_SRC/plugin/skills/heartbeat/SKILL.md" && grep -q "/schedule routine" "$HB_SRC/plugin/skills/heartbeat/SKILL.md"'
check "T15.6 install.sh → sandbox HOME installe skill + tooling + smoke" \
  'SBX=$(mktemp -d); HOME="$SBX" bash "$HB_SRC/scripts/install.sh" >/dev/null 2>&1 && [ -f "$SBX/.claude/skills/heartbeat/SKILL.md" ] && [ -f "$SBX/.claude/heartbeat/bootstrap.sh" ]; rc=$?; rm -rf "$SBX"; [ $rc -eq 0 ]'
check "T15.7 skill installé par script a des chemins concrets (var substituée)" \
  'SBX=$(mktemp -d); HOME="$SBX" bash "$HB_SRC/scripts/install.sh" >/dev/null 2>&1; ! grep -q "CLAUDE_PLUGIN_ROOT" "$SBX/.claude/skills/heartbeat/SKILL.md"; rc=$?; rm -rf "$SBX"; [ $rc -eq 0 ]'

echo "═══ T16 — hb CLI & projection événementielle (v1.3, #1/#2) ═══"
P16="$TMP/p16"; bash "$HB_SRC/plugin/bootstrap.sh" "$P16" >/dev/null 2>&1 </dev/null; H16="$P16/.hb"
node "$H16/hb.js" start P0T1 >/dev/null; node "$H16/hb.js" done P0T1 >/dev/null
check "T16.1 hb done → tâche dans completed_tasks (dérivé du log)" 'node "$H16/hb.js" state | grep -q "\"P0T1\""'
node "$H16/hb.js" fail P0T2 >/dev/null
check "T16.2 hb fail → build_stuck_count dérivé incrémenté" \
  'node "$H16/hb.js" state | node -e "let d=\"\";process.stdin.on(\"data\",c=>d+=c).on(\"end\",()=>process.exit(JSON.parse(d).build_stuck_count>=1?0:1))"'
node "$H16/hb.js" rebuild >/dev/null; A16=$(node -e "const s=require(\"$H16/state.json\");delete s.last_updated;console.log(JSON.stringify(s))")
node "$H16/hb.js" rebuild >/dev/null; B16=$(node -e "const s=require(\"$H16/state.json\");delete s.last_updated;console.log(JSON.stringify(s))")
check "T16.3 rebuild déterministe (state = projection pure du log)" '[ "$A16" = "$B16" ]'
echo "{broken" > "$H16/state.json"
check "T16.4 state corrompu → hb rebuild répare depuis le log" \
  'node "$H16/hb.js" rebuild >/dev/null && node -e "JSON.parse(require(\"fs\").readFileSync(\"$H16/state.json\",\"utf8\"))"'
P16b="$TMP/p16b"; bash "$HB_SRC/plugin/bootstrap.sh" "$P16b" >/dev/null 2>&1 </dev/null; H16b="$P16b/.hb"
node -e "const fs=require(\"fs\");const f=\"$H16b/state.json\";const s=JSON.parse(fs.readFileSync(f,\"utf8\"));s.completed_tasks=[\"P0T1\"];fs.writeFileSync(f,JSON.stringify(s,null,2))"
node "$H16b/hb.js" import >/dev/null
check "T16.5 migration legacy (hb import) → log reconstruit (P0T1 done)" 'node "$H16b/hb.js" state | grep -q "\"P0T1\""'

echo "═══ T17 — détection no-progress objective (v1.3, #3) ═══"
P17="$TMP/p17"; bash "$HB_SRC/plugin/bootstrap.sh" "$P17" >/dev/null 2>&1 </dev/null; H17="$P17/.hb"
# simule un agent réveillé qui ne progresse pas ET libère sa lease → re-servi chaque tick
t17(){ rm -rf "$H17/.lock" "$H17/leases"; STUCK_TICKS=3 bash "$H17/tick.sh"; }
t17 >/dev/null; t17 >/dev/null; t17 >/dev/null
o17=$(t17)
check "T17.1 N réveils sans progrès → build_stuck (signal no_progress)" \
  'echo "$o17" | grep -q build_stuck && echo "$o17" | grep -q no_progress'
o17b=$(t17)
check "T17.2 réveil suivant → SILENCE (stuck_waiting_human)" \
  'echo "$o17b" | grep -q stuck_waiting_human && echo "$o17b" | grep -q "\"wakeAgent\":false"'
node "$H17/hb.js" start P0T1 >/dev/null; node "$H17/hb.js" done P0T1 >/dev/null
o17c=$(t17)
check "T17.3 progrès (hb done) → compteur remis à zéro, tick reprend" \
  'echo "$o17c" | grep -q next_task && [ ! -f "$H17/.noprogress-alerted" ]'

echo "═══ T18 — timeout des critères de gate (v1.3, #4) ═══"
P18="$TMP/p18"; bash "$HB_SRC/plugin/bootstrap.sh" "$P18" >/dev/null 2>&1 </dev/null; H18="$P18/.hb"
node -e "const fs=require(\"fs\");const f=\"$H18/dag.json\";const d=JSON.parse(fs.readFileSync(f,\"utf8\"));d.gates.GATE_SLOW={desc:\"s\",criteria:[{id:\"S\",desc:\"hang\",cmd:\"sleep 10\"}]};fs.writeFileSync(f,JSON.stringify(d,null,2))"
s18=$(date +%s); GATE_TIMEOUT_S=1 bash "$H18/gate.sh" GATE_SLOW >/dev/null 2>&1; rc18=$?; e18=$(date +%s)
check "T18.1 critère lent → gate bloquée (exit 1)" '[ "$rc18" -eq 1 ]'
check "T18.2 timeout rapide (< 5s — pas de tick figé)" '[ $((e18-s18)) -lt 5 ]'

echo "═══ T19 — leases & concurrence bornée (v1.3, #5) ═══"
P19="$TMP/p19"; bash "$HB_SRC/plugin/bootstrap.sh" "$P19" >/dev/null 2>&1 </dev/null; H19="$P19/.hb"
node -e "const fs=require(\"fs\");const f=\"$H19/dag.json\";const d=JSON.parse(fs.readFileSync(f,\"utf8\"));d.phases=[{id:'P0',title:'P',gate_entry:null,gate_exit:'GATE_P0',tasks:[{id:'A',title:'a',requires:[]},{id:'B',title:'b',requires:[]},{id:'C',title:'c',requires:[]}]}];d.gates={GATE_P0:{desc:'g',criteria:[{id:'g',desc:'ok',cmd:'true'}]}};fs.writeFileSync(f,JSON.stringify(d,null,2))"
node -e "const fs=require(\"fs\");const f=\"$H19/state.json\";const s=JSON.parse(fs.readFileSync(f,\"utf8\"));s.completed_tasks=[];s.completed_phases=[];s.active_tasks=[];fs.writeFileSync(f,JSON.stringify(s,null,2))"
t19(){ rm -rf "$H19/.lock"; STUCK_TICKS=999 HB_MAX_CONCURRENCY=2 bash "$H19/tick.sh"; }
t19 >/dev/null; t19 >/dev/null; o19=$(t19)
check "T19.1 cap=2 → 2 tâches DISTINCTES leasées en parallèle" '[ "$(ls "$H19/leases" | wc -l)" -eq 2 ]'
check "T19.2 3e tâche prête mais cap atteint → at_capacity" 'echo "$o19" | grep -q at_capacity'
check "T19.3 pas de double-claim (mkdir lease atomique)" '! mkdir "$H19/leases/A" 2>/dev/null'
f19=$(ls "$H19/leases" | head -1); node "$H19/hb.js" done "$f19" >/dev/null
check "T19.4 hb done libère un slot → tâche restante servie" 'o=$(t19); echo "$o" | grep -q next_task'

echo "═══ T20 — heartbeat mi-session (reclaim rapide des leases pendues) ═══"
P20="$TMP/p20"; bash "$HB_SRC/plugin/bootstrap.sh" "$P20" >/dev/null 2>&1 </dev/null; H20="$P20/.hb"
mkdir -p "$H20/leases/P0T1"
node "$H20/hb.js" heartbeat P0T1 >/dev/null
check "T20.1 hb heartbeat → marqueur beat créé" '[ -f "$H20/leases/P0T1/beat" ]'
touch -d "1 hour ago" "$H20/leases/P0T1/beat"
rm -rf "$H20/.lock"; HEARTBEAT_STALE_S=120 bash "$H20/tick.sh" >/dev/null 2>&1
check "T20.2 beat périmé (>HEARTBEAT_STALE_S, <LOCK_STALE_S) → reclaim rapide" \
  'grep lease_expired "$H20/events.jsonl" | grep -q P0T1'
mkdir -p "$H20/leases/P0T3"; node "$H20/hb.js" heartbeat P0T3 >/dev/null
rm -rf "$H20/.lock"; HEARTBEAT_STALE_S=120 bash "$H20/tick.sh" >/dev/null 2>&1
check "T20.3 beat frais → lease maintenue en vie" '[ -d "$H20/leases/P0T3" ]'
mkdir -p "$H20/leases/P0T4"
rm -rf "$H20/.lock"; HEARTBEAT_STALE_S=120 bash "$H20/tick.sh" >/dev/null 2>&1
check "T20.4 lease sans beat & récente → conservée (fallback LOCK_STALE_S, pas de faux reclaim)" \
  '[ -d "$H20/leases/P0T4" ] && ! ( grep lease_expired "$H20/events.jsonl" | grep -q P0T4 )'

echo ""
echo "═══════════════════════════════════════"
echo "  RÉSULTAT : $PASS passés, $FAIL échoués"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] && { echo "✅ SUITE VERTE"; exit 0; } || { echo "❌ ÉCHECS"; exit 1; }
