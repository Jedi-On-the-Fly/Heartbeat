#!/usr/bin/env node
/**
 * hb-exec.js — HeartBeat executor driver (v1.8)
 *
 * Stage B is pluggable. HeartBeat stays the deterministic brain — the tick decides
 * WHAT/WHEN, the gates VERIFY — and this driver dispatches each task to a backend
 * agent (claude-code, agno, crewai, or a raw script) over a tiny JSON wire protocol:
 *
 *   driver → backend:  argv[last] = <mode: execute|refute>, stdin = <payload JSON>
 *   backend → driver:  ONE JSON object on stdout
 *     execute → { "ok": bool,       "summary":  string }
 *     refute  → { "refuted": bool,   "findings": string }
 *
 * The backend NEVER touches state.json or gate.sh. The driver mediates every state
 * transition (hb start/done/fail/review), runs gates itself, pumps the task lease
 * heartbeat while the backend works, and — by policy — ESCALATES (never auto-fixes)
 * when a gate blocks. Serial: one task at a time.
 *
 * Usage:  node hb-exec.js run        drive the loop until all_done or a human is needed
 *         node hb-exec.js config     print the resolved executor config
 *
 * Config: .hb/executor.json { backend, cmd, strict, attempt_cap }  (env vars override:
 *         HB_EXEC_BACKEND, HB_EXEC_CMD, HB_EXEC_STRICT, HB_EXEC_ATTEMPT_CAP,
 *         HB_EXEC_MAX_ITERS, HB_EXEC_MODEL).
 */
'use strict';
const fs   = require('fs');
const path = require('path');
const { execFileSync, execSync, spawn } = require('child_process');

const HB_DIR      = process.env.HB_DIR || __dirname;
const PROJECT_DIR = path.dirname(HB_DIR);
const DAG   = path.join(HB_DIR, 'dag.json');
const STATE = path.join(HB_DIR, 'state.json');
const HB    = path.join(HB_DIR, 'hb.js');
const TICK  = path.join(HB_DIR, 'tick.sh');
const GATE  = path.join(HB_DIR, 'gate.sh');

function readJson(f, dflt) { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) { return dflt; } }
function envBool(name, dflt) { const v = process.env[name]; return v == null ? dflt : (v === '1' || v === 'true'); }
// Read-only shell; never throws (used only to gather context).
function sh(cmd) { try { return execSync(cmd, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 8000 }); } catch (e) { return (e && e.stdout) || ''; } }

function defaultCmd(backend) {
  const ex = path.join(HB_DIR, 'executors');
  switch (backend) {
    case 'claude-code': return `bash "${path.join(ex, 'claude-exec.sh')}"`;
    case 'agno':        return `python3 "${path.join(ex, 'agno_exec.py')}"`;
    case 'crewai':      return `python3 "${path.join(ex, 'crewai_exec.py')}"`;
    default:            return backend;   // 'script'/custom: the backend IS the command
  }
}

function config() {
  const file = readJson(path.join(HB_DIR, 'executor.json'), {});
  const backend = process.env.HB_EXEC_BACKEND || file.backend || 'claude-code';
  const heartbeatMs = parseInt(process.env.HB_EXEC_HEARTBEAT_MS ||
    String(Math.floor(parseInt(process.env.HEARTBEAT_STALE_S || '180', 10) * 1000 / 2)), 10);
  return {
    backend,
    cmd:        process.env.HB_EXEC_CMD || file.cmd || defaultCmd(backend),
    strict:     envBool('HB_EXEC_STRICT', file.strict != null ? !!file.strict : false),
    attemptCap: parseInt(process.env.HB_EXEC_ATTEMPT_CAP || file.attempt_cap || '3', 10),
    heartbeatMs,
  };
}

// ── driver ↔ HeartBeat helpers ──────────────────────────────────────────────
function hb(...args) { return execFileSync('node', [HB, ...args], { cwd: PROJECT_DIR, encoding: 'utf8' }); }

function runTick() {
  const out = execFileSync('bash', [TICK], { cwd: PROJECT_DIR, encoding: 'utf8', env: process.env });
  const line = out.trim().split('\n').filter(Boolean).pop() || '{}';
  return JSON.parse(line);
}

