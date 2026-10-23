#!/usr/bin/env node
/**
 * hb-report.js — HeartBeat progress report
 *
 * Reads dag.json + state.json + events.jsonl and produces:
 *   - overall and per-phase progress (status: done / in_progress / ready / locked)
 *   - gate stats (passed / failed)
 *   - incidents (corruptions, drift, stale locks, circuit breaker, deadlocks)
 *   - phase durations (milestones: initialized → gate_passed → gate_passed…)
 *   - per-task durations (task_started → task_done)
 *
 * Usage: node hb-report.js <hb-dir> [--json]
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
  const status = p.parked ? 'parked'
    : cph.has(p.id) ? 'done'
    : locked ? 'locked'
    : (d > 0 || ts.some(t => active.has(t.id))) ? 'in_progress'
    : 'ready';
  return { id: p.id, title: p.title ?? p.id, done: d, total: ts.length, status, gate_exit: p.gate_exit ?? null,
           parked: !!p.parked };
});

// A parked phase is out of the plan's live surface: excluded from the progress denominator
// (and numerator) but never hidden — listed in `parked` and flagged per-phase.
const livePhases = phases.filter(p => !p.parked);
const totalTasks = livePhases.reduce((a, p) => a + p.total, 0);
const doneTasks  = livePhases.reduce((a, p) => a + p.done,  0);

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

// What the refuter ACTUALLY did this run, from the event log (truth) — python twin: report.refuter_impact.
// review_failed = a CATCH (found a hole → gate_blocked); review_passed = a clear. Lens = gate review.profile.
// Records what was caught, never what was missed (unknowable). Summary structurally identical to python.
function refuterImpact(evs, d) {
  const g0 = (d && d.gates) || {};
  const per = {};
  for (const e of evs) {
    if (e.event !== 'review_failed' && e.event !== 'review_passed') continue;
    if (!e.gate) continue;
    (per[e.gate] ??= { caught: 0, cleared: 0, findings: [], models: {} });
    // Per-model breakdown — the capability axis of "did the refuter earn its keep?".
    // Null/absent model buckets under "(none)" (one mirrored convention, node ≡ python).
    const mk = e.model || '(none)';
    (per[e.gate].models[mk] ??= { caught: 0, cleared: 0 });
    if (e.event === 'review_failed') { per[e.gate].caught++; per[e.gate].models[mk].caught++; per[e.gate].findings.push(e.note || ''); }
    else { per[e.gate].cleared++; per[e.gate].models[mk].cleared++; }
  }
  const outGates = Object.keys(per).sort().map(g => ({
    gate: g, profile: ((g0[g] || {}).review || {}).profile ?? null,
    caught: per[g].caught, cleared: per[g].cleared, findings: per[g].findings,
    models: per[g].models,
  }));
  return { caught: outGates.reduce((a, x) => a + x.caught, 0),
           cleared: outGates.reduce((a, x) => a + x.cleared, 0), gates: outGates };
}

const report = {
  project: dag._meta?.project ?? path.basename(path.dirname(path.resolve(dir))),
  progress: { done: doneTasks, total: totalTasks, pct: totalTasks ? Math.round(100 * doneTasks / totalTasks) : 0 },
  parked: phases.filter(p => p.parked).map(p => p.id),
  phases, gates, incidents,
  phase_durations: durations,
  task_durations: taskDurations,
  task_done_events: events.filter(e => e.event === 'task_done').length,
  refuters: refuterImpact(events, dag),
  generated: new Date().toISOString(),
};

if (asJson) { console.log(JSON.stringify(report, null, 2)); process.exit(0); }

const hms = s => s >= 3600 ? `${Math.floor(s / 3600)}h${Math.floor((s % 3600) / 60)}m`
             : s >= 60   ? `${Math.floor(s / 60)}m${s % 60}s` : `${s}s`;
const icon = { done: '✅', in_progress: '🔧', ready: '▶️ ', locked: '🔒', parked: '⏸ ' };

console.log(`═══ HeartBeat Report — ${report.project} ═══`);
console.log(`Progress: ${doneTasks}/${totalTasks} tasks (${report.progress.pct}%)`);
console.log('');
console.log('Phases:');
const regateNote = (g) => { const r = require('./hb.js').regateBlocks((dag.gates || {})[g]); return r ? `  ⛔ revised — rearm pending (by ${r.actor || '?'}: ${r.reason || ''})` : ''; };   // regate-guard: report — a revision is never silent
const detachNote = (id) => { const rp = (dag.phases || []).find(x => x.id === id); return (rp && Object.prototype.hasOwnProperty.call(rp, 'detached_from')) ? `  ⟂ detached from ${rp.detached_from} (by ${rp.detached_by || '?'}: ${rp.detached_reason || ''})` : ''; };   // detach-guard: report — a retracted claim is never silent
for (const p of phases) {
  let rn = '';
  if (p.gate_exit) rn = regateNote(p.gate_exit);   // regate-guard: report
  let dn = '';
  dn = detachNote(p.id);   // detach-guard: report
  console.log(`  ${icon[p.status]} ${p.id} ${p.title} — ${p.done}/${p.total}${p.gate_exit ? `  [gate: ${p.gate_exit}]${rn}` : ''}${dn}`);
}
if (Object.keys(gates).length) {
  console.log(''); console.log('Gates:');
  for (const [g, v] of Object.entries(gates)) console.log(`  ${g}: ${v.passed} passed, ${v.failed} failed`);
}
if (durations.length) {
  console.log(''); console.log('Phase durations (milestone → gate):');
  for (const d of durations) console.log(`  ${d.gate}: ${hms(d.seconds)}`);
}
if (taskDurations.length) {
  console.log(''); console.log('Longest tasks (start → done):');
  for (const d of taskDurations.slice(0, 5)) console.log(`  ${d.task}: ${hms(d.seconds)}`);
}
if (report.refuters.caught || report.refuters.cleared) {
  console.log(''); console.log(`Refuter impact: caught ${report.refuters.caught} hole(s) across ${report.refuters.caught + report.refuters.cleared} review(s)`);
  for (const g of report.refuters.gates) {
    console.log(`  ${g.gate} [${g.profile || '(default prompt)'}]: caught ${g.caught}, cleared ${g.cleared}`);
    for (const [m, mc] of Object.entries(g.models || {}).sort())
      console.log(`     · ${m}: caught ${mc.caught}, cleared ${mc.cleared}`);
    for (const f of g.findings) console.log(`     ✗ ${(f.split('\n')[0] || '').slice(0, 100)}`);
  }
}
console.log('');
console.log(Object.keys(incidents).length
  ? `Incidents: ${Object.entries(incidents).map(([k, v]) => `${k}×${v}`).join(', ')}`
  : 'Incidents: none');
