#!/usr/bin/env node
/**
 * hb.js — HeartBeat state CLI (v1.3)
 *
 * events.jsonl is AUTHORITATIVE. state.json is a pure PROJECTION of the log,
 * with the same shape it has always had. Agents mutate state ONLY through this
 * CLI — never by hand-editing JSON. Every mutation is: acquire write-lock →
 * append event → reproject the whole log → atomic write (tmp+rename) → release.
 *
 * Commands:
 *   hb start <taskId>          append task_started
 *   hb done  <taskId>          append task_done   (frees the task lease — P4)
 *   hb fail  <taskId> [reason] append task_failed (frees the task lease — P4)
 *   hb rebuild                 replay events.jsonl → state.json (sync / recover)
 *   hb state                   print the projected state (no write)
 *   hb import                  seed the log from an existing state.json (migration)
 *
 * State-mutating events: initialized, task_started, task_done, task_failed,
 * gate_passed, gate_failed. All other events are audit-only (ignored by the
 * projector). build_stuck_count, completed_phases and current_phase are DERIVED.
 *
 * HB_DIR defaults to the directory this script lives in (.hb/).
 */
'use strict';

const fs   = require('fs');
const path = require('path');

const HB_DIR = process.env.HB_DIR || __dirname;
const EVENTS = path.join(HB_DIR, 'events.jsonl');
const STATE  = path.join(HB_DIR, 'state.json');
const DAG    = path.join(HB_DIR, 'dag.json');
const LEASES = path.join(HB_DIR, 'leases');          // used by P4
const WLOCK  = path.join(HB_DIR, '.wlock');
const LOCK_STALE_S = parseInt(process.env.LOCK_STALE_S || '1800', 10);

const nowIso = () => new Date().toISOString();
const sleepMs = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

function readDag() {
  try { return JSON.parse(fs.readFileSync(DAG, 'utf8')); }
  catch (e) { return { phases: [], gates: {} }; }
}

function readEvents() {
  let raw;
  try { raw = fs.readFileSync(EVENTS, 'utf8'); } catch (e) { return []; }
  const out = [];
  for (const line of raw.split('\n')) {
    const s = line.trim();
    if (!s) continue;
    try { out.push(JSON.parse(s)); } catch (e) { /* skip malformed audit line */ }
  }
  return out;
}

function phaseByGateExit(dag, gate) {
  for (const p of (dag.phases || [])) if (p.gate_exit === gate) return p.id;
  return null;
}

function initialState(dag) {
  const firstPhase = (dag.phases && dag.phases[0] && dag.phases[0].id) || null;
  return {
    current_phase: firstPhase,
    active_tasks: [],
    completed_tasks: [],
    completed_phases: [],
    build_stuck_count: 0,
    gate: { errors: 0 },
    last_event: 'initialized',
    last_updated: nowIso(),
  };
}

// Pure: (events, dag) → state. Deterministic (except last_updated timestamp).
function project(events, dag) {
  const s = initialState(dag);
  const completed = new Set();
  const active = new Set();
  const completedPhases = new Set();

  for (const ev of events) {
    switch (ev.event) {
      case 'initialized':
        completed.clear(); active.clear(); completedPhases.clear();
        s.build_stuck_count = 0; s.gate.errors = 0;
        break;
      case 'task_started':
        if (ev.task && !completed.has(ev.task)) active.add(ev.task);
        break;
      case 'task_done':
        if (ev.task) { completed.add(ev.task); active.delete(ev.task); }
        s.build_stuck_count = 0;
        break;
      case 'task_failed':
        if (ev.task) active.delete(ev.task);
        s.build_stuck_count += 1;
        break;
      case 'lease_expired':          // dead agent reclaimed → task returns to pending
        if (ev.task) active.delete(ev.task);
        break;
      case 'gate_passed': {
        const ph = phaseByGateExit(dag, ev.gate);
        if (ph) completedPhases.add(ph);
        s.gate.errors = 0; s.build_stuck_count = 0;
        break;
      }
      case 'gate_failed':
        s.gate.errors = 1; s.build_stuck_count += 1;
        break;
      default: /* audit-only event → no state change */ break;
    }
    if (ev.event) s.last_event = ev.event;
  }

  s.completed_tasks = [...completed];
  s.active_tasks = [...active];
  s.completed_phases = [...completedPhases];

  const phases = dag.phases || [];
  let cur = null;
  for (const p of phases) { if (!completedPhases.has(p.id)) { cur = p.id; break; } }
  if (cur === null && phases.length) cur = phases[phases.length - 1].id;
  s.current_phase = cur;

  s.last_updated = nowIso();
  return s;
}