function notify(reason, detail) {
  const cmd = process.env.HB_NOTIFY_CMD;
  if (!cmd) return;
  try {
    execFileSync('bash', ['-c', cmd, '_', reason, path.basename(PROJECT_DIR), detail || ''],
      { stdio: 'ignore', timeout: 10000 });
  } catch (e) { /* best-effort */ }
}
function escalate(reason, detail) {
  notify(reason, detail);
  process.stdout.write(`HB-EXEC STOP: ${reason}${detail ? ` — ${detail}` : ''}\n`);
}

// ── informed state → prompt (the driver assembles context; the backend consumes) ─
function assembleContext(task) {
  const dag   = readJson(DAG, { phases: [], gates: {} });
  const state = readJson(STATE, {});
  const phase = (dag.phases || []).find(p => p.id === task.phase) || {};
  const gate  = phase.gate_exit ? (dag.gates || {})[phase.gate_exit] : null;
  const L = [];
  L.push(`Project ${path.basename(PROJECT_DIR)} (dir: ${PROJECT_DIR}).`);
  L.push(`Phase ${task.phase}. Task ${task.id}: ${task.title}`);
  if (task.description) L.push(`\nWhat to do:\n${task.description}`);
  const doneHere = (state.completed_tasks || []).filter(t => (phase.tasks || []).some(x => x.id === t));
  if (doneHere.length) L.push(`\nAlready completed in this phase: ${doneHere.join(', ')}`);
  if (gate && (gate.criteria || []).length) {
    L.push(`\nThis phase's gate (${phase.gate_exit}) will verify the following — build to make these pass, but do NOT edit the gate or the tests it runs:`);
    for (const c of gate.criteria) L.push(`  - ${c.desc || c.id}: ${c.cmd}`);
  }
  const log = sh(`git -C "${PROJECT_DIR}" log --oneline -8`).trim();
  if (log) L.push(`\nRecent commits:\n${log}`);
  L.push('\nDo exactly this one task, then stop. Work in the project directory. Do not modify .hb/.');
  return L.join('\n');
}

