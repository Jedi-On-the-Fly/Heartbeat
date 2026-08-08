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
    case 'codex':       return `bash "${path.join(ex, 'codex-exec.sh')}"`;
    case 'opencode':    return `bash "${path.join(ex, 'opencode-exec.sh')}"`;
    case 'agno':        return `python3 "${path.join(ex, 'agno_exec.py')}"`;
    case 'crewai':      return `python3 "${path.join(ex, 'crewai_exec.py')}"`;
    case 'ollama':        return `python3 "${path.join(ex, 'ollama_exec.py')}"`;
    case 'langgraph':     return `python3 "${path.join(ex, 'langgraph_exec.py')}"`;
    case 'openai-agents': return `python3 "${path.join(ex, 'openai_agents_exec.py')}"`;
    case 'autogen':       return `python3 "${path.join(ex, 'autogen_exec.py')}"`;
    case 'smolagents':    return `python3 "${path.join(ex, 'smolagents_exec.py')}"`;
    case 'pydantic-ai':   return `python3 "${path.join(ex, 'pydanticai_exec.py')}"`;
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
    cmd:         process.env.HB_EXEC_CMD || file.cmd || defaultCmd(backend),
    strict:      envBool('HB_EXEC_STRICT', file.strict != null ? !!file.strict : false),
    attemptCap:  parseInt(process.env.HB_EXEC_ATTEMPT_CAP || file.attempt_cap || '3', 10),
    concurrency: Math.max(1, parseInt(process.env.HB_MAX_CONCURRENCY || file.concurrency || '1', 10) || 1),
    heartbeatMs,
  };
}

// Worktree isolation needs git and a real repo (and must not be suppressed by HB_NO_GIT).
let _gitOk = null;
function gitIsolation() {
  if (_gitOk !== null) return _gitOk;
  _gitOk = false;
  if (!process.env.HB_NO_GIT) {
    try { execFileSync('git', ['-C', PROJECT_DIR, 'rev-parse', '--is-inside-work-tree'], { stdio: 'ignore' }); _gitOk = true; }
    catch (e) {}
  }
  return _gitOk;
}

