#!/usr/bin/env node
/**
 * hb-report.js — Rapport d'avancement HeartBeat (v1.2)
 *
 * Lit dag.json + state.json + events.jsonl et produit :
 *   - avancement global et par phase (statut : done / in_progress / ready / locked)
 *   - statistiques de gates (passées / échecs)
 *   - incidents (corruptions, drift, stale locks, circuit breaker, deadlocks)
 *   - durées de phase (jalons : initialized → gate_passed → gate_passed…)
 *
 * Convention v1.2 : l'agent appende {"ts","event":"task_done","task":"ID"} dans
 * events.jsonl à chaque tâche terminée — le rapport les exploite si présents.
 *
 * Usage : node hb-report.js <hb-dir> [--json]
 */
'use strict';
const fs = require('fs');
const path = require('path');

const dir    = process.argv[2];
const asJson = process.argv.includes('--json');
if (!dir) { console.error('Usage: hb-report.js <hb-dir> [--json]'); process.exit(2); }

const J = f => JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
let dag, state;
try { dag = J('dag.json'); state = J('state.json'); }
catch (e) { console.error(`Cannot read dag/state: ${e.message}`); process.exit(1); }

let events = [];
try {
  events = fs.readFileSync(path.join(dir, 'events.jsonl'), 'utf8')
    .split('\n').filter(Boolean)
    .map(l => { try { return JSON.parse(l); } catch (e) { return null; } })
    .filter(Boolean);
} catch (e) { /* pas d'events = rapport partiel */ }

const done   = new Set(state.completed_tasks ?? []);
const active = new Set(state.active_tasks ?? []);
const cph    = new Set(state.completed_phases ?? []);
const gatePassed = new Set();
for (const p of (dag.phases ?? [])) if (cph.has(p.id) && p.gate_exit) gatePassed.add(p.gate_exit);

const phases = (dag.phases ?? []).map(p => {
  const ts = p.tasks ?? [];
  const d  = ts.filter(t => done.has(t.id)).length;
  const locked = !!(p.gate_entry && !gatePassed.has(p.gate_entry));
  const status = cph.has(p.id) ? 'done'
    : locked ? 'locked'
    : (d > 0 || ts.some(t => active.has(t.id))) ? 'in_progress'
    : 'ready';
  return { id: p.id, title: p.title ?? p.id, done: d, total: ts.length, status, gate_exit: p.gate_exit ?? null };
});

const totalTasks = phases.reduce((a, p) => a + p.total, 0);
const doneTasks  = phases.reduce((a, p) => a + p.done,  0);

const gates = {};
for (const e of events) {
  if (e.event === 'gate_passed' || e.event === 'gate_failed') {
    gates[e.gate] ??= { passed: 0, failed: 0, last: null };
    gates[e.gate][e.event === 'gate_passed' ? 'passed' : 'failed']++;
    gates[e.gate].last = e.event;
  }
}

const INCIDENTS = ['state_corrupted', 'dag_corrupted', 'unsanctioned_drift',
                   'stale_lock_broken', 'circuit_breaker_tripped', 'deadlock_detected'];
const incidents = {};
for (const e of events) if (INCIDENTS.includes(e.event)) incidents[e.event] = (incidents[e.event] ?? 0) + 1;

const ms = t => new Date(t).getTime();
const milestones = events.filter(e => e.event === 'initialized' || e.event === 'gate_passed');
const durations = [];
for (let i = 1; i < milestones.length; i++) {
  if (milestones[i].event === 'gate_passed') {
    durations.push({ gate: milestones[i].gate, seconds: Math.round((ms(milestones[i].ts) - ms(milestones[i - 1].ts)) / 1000) });
  }
}

// v1.4: per-task durations (task_started → task_done)
const startedAt = {};
const taskDurations = [];
for (const e of events) {
  if (e.event === 'task_started' && e.task) startedAt[e.task] = e.ts;
  else if (e.event === 'task_done' && e.task && startedAt[e.task]) {
    taskDurations.push({ task: e.task, seconds: Math.round((ms(e.ts) - ms(startedAt[e.task])) / 1000) });
    delete startedAt[e.task];
  }
}
taskDurations.sort((a, b) => b.seconds - a.seconds);

const report = {
  project: dag._meta?.project ?? path.basename(path.dirname(path.resolve(dir))),
  progress: { done: doneTasks, total: totalTasks, pct: totalTasks ? Math.round(100 * doneTasks / totalTasks) : 0 },
  phases, gates, incidents,
  phase_durations: durations,
  task_durations: taskDurations,
  task_done_events: events.filter(e => e.event === 'task_done').length,
  generated: new Date().toISOString(),
};

if (asJson) { console.log(JSON.stringify(report, null, 2)); process.exit(0); }

const hms = s => s >= 3600 ? `${Math.floor(s / 3600)}h${Math.floor((s % 3600) / 60)}m`
             : s >= 60   ? `${Math.floor(s / 60)}m${s % 60}s` : `${s}s`;
const icon = { done: '✅', in_progress: '🔧', ready: '▶️ ', locked: '🔒' };

console.log(`═══ HeartBeat Report — ${report.project} ═══`);
console.log(`Avancement : ${doneTasks}/${totalTasks} tâches (${report.progress.pct}%)`);
console.log('');
console.log('Phases :');
for (const p of phases) {
  console.log(`  ${icon[p.status]} ${p.id} ${p.title} — ${p.done}/${p.total}${p.gate_exit ? `  [gate: ${p.gate_exit}]` : ''}`);
}
if (Object.keys(gates).length) {
  console.log(''); console.log('Gates :');
  for (const [g, v] of Object.entries(gates)) console.log(`  ${g}: ${v.passed} passée(s), ${v.failed} échec(s)`);
}
if (durations.length) {
  console.log(''); console.log('Durées de phase (jalon → gate) :');
  for (const d of durations) console.log(`  ${d.gate}: ${hms(d.seconds)}`);
}
if (taskDurations.length) {
  console.log(''); console.log('Tâches les plus longues (start → done) :');
  for (const d of taskDurations.slice(0, 5)) console.log(`  ${d.task}: ${hms(d.seconds)}`);
}
console.log('');
console.log(Object.keys(incidents).length
  ? `Incidents : ${Object.entries(incidents).map(([k, v]) => `${k}×${v}`).join(', ')}`
  : 'Incidents : aucun');
