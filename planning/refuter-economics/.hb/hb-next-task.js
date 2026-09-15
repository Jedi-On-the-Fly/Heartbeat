#!/usr/bin/env node
/**
 * hb-next-task.js — HeartBeat gate-aware resolver (v1.4)
 *
 * A phase is eligible only once its gate_entry has passed (the phase carrying that
 * gate as gate_exit is in state.completed_phases). Leased tasks (.hb/leases/<id>)
 * are runtime claims and are excluded from handout.
 *
 * Exports:
 *   resolve(state, dag, hbDir)              → single next action:
 *     { id, phase, title, description, requires }   actionable task
 *     { type:"gate_pending", phase, gate }          phase tasks done, gate to run
 *     { type:"review_pending", phase, gate }        gate passed, adversarial review due (v1.4)
 *     { type:"all_done" } | { type:"busy", … } | { type:"deadlock", … } | null
 *   readyTasks(state, dag, hbDir, limit)    → array of ALL currently-runnable,
 *                                             unleased, requires-independent tasks
 *                                             (up to `limit`; 0 = no limit) — for
 *                                             parallel drivers (v1.4).
 *
 * CLI: node hb-next-task.js <path/to/state.json>   (dag.json expected alongside)
 */
'use strict';

const fs   = require('fs');
const path = require('path');

function buildContext(state, dag, hbDir) {
  const phases = dag.phases ?? [];
  const completedPhases = new Set(state.completed_phases ?? []);
  const pendingReviews  = new Set(state.pending_reviews ?? []);   // v1.4
  const taskStatus = {};
  for (const t of (state.completed_tasks ?? [])) taskStatus[t] = 'done';
  for (const t of (state.active_tasks    ?? [])) taskStatus[t] = 'active';
  const leased = new Set();
  try {
    for (const t of fs.readdirSync(path.join(hbDir, 'leases'))) {
      leased.add(t);
      if (!taskStatus[t]) taskStatus[t] = 'leased';
    }
  } catch (e) { /* no leases dir yet */ }
  const gatePassed = new Set();
  for (const p of phases) if (completedPhases.has(p.id) && p.gate_exit) gatePassed.add(p.gate_exit);
  return { phases, completedPhases, pendingReviews, taskStatus, leased, gatePassed };
}

// A parked phase is out of the plan's live surface: its tasks are never offered, it never
// produces gate_pending/review_pending, and all_done is computed without it. Note that
// gatePassed (in buildContext) is still computed over ALL phases — parking a completed
// phase must not re-block downstream phases whose gate_entry it satisfied.
function isLive(phase) { return !phase.parked; }

function isEligible(task, ctx) {
  if ((ctx.taskStatus[task.id] ?? 'pending') !== 'pending') return false;
  return (task.requires ?? []).every(r => ctx.taskStatus[r] === 'done');
}

function taskView(task, phase) {
  return {
    id:          task.id,
    phase:       phase.id,
    title:       task.title ?? task.id,
    description: task.description ?? '',
    requires:    task.requires ?? [],
  };
}

/** All currently-runnable, unleased tasks (up to limit; 0 = no limit). */
function readyTasks(state, dag, hbDir, limit) {
  const ctx = buildContext(state, dag, hbDir);
  const out = [];
  for (const phase of ctx.phases) {
    if (!isLive(phase)) continue;
    if (ctx.completedPhases.has(phase.id)) continue;
    if (phase.gate_entry && !ctx.gatePassed.has(phase.gate_entry)) continue;
    for (const task of (phase.tasks ?? [])) {
      if (!isEligible(task, ctx)) continue;
      out.push(taskView(task, phase));
      if (limit && out.length >= limit) return out;
    }
  }
  return out;
}

/** Single next action (see header for the shape). */
function resolve(state, dag, hbDir) {
  const ctx = buildContext(state, dag, hbDir);
  const { phases, completedPhases, pendingReviews, taskStatus, leased, gatePassed } = ctx;

  for (const phase of phases) {
    if (!isLive(phase)) continue;
    if (completedPhases.has(phase.id)) continue;
    if (phase.gate_entry && !gatePassed.has(phase.gate_entry)) continue;
    const tasks = phase.tasks ?? [];
    for (const task of tasks) {
      if (isEligible(task, ctx)) return taskView(task, phase);
    }
    if (tasks.length > 0 && tasks.every(t => taskStatus[t.id] === 'done')) {
      // v1.4: deterministic gate passed but adversarial review still owed → review_pending
      if (phase.gate_exit && pendingReviews.has(phase.gate_exit)) {
        return { type: 'review_pending', phase: phase.id, gate: phase.gate_exit };
      }
      return { type: 'gate_pending', phase: phase.id, gate: phase.gate_exit ?? null };
    }
  }

  if (phases.length === 0) return null;
  if (phases.filter(isLive).every(p => completedPhases.has(p.id))) return { type: 'all_done' };

  // busy: the only tasks blocking progress are leased (in flight elsewhere)
  const inFlight = [];
  for (const phase of phases) {
    if (!isLive(phase)) continue;
    if (completedPhases.has(phase.id)) continue;
    if (phase.gate_entry && !gatePassed.has(phase.gate_entry)) continue;
    for (const t of (phase.tasks ?? [])) if (leased.has(t.id)) inFlight.push(t.id);
  }
  if (inFlight.length) return { type: 'busy', in_flight: inFlight };

  // active orphans (agent died mid-task, lease reclaimed but still marked active)
  const orphans = [];
  for (const phase of phases) {
    if (!isLive(phase)) continue;
    if (completedPhases.has(phase.id)) continue;
    if (phase.gate_entry && !gatePassed.has(phase.gate_entry)) continue;
    for (const t of (phase.tasks ?? [])) if (taskStatus[t.id] === 'active') orphans.push(t.id);
  }
  if (orphans.length) return {
    type: 'deadlock', cause: 'active_orphan',
    detail: { tasks: orphans, hint: 'remove these IDs from active_tasks (to retry) or mark them done if the work exists' },
  };

  try {
    const { lint } = require('./hb-lint.js');
    const res = lint(dag);
    if (res.errors.length) return { type: 'deadlock', cause: 'dag_invalid', detail: { errors: res.errors.slice(0, 5) } };
  } catch (e) { /* lint absent → fall through */ }

  return { type: 'deadlock', cause: 'unsatisfiable', detail: { hint: 'no eligible task — run: node .hb/hb-lint.js .hb/dag.json' } };
}

if (require.main === module) {
  const stateFile = process.argv[2];
  if (!stateFile) {
    process.stderr.write('Usage: hb-next-task.js <path/to/state.json>\n');
    process.stdout.write('null\n'); process.exit(0);
  }
  const hbDir = path.dirname(stateFile);
  let state, dag;
  try { state = JSON.parse(fs.readFileSync(stateFile, 'utf8')); }
  catch (e) { process.stderr.write(`Cannot read state.json: ${e.message}\n`); process.stdout.write('null\n'); process.exit(0); }
  try { dag = JSON.parse(fs.readFileSync(path.join(hbDir, 'dag.json'), 'utf8')); }
  catch (e) { process.stderr.write(`Cannot read dag.json: ${e.message}\n`); process.stdout.write('null\n'); process.exit(0); }
  const result = resolve(state, dag, hbDir);
  process.stdout.write((result === null ? 'null' : JSON.stringify(result)) + '\n');
  process.exit(0);
}

module.exports = { readyTasks, resolve };
