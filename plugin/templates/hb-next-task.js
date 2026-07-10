#!/usr/bin/env node
/**
 * hb-next-task.js — HeartBeat gate-aware next-task resolver (v1.1)
 *
 * Une phase n'est éligible que si sa gate_entry a été passée, c.-à-d. si la
 * phase dont gate_exit === gate_entry figure dans state.completed_phases.
 * → Impossible de servir une tâche de P1 tant que GATE_P0 n'est pas validée.
 *
 * Sorties (JSON compact sur stdout) :
 *   { id, phase, title, description, requires }  → tâche actionnable
 *   { type:"gate_pending", phase, gate }         → tâches de la phase finies,
 *                                                   gate à passer / phase à clôturer
 *   { type:"all_done" }                          → toutes les phases complétées
 *   null                                         → rien d'actionnable
 *
 * Usage: node hb-next-task.js <path/to/state.json>
 *        (dag.json attendu dans le même répertoire)
 */

'use strict';

const fs   = require('fs');
const path = require('path');

const stateFile = process.argv[2];
if (!stateFile) {
  process.stderr.write('Usage: hb-next-task.js <path/to/state.json>\n');
  process.stdout.write('null\n');
  process.exit(0);
}

let state, dag;
const hbDir = path.dirname(stateFile);

try {
  state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
} catch (e) {
  process.stderr.write(`Cannot read state.json: ${e.message}\n`);
  process.stdout.write('null\n');
  process.exit(0);
}

try {
  dag = JSON.parse(fs.readFileSync(path.join(hbDir, 'dag.json'), 'utf8'));
} catch (e) {
  process.stderr.write(`Cannot read dag.json: ${e.message}\n`);
  process.stdout.write('null\n');
  process.exit(0);
}

const phases          = dag.phases ?? [];
const completedPhases = new Set(state.completed_phases ?? []);

// Task status lookup
const taskStatus = {};
for (const t of (state.completed_tasks ?? [])) taskStatus[t] = 'done';
for (const t of (state.active_tasks    ?? [])) taskStatus[t] = 'active';
// v1.3 (#5): on-disk leases are runtime claims — exclude leased tasks from
// handout so overlapping ticks/agents are never served the same task.
const leased = new Set();
try {
  for (const t of fs.readdirSync(path.join(hbDir, 'leases'))) {
    leased.add(t);
    if (!taskStatus[t]) taskStatus[t] = 'leased';
  }
} catch (e) { /* no leases dir yet */ }

// Une gate est "passée" si la phase qui la porte en gate_exit est complétée
const gatePassed = new Set();
for (const p of phases) {
  if (completedPhases.has(p.id) && p.gate_exit) gatePassed.add(p.gate_exit);
}

for (const phase of phases) {
  if (completedPhases.has(phase.id)) continue;

  // Phase verrouillée tant que sa gate d'entrée n'est pas passée
  if (phase.gate_entry && !gatePassed.has(phase.gate_entry)) continue;

  const tasks = phase.tasks ?? [];

  for (const task of tasks) {
    const status = taskStatus[task.id] ?? 'pending';
    if (status !== 'pending') continue;

    const requires = task.requires ?? [];
    if (!requires.every(reqId => taskStatus[reqId] === 'done')) continue;

    process.stdout.write(JSON.stringify({
      id:          task.id,
      phase:       phase.id,
      title:       task.title ?? task.id,
      description: task.description ?? '',
      requires:    requires,
    }) + '\n');
    process.exit(0);
  }

  // Toutes les tâches faites mais phase pas clôturée → la gate doit tourner
  if (tasks.length > 0 && tasks.every(t => taskStatus[t.id] === 'done')) {
    process.stdout.write(JSON.stringify({
      type:  'gate_pending',
      phase: phase.id,
      gate:  phase.gate_exit ?? null,
    }) + '\n');
    process.exit(0);
  }
}

// ── v1.2 — plus de null silencieux : diagnostic de deadlock ──────────────────
if (phases.length === 0) {
  process.stdout.write('null\n');
  process.exit(0);
}
if (phases.every(p => completedPhases.has(p.id))) {
  process.stdout.write(JSON.stringify({ type: 'all_done' }) + '\n');
  process.exit(0);
}

// Rien d'actionnable et projet non fini → deadlock. On diagnostique :
function deadlock(cause, detail) {
  process.stdout.write(JSON.stringify({ type: 'deadlock', cause, detail }) + '\n');
  process.exit(0);
}

// 0. v1.3 (#5): si les seules tâches qui bloqueraient la progression sont
//    LEASÉES (en cours dans une autre session), le projet est OCCUPÉ, pas bloqué.
//    → 'busy' (le tick dort), et non un faux deadlock.
const inFlight = [];
for (const phase of phases) {
  if (completedPhases.has(phase.id)) continue;
  if (phase.gate_entry && !gatePassed.has(phase.gate_entry)) continue;
  for (const t of (phase.tasks ?? [])) if (leased.has(t.id)) inFlight.push(t.id);
}
if (inFlight.length) {
  process.stdout.write(JSON.stringify({ type: 'busy', in_flight: inFlight }) + '\n');
  process.exit(0);
}

// 1. Tâches actives orphelines dans les phases déverrouillées (agent mort,
//    lock périmé cassé, mais la tâche jamais resservie) — l'agent doit les
//    remettre en pending ou les reprendre.
const orphans = [];
for (const phase of phases) {
  if (completedPhases.has(phase.id)) continue;
  if (phase.gate_entry && !gatePassed.has(phase.gate_entry)) continue;
  for (const t of (phase.tasks ?? [])) {
    if (taskStatus[t.id] === 'active') orphans.push(t.id);
  }
}
if (orphans.length) {
  deadlock('active_orphan', {
    tasks: orphans,
    hint: 'retirer ces IDs de active_tasks (reprise) ou les marquer done si le travail existe',
  });
}

// 2. DAG structurellement invalide (requires cassé, cycle, gate manquante)
try {
  const { lint } = require('./hb-lint.js');
  const res = lint(dag);
  if (res.errors.length) deadlock('dag_invalid', { errors: res.errors.slice(0, 5) });
} catch (e) { /* lint absent : on retombe sur unsatisfiable */ }

// 3. Cause non identifiée
deadlock('unsatisfiable', { hint: 'aucune tâche éligible — lancer: node .hb/hb-lint.js .hb/dag.json' });