// ── driver ↔ HeartBeat helpers ──────────────────────────────────────────────
function hb(...args) { return execFileSync('node', [HB, ...args], { cwd: PROJECT_DIR, encoding: 'utf8' }); }
// Same, but stamps HB_ACTOR — so the driver can record the refuter under a distinct
// identity from the worker (the self-review guard needs reviewer != doer).
function hbAs(actor, ...args) { return execFileSync('node', [HB, ...args], { cwd: PROJECT_DIR, encoding: 'utf8', env: { ...process.env, HB_ACTOR: actor } }); }

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
function dispatch(cmd, mode, payload, taskId, heartbeatMs, cwd) {
  return new Promise((resolve) => {
    const child = spawn('bash', ['-c', `${cmd} ${mode}`], { cwd: cwd || PROJECT_DIR, stdio: ['pipe', 'pipe', 'inherit'] });
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

// ── parallel fan-out: run the runnable set concurrently, isolated per task ────
// Each task runs in its own git worktree (writes can't collide); the merge-back is
// SERIALIZED so the git index never races. A failed task's worktree is discarded.
// Without git, falls back to concurrent in-place execution (caller-warned).
async function worktreeDispatch(t, c, attempts, iso, serialize) {
  try { hb('start', t.id); } catch (e) {}
  let cwd = PROJECT_DIR, wt = null, branch = null;
  if (iso) {
    branch = `hb-exec/${t.id}`;
    wt = path.join(HB_DIR, 'wt', t.id);
    try {
      fs.mkdirSync(path.join(HB_DIR, 'wt'), { recursive: true });
      execFileSync('git', ['-C', PROJECT_DIR, 'worktree', 'add', '--quiet', '-B', branch, wt, 'HEAD'], { stdio: 'ignore' });
      cwd = wt;
    } catch (e) { wt = null; cwd = PROJECT_DIR; }   // isolation failed → in-place
  }

  const r = await dispatch(c.cmd, 'execute',
    { mode: 'execute', task: t, project_dir: cwd, context: assembleContext(t) }, t.id, c.heartbeatMs, cwd);
  const ok = r.json && r.json.ok === true;
  let capped = false;
  const bump = () => { attempts[t.id] = (attempts[t.id] || 0) + 1; if (attempts[t.id] >= c.attemptCap) capped = true; };

  if (ok && wt) {
    try {
      await serialize(async () => {
        execFileSync('git', ['-C', wt, 'add', '-A'], { stdio: 'ignore' });
        // commit only if the task actually changed something
        let changed = true;
        try { execFileSync('git', ['-C', wt, 'diff', '--cached', '--quiet']); changed = false; } catch (e) {}
        if (changed) execFileSync('git', ['-c', 'user.name=HeartBeat', '-c', 'user.email=heartbeat@local',
          '-C', wt, 'commit', '--no-verify', '-q', '-m', `hb-exec(${t.id}): ${t.title}`], { stdio: 'ignore' });
        execFileSync('git', ['-C', PROJECT_DIR, 'merge', '--no-verify', '--no-edit', '-q', branch], { stdio: 'ignore' });
      });
      hb('done', t.id);
    } catch (mergeErr) {
      try { execFileSync('git', ['-C', PROJECT_DIR, 'merge', '--abort'], { stdio: 'ignore' }); } catch (e) {}
      hb('fail', t.id, 'merge conflict on integration'); bump();
    }
  } else if (ok) {
    hb('done', t.id);
  } else {
    hb('fail', t.id, (r.json && r.json.summary) || 'backend reported failure'); bump();
  }

  if (wt) {
    try { execFileSync('git', ['-C', PROJECT_DIR, 'worktree', 'remove', '--force', wt], { stdio: 'ignore' }); } catch (e) {}
    try { execFileSync('git', ['-C', PROJECT_DIR, 'branch', '-D', branch], { stdio: 'ignore' }); } catch (e) {}
  }
  return capped ? 'capped' : 'ok';
}

async function fanOut(c, attempts) {
  let ready;
  try { ready = JSON.parse((hb('ready', String(c.concurrency)) || '[]').trim() || '[]'); } catch (e) { ready = []; }
  if (!ready.length) return 'continue';
  const iso = gitIsolation();
  process.stdout.write(`⇉ fan-out ${ready.length} task(s) [${iso ? 'worktree-isolated' : 'in-place'}]: ${ready.map(t => t.id).join(', ')}\n`);
  let chain = Promise.resolve();                                   // serialize merge-backs
  const serialize = (fn) => { const p = chain.then(fn); chain = p.catch(() => {}); return p; };
  const results = await Promise.all(ready.map(t => worktreeDispatch(t, c, attempts, iso, serialize)));
  if (results.some(r => r === 'capped')) { escalate('attempts_exhausted', 'a task exceeded the attempt cap under fan-out'); return 'stop'; }
  return 'continue';
}

// ── the run loop (serial by default; parallel when concurrency > 1) ───────────
async function run() {
  const c = config();
  const maxIters = parseInt(process.env.HB_EXEC_MAX_ITERS || '0', 10) || Infinity;
  // Distinct identities: the worker stamps task_done, the refuter stamps the review pass —
  // guaranteed different so the self-review guard is enforced in the automated path.
  const workerActor = process.env.HB_ACTOR || 'hb-exec:worker';
  process.env.HB_ACTOR = workerActor;
  const refuterActor = `${workerActor}:refuter`;
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
        if (c.concurrency > 1) {
          // The tick leased ONE task; free it so `hb ready N` returns the full runnable set.
          try { fs.rmSync(path.join(HB_DIR, 'leases', data.next_task.id), { recursive: true, force: true }); } catch (e) {}
          const sig = await fanOut(c, attempts);
          if (sig === 'stop') return 1;
          break;
        }
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
        if (r.json.refuted) {
          hb('review', gate, 'fail', r.json.findings || 'refuted');
        } else {
          // Sev-1: a "could not refute" pass must cite the refuter's ACTUAL written
          // attempt. Persist findings + pass --artifact so the verdict is reducible to
          // evidence on disk (doctor re-checks it). An empty pass is not a refutation.
          const findings = (r.json.findings || '').trim();
          if (findings.length < 40) {
            escalate('review_error', `${gate}: refuter returned a pass with no substantive findings — refusing to rubber-stamp`); return 1;
          }
          const fdir = path.join(HB_DIR, 'reviews');
          try { fs.mkdirSync(fdir, { recursive: true }); } catch (e) {}
          const fpath = path.join(fdir, `${gate}.attempt.md`);
          fs.writeFileSync(fpath, `# Refutation attempt for ${gate}\n\nVerdict: could not refute (refuted=false)\n\n${findings}\n`);
          hbAs(refuterActor, 'review', gate, 'pass', '--artifact', fpath);
        }
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
  const pIdx = process.argv.indexOf('--parallel');   // run --parallel N → HB_MAX_CONCURRENCY
  if (pIdx !== -1) { const n = parseInt(process.argv[pIdx + 1], 10); if (n > 0) process.env.HB_MAX_CONCURRENCY = String(n); }
  if (cmd === 'run')         run().then(code => process.exit(code || 0));
  else if (cmd === 'config') process.stdout.write(JSON.stringify(config(), null, 2) + '\n');
  else { process.stderr.write('usage: hb-exec.js <run|config>\n'); process.exit(1); }
}

module.exports = { run, config, assembleContext, nonBehavioral, strictBlock };