function atomicWrite(file, data) {
  const tmp = file + '.tmp';
  fs.writeFileSync(tmp, data);
  fs.renameSync(tmp, file);
}

function reproject() {
  const state = project(readEvents(), readDag());
  atomicWrite(STATE, JSON.stringify(state, null, 2));
  return state;
}

function appendEvent(ev) {
  ev.ts = ev.ts || nowIso();
  fs.appendFileSync(EVENTS, JSON.stringify(ev) + '\n');
}

// Guards the append+reproject critical section so concurrent mutations are safe.
function withWlock(fn) {
  const deadline = Date.now() + 5000;
  for (;;) {
    try { fs.mkdirSync(WLOCK); break; }
    catch (e) {
      try {
        const age = (Date.now() - fs.statSync(WLOCK).mtimeMs) / 1000;
        if (age > LOCK_STALE_S) { fs.rmSync(WLOCK, { recursive: true, force: true }); continue; }
      } catch (_) { /* lock vanished — retry */ }
      if (Date.now() > deadline) throw new Error('hb: write-lock timeout');
      sleepMs(50);
    }
  }
  try { return fn(); }
  finally { try { fs.rmSync(WLOCK, { recursive: true, force: true }); } catch (_) {} }
}

function releaseLease(task) {
  try { fs.rmSync(path.join(LEASES, task), { recursive: true, force: true }); } catch (_) {}
}

function mutate(ev) {
  return withWlock(() => { appendEvent(ev); return reproject(); });
}

// ── CLI ───────────────────────────────────────────────────────────────────────
const [cmd, arg1, ...rest] = process.argv.slice(2);
const die = (msg) => { process.stderr.write(msg + '\n'); process.exit(1); };

switch (cmd) {
  case 'start':
    if (!arg1) die('usage: hb start <taskId>');
    fs.mkdirSync(LEASES, { recursive: true });
    try { fs.mkdirSync(path.join(LEASES, arg1)); } catch (e) { /* idempotent: tick may have leased it */ }
    mutate({ event: 'task_started', task: arg1 });
    process.stdout.write(`started ${arg1}\n`);
    break;

  case 'done':
    if (!arg1) die('usage: hb done <taskId>');
    mutate({ event: 'task_done', task: arg1 });
    releaseLease(arg1);
    process.stdout.write(`done ${arg1}\n`);
    break;

  case 'fail': {
    if (!arg1) die('usage: hb fail <taskId> [reason]');
    const reason = rest.join(' ');
    mutate({ event: 'task_failed', task: arg1, ...(reason ? { reason } : {}) });
    releaseLease(arg1);
    process.stdout.write(`failed ${arg1}\n`);
    break;
  }

  case 'heartbeat':
  case 'beat': {
    if (!arg1) die('usage: hb heartbeat <taskId>');
    const lease = path.join(LEASES, arg1);
    if (!fs.existsSync(lease)) {   // lost the claim (already reclaimed) — non-fatal
      process.stderr.write(`hb heartbeat: no lease for ${arg1} (reclaimed?)\n`);
      process.exit(0);
    }
    fs.writeFileSync(path.join(lease, 'beat'), nowIso());   // refreshes mtime = liveness
    process.stdout.write(`beat ${arg1}\n`);
    break;
  }

  case 'rebuild': {
    const s = withWlock(() => reproject());
    process.stdout.write(`rebuilt: ${s.completed_tasks.length} done, phase ${s.current_phase}\n`);
    break;
  }

  case 'state':
    process.stdout.write(JSON.stringify(project(readEvents(), readDag()), null, 2) + '\n');
    break;

  case 'import': {
    let legacy;
    try { legacy = JSON.parse(fs.readFileSync(STATE, 'utf8')); }
    catch (e) { die('hb import: no readable state.json to import'); }
    withWlock(() => {
      const dag = readDag();
      for (const t of (legacy.completed_tasks || [])) appendEvent({ event: 'task_started', task: t });
      for (const t of (legacy.completed_tasks || [])) appendEvent({ event: 'task_done', task: t });
      for (const ph of (legacy.completed_phases || [])) {
        const phase = (dag.phases || []).find(p => p.id === ph);
        if (phase && phase.gate_exit) appendEvent({ event: 'gate_passed', gate: phase.gate_exit });
      }
      reproject();
    });
    process.stdout.write('imported legacy state into the event log\n');
    break;
  }

  default:
    die('usage: hb <start|done|fail|heartbeat|rebuild|state|import> [args]');
}

module.exports = { project, phaseByGateExit, initialState };