// ── strict mode: in an unattended run, refuse weak gates ─────────────────────
function nonBehavioral(cmd) {
  // A criterion that only checks a file/dir EXISTS (not that it behaves).
  return /^\s*(test\s+-[efds]\b|\[\s+-[efds]\b|ls\b)/.test(cmd || '');
}
function strictBlock(gateId) {
  const dag  = readJson(DAG, { gates: {} });
  const gate = (dag.gates || {})[gateId] || {};
  const reasons = [];
  if ((gate.criteria || []).some(c => nonBehavioral(c.cmd)))
    reasons.push(`gate ${gateId} has a non-behavioral criterion (existence check, not behavior)`);
  try {
    const { lint } = require(path.join(HB_DIR, 'hb-lint.js'));
    const w = lint(dag).warnings;
    if (w.length) reasons.push(`hb-lint: ${w.length} warning(s) — ${w[0]}`);
  } catch (e) { /* lint absent → skip */ }
  return reasons;
}

// ── dispatch one backend call, pumping the lease heartbeat while it runs ──────
function dispatch(cmd, mode, payload, taskId, heartbeatMs) {
  return new Promise((resolve) => {
    const child = spawn('bash', ['-c', `${cmd} ${mode}`], { cwd: PROJECT_DIR, stdio: ['pipe', 'pipe', 'inherit'] });
    let out = '';
    child.stdout.on('data', d => (out += d));
    let timer = null;
    if (taskId && heartbeatMs > 0) {
      timer = setInterval(() => { try { execFileSync('node', [HB, 'heartbeat', taskId], { stdio: 'ignore' }); } catch (e) {} }, heartbeatMs);
    }
    child.on('close', (code) => {
      if (timer) clearInterval(timer);
      const line = out.trim().split('\n').filter(Boolean).pop() || '';
      let json = null; try { json = JSON.parse(line); } catch (e) {}
      resolve({ code, json, raw: out });
    });
    child.stdin.write(JSON.stringify(payload));
    child.stdin.end();
  });
}

// ── the serial run loop ──────────────────────────────────────────────────────
async function run() {
  const c = config();
  const maxIters = parseInt(process.env.HB_EXEC_MAX_ITERS || '0', 10) || Infinity;
  const attempts = {};

  for (let i = 0; i < maxIters; i++) {
    let tick;
    try { tick = runTick(); } catch (e) { escalate('tick_error', e.message); return 1; }
    const data = tick.data || {};
    const reason = data.reason;

    if (!tick.wakeAgent) {
      if (reason === 'project_complete') { process.stdout.write('HB-EXEC DONE: project complete\n'); return 0; }
      process.stdout.write(`HB-EXEC IDLE: ${reason || '(unknown)'}\n`);
      return 0;
    }

    switch (reason) {
      case 'next_task': {
        const t = data.next_task;
        process.stdout.write(`▸ ${t.id} — ${t.title}\n`);
        try { hb('start', t.id); } catch (e) {}
        const r = await dispatch(c.cmd, 'execute',
          { mode: 'execute', task: t, project_dir: PROJECT_DIR, context: assembleContext(t) },
          t.id, c.heartbeatMs);
        if (r.json && r.json.ok === true) {
          hb('done', t.id);
        } else {
          hb('fail', t.id, (r.json && r.json.summary) || 'backend reported failure');
          attempts[t.id] = (attempts[t.id] || 0) + 1;
          if (attempts[t.id] >= c.attemptCap) {
            escalate('attempts_exhausted', `${t.id} failed ${attempts[t.id]}× (cap ${c.attemptCap})`);
            return 1;
          }
        }
        break;
      }

      case 'gate_pending': {
        const gate = data.next_task && data.next_task.gate;
        if (c.strict) {
          const blocks = strictBlock(gate);
          if (blocks.length) { escalate('strict_gate', `${gate}: ${blocks.join('; ')}`); return 1; }
        }
        // gate.sh advances the phase on pass (and announces a review if one is owed);
        // on fail it records the error → the next tick surfaces gate_blocked.
        try { execFileSync('bash', [GATE, gate], { cwd: PROJECT_DIR, stdio: 'inherit' }); } catch (e) {}
        break;
      }

      case 'review_pending': {
        const gate = data.next_task && data.next_task.gate;
        const dag  = readJson(DAG, { gates: {} });
        const rv   = ((dag.gates || {})[gate] || {}).review || {};
        const r = await dispatch(c.cmd, 'refute',
          { mode: 'refute', gate, prompt: rv.prompt || `Refute that ${gate} is truly complete.`,
            project_dir: PROJECT_DIR, context: sh(`git -C "${PROJECT_DIR}" log --oneline -8`).trim() },
          null, 0);
        if (!r.json || typeof r.json.refuted !== 'boolean') {
          escalate('review_error', `${gate}: backend returned no verdict`); return 1;
        }
        if (r.json.refuted) hb('review', gate, 'fail', r.json.findings || 'refuted');
        else                hb('review', gate, 'pass');
        break;
      }

      case 'all_done':
        report();
        process.stdout.write('HB-EXEC DONE: all phases complete\n');
        return 0;

      // escalate-only: every human-needed reason stops the run and notifies.
      case 'gate_blocked':        escalate('gate_blocked', 'gate errors — human needed (escalate-only policy)'); return 1;
      case 'build_stuck':         escalate('build_stuck', data.task || data.signal || ''); return 1;
      case 'deadlock':            escalate('deadlock', data.detail ? JSON.stringify(data.detail) : ''); return 1;
      case 'unsanctioned_drift':  escalate('unsanctioned_drift', ''); return 1;
      case 'dag_corrupted':       escalate('dag_corrupted', ''); return 1;
      case 'state_corrupted':     escalate('state_corrupted', ''); return 1;
      case 'gate_rot':            escalate('gate_rot', `count=${data.count || '?'}`); return 1;
      case 'review_stuck':        escalate('review_stuck', data.gate || ''); return 1;
      default:                    escalate('unknown_reason', reason || '(none)'); return 1;
    }
  }
  process.stdout.write('HB-EXEC: max iterations reached\n');
  return 0;
}

function report() {
  try { process.stdout.write(execFileSync('node', [path.join(HB_DIR, 'hb-report.js'), HB_DIR], { encoding: 'utf8' })); } catch (e) {}
}

if (require.main === module) {
  const cmd = process.argv[2];
  if (cmd === 'run')         run().then(code => process.exit(code || 0));
  else if (cmd === 'config') process.stdout.write(JSON.stringify(config(), null, 2) + '\n');
  else { process.stderr.write('usage: hb-exec.js <run|config>\n'); process.exit(1); }
}

module.exports = { run, config, assembleContext, nonBehavioral, strictBlock };
