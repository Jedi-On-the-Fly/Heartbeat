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
const { nonBehavioral } = require('./hb-audit.js');   // single-sourced (R4)
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
  const cmd = process.env.HB_EXEC_CMD || file.cmd || defaultCmd(backend);
  // Cross-model refuter: run `refute` on a distinct backend/cmd/model from the doer. Each falls
  // back to the doer's value (backward compatible). refuteCmd falls back to the doer's cmd ONLY
  // when no distinct refute backend was requested — else use that backend's default command.
  const refuteBackend = process.env.HB_REFUTE_BACKEND || file.refute_backend || backend;
  const distinctRefuteBackend = !!(process.env.HB_REFUTE_BACKEND || file.refute_backend);
  const refuteCmd = process.env.HB_REFUTE_CMD || file.refute_cmd ||
    (distinctRefuteBackend ? defaultCmd(refuteBackend) : cmd);
  return {
    backend,
    cmd,
    // Generic, domain-neutral context hook: a command whose stdout is appended to each task's
    // context (see assembleContext). The executor knows nothing about what it produces.
    contextCmd:  process.env.HB_EXEC_CONTEXT_CMD || file.context_cmd || '',
    strict:      envBool('HB_EXEC_STRICT', file.strict != null ? !!file.strict : false),
    attemptCap:  parseInt(process.env.HB_EXEC_ATTEMPT_CAP || file.attempt_cap || '3', 10),
    concurrency: Math.max(1, parseInt(process.env.HB_MAX_CONCURRENCY || file.concurrency || '1', 10) || 1),
    heartbeatMs,
    refuteBackend,
    refuteCmd,
    refuteModel:    process.env.HB_REFUTE_MODEL || file.refute_model || null,
    refuteProvider: process.env.HB_REFUTE_PROVIDER || file.refute_provider || null,
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
  return L.join('\n') + contextHook(task);
}

// Generic context hook: if a context_cmd is configured, run it and append its stdout to the task
// context, delimited. Domain-neutral — the executor never inspects what the command emits.
function contextHook(task) {
  const cmd = config().contextCmd;
  if (!cmd) return '';
  const env = { ...process.env, HB_TASK_ID: task.id || '', HB_TASK_TITLE: task.title || '', HB_TASK_DESC: task.description || '' };
  let out = '';
  // Inject the captured stdout even when the command exits NONZERO (execSync throws but carries
  // e.stdout) — this mirrors Python's subprocess.run (no check), so the injected block is identical
  // across runtimes. Degrade to nothing only when there is truly no output (spawn/timeout error).
  try { out = execSync(cmd, { encoding: 'utf8', env, stdio: ['ignore', 'pipe', 'ignore'], timeout: 30000 }); }
  catch (e) { out = (e && e.stdout) || ''; if (!out) process.stderr.write(`context_cmd failed: ${e.message}\n`); }
  out = String(out).trim();
  return out ? `\n\n<<HB-CONTEXT>>\n${out}\n<</HB-CONTEXT>>` : '';
}

// ── strict mode: in an unattended run, refuse weak gates ─────────────────────
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
function dispatch(cmd, mode, payload, taskId, heartbeatMs, cwd, extraEnv) {
  return new Promise((resolve) => {
    const env = extraEnv ? { ...process.env, ...extraEnv } : process.env;   // cross-model: refuter model/provider
    const child = spawn('bash', ['-c', `${cmd} ${mode}`], { cwd: cwd || PROJECT_DIR, stdio: ['pipe', 'pipe', 'inherit'], env });
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
    // A backend that doesn't drain stdin (e.g. a tiny script that only reads argv) closes the
    // pipe before we finish writing → an EPIPE 'error' on child.stdin. Unhandled, it crashes the
    // driver (a flaky "no review_passed" — the payload write raced the child's exit). The payload
    // is best-effort; swallow EPIPE (the child chose not to read it) and re-throw anything else.
    child.stdin.on('error', (e) => { if (!e || e.code !== 'EPIPE') throw e; });
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

// ── constraint-first review, unattended (a CONSTRAINED gate) ──────────────────────
// author (mode `author` → {"ok":bool,"constraints":[…]}) → `hb constraints --record` as the author actor
// → constrained refute (every id + answer format; a panel checks EACH panelist's answers) → free refute
// (payload.review = "free") when the profile asks → `hb review free` as the free actor → the SAME enforced
// `hb review pass`. Each role dispatches with its own profile model (author_model / model / free_model),
// an unset one falling back to the executor's refute default. A refused answer set or pass is recorded as
// review_failed with the reason (the next tick surfaces gate_blocked → escalation) — never a crash, never
// a pass. Returns an exit code to stop the run, or undefined to continue the loop.
async function constrainedReview(c, dag, gate, rv, actors) {
  const rprof = require('./refuter_profiles.js');
  const hbjs = require('./hb.js');
  let prof;
  try { prof = rprof.gateProfile(HB_DIR, rv); } catch (e) { escalate('review_error', `${gate}: ${e.message}`); return 1; }
  const dflt = c.refuteModel;
  const rProvider = (prof && prof.provider) || c.refuteProvider;
  // ONE validation, identical in python: model fields are strings; verdict.panel a positive integer
  // (a number, or a string of digits). Anything else escalates — never a crash, never a guess.
  for (const f of ['author_model', 'model', 'free_model', 'provider'])
    if (prof && prof[f] != null && typeof prof[f] !== 'string') { escalate('review_error', `${gate}: the refuter profile field ${f} must be a string`); return 1; }
  const models = { author: (prof && prof.author_model) || dflt, refute: (prof && prof.model) || dflt, free: (prof && prof.free_model) || dflt };
  const envFor = (m) => { const e = {}; if (m) e.HB_EXEC_MODEL = m; if (rProvider) e.HB_EXEC_PROVIDER = rProvider; return Object.keys(e).length ? e : undefined; };
  const context = sh(`git -C "${PROJECT_DIR}" log --oneline -8`).trim();
  const fdir = path.join(HB_DIR, 'reviews');
  try { fs.mkdirSync(fdir, { recursive: true }); } catch (e) {}
  const errOf = (e) => ((e && e.stderr) ? e.stderr.toString() : (e && e.message) || '').trim().split('\n').pop();
  const refuse = (reason, model = models.refute) => {   // a refused review is a recorded failure, never a crash
    try { hb('review', gate, 'fail', reason.slice(0, 1500), ...(model ? ['--model', model] : [])); }
    catch (e) { escalate('review_error', `${gate}: could not record the refusal (${errOf(e)})`); return 1; }
    return undefined;
  };

  // 1. the gate-time author (once per review cycle)
  if (!hbjs.reviewCycle(hbjs_dag(), gate).recorded) {
    let aPrompt;
    try { aPrompt = hbjs.composeAuthorPrompt(hbjs_dag(), gate); } catch (e) { escalate('review_error', `${gate}: ${e.message}`); return 1; }
    const ra = await dispatch(c.refuteCmd, 'author', { mode: 'author', gate, prompt: aPrompt, project_dir: PROJECT_DIR, context }, null, 0, undefined, envFor(models.author));
    if (!ra.json || typeof ra.json !== 'object' || Array.isArray(ra.json) || ra.json.ok !== true || !Array.isArray(ra.json.constraints)) {
      escalate('review_error', `${gate}: the constraint author returned no constraint list`); return 1;
    }
    const af = path.join(fdir, `${gate}.author.json`);
    fs.writeFileSync(af, JSON.stringify(ra.json.constraints, null, 2) + '\n');
    try { hbAs(actors.authorActor, 'constraints', gate, '--record', af, ...(models.author ? ['--model', models.author] : [])); }
    catch (e) { escalate('review_error', `${gate}: the author's constraints were rejected — ${errOf(e)}`); return 1; }
  }
  let ids;
  try { ids = hbjs.planConstraints(hbjs_dag(), gate).map(x => x.id).concat(hbjs.recordedConstraints(gate).map(x => x.id)); }
  catch (e) { escalate('review_error', `${gate}: ${e.message}`); return 1; }

  // 2. the constrained refute (composed AFTER recording, so it carries the gate-time ids)
  let prompt;
  try { prompt = rprof.composePrompt(HB_DIR, hbjs_dag(), gate); } catch (e) { escalate('review_error', `${gate}: ${e.message}`); return 1; }
  const payload = { mode: 'refute', gate, prompt, project_dir: PROJECT_DIR, context };
  const verdictCfg = (prof && prof.verdict) || {};
  const pv = verdictCfg.panel == null ? 1 : verdictCfg.panel;
  const panelN = (typeof pv === 'number' && Number.isInteger(pv) && pv >= 1) ? pv
    : (typeof pv === 'string' && /^[0-9]+$/.test(pv) && parseInt(pv, 10) >= 1) ? parseInt(pv, 10) : null;
  if (panelN === null || panelN > 50) { escalate('review_error', `${gate}: the refuter profile verdict.panel must be a positive integer (at most 50)`); return 1; }
  const verdicts = [], texts = [];
  for (let i = 0; i < panelN; i++) {
    const ri = await dispatch(c.refuteCmd, 'refute', payload, null, 0, undefined, envFor(models.refute));
    const bad = !ri.json || typeof ri.json !== 'object' || Array.isArray(ri.json) || typeof ri.json.refuted !== 'boolean' ||
                (ri.json.findings != null && typeof ri.json.findings !== 'string');
    if (bad) {
      escalate('review_error', `${gate}: ${panelN > 1 ? `panelist ${i + 1}/${panelN}` : 'the refuter'} returned no verdict (fail-closed)`); return 1;
    }
    verdicts.push(ri.json.refuted); texts.push((ri.json.findings || '').trim());
  }
  const refuted = panelN > 1 ? rprof.aggregateVerdict(verdicts, verdictCfg.refute_if || 'majority') : verdicts[0];
  if (refuted) return refuse(texts.filter(Boolean).join('\n\n') || 'refuted');
  // each panelist's answers are checked on their own — one VIOLATED (or incomplete) answer set refuses
  for (let i = 0; i < texts.length; i++) {
    const a = hbjs.checkAnswers(texts[i], ids);
    if (a.errors.length)
      return refuse(`answers refused${panelN > 1 ? ` (panelist ${i + 1}/${panelN})` : ''}: ${a.errors.join('; ')}`);
  }

  // 3. the free review (breadth, no constraint list) when the profile asks for it
  if (prof && prof.free_review) {
    let fPrompt;
    try { fPrompt = rprof.composePrompt(HB_DIR, hbjs_dag(), gate, { free: true }); } catch (e) { escalate('review_error', `${gate}: ${e.message}`); return 1; }
    const rf = await dispatch(c.refuteCmd, 'refute', { mode: 'refute', review: 'free', gate, prompt: fPrompt, project_dir: PROJECT_DIR, context }, null, 0, undefined, envFor(models.free));
    if (!rf.json || typeof rf.json !== 'object' || Array.isArray(rf.json) || typeof rf.json.refuted !== 'boolean' ||
        (rf.json.findings != null && typeof rf.json.findings !== 'string')) { escalate('review_error', `${gate}: the free reviewer returned no verdict (fail-closed)`); return 1; }
    const ft = (rf.json.findings || '').trim();
    if (rf.json.refuted) return refuse(`free review: ${ft || 'refuted'}`, models.free);
    const ff = path.join(fdir, `${gate}.free.attempt.md`);
    fs.writeFileSync(ff, `# Free review of ${gate}\n\n${ft}\n`);
    try { hbAs(actors.freeActor, 'review', gate, 'free', '--artifact', ff, ...(models.free ? ['--model', models.free] : [])); }
    catch (e) { return refuse(`free review rejected: ${errOf(e)}`); }
  }

  // 4. the SAME enforced pass (the first panelist's validated answers are the artifact)
  const fpath = path.join(fdir, `${gate}.attempt.md`);
  fs.writeFileSync(fpath, `# Refutation attempt for ${gate}\n\nVerdict: could not refute (refuted=false)\n\n${texts[0]}\n`);
  try { hbAs(actors.refuterActor, 'review', gate, 'pass', '--artifact', fpath, ...(models.refute ? ['--model', models.refute] : [])); }
  catch (e) { return refuse(`review pass refused: ${errOf(e)}`); }
  return undefined;
}
function hbjs_dag() { return readJson(DAG, { gates: {} }); }

// ── the run loop (serial by default; parallel when concurrency > 1) ───────────
async function run() {
  const c = config();
  const maxIters = parseInt(process.env.HB_EXEC_MAX_ITERS || '0', 10) || Infinity;
  // Distinct identities: the worker stamps task_done, the refuter stamps the review pass —
  // guaranteed different so the self-review guard is enforced in the automated path.
  const workerActor = process.env.HB_ACTOR || 'hb-exec:worker';
  process.env.HB_ACTOR = workerActor;
  const refuterActor = `${workerActor}:refuter`;
  // Constraint-first review roles — each a distinct identity (the author and the free reviewer must
  // not be the doer, and the free reviewer must not be the pass reviewer).
  const authorActor = `${workerActor}:author`, freeActor = `${workerActor}:free`;
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
        if (Array.isArray(rv.constraints) && rv.constraints.length) {
          const rc = await constrainedReview(c, dag, gate, rv, { refuterActor, authorActor, freeActor });
          if (rc !== undefined) return rc;
          break;
        }
        // ONE compose (shared with `hb refute-prompt` + the interactive surface). An unknown profile
        // throws → fail CLOSED (never skip the review). A profile's model/provider route through the
        // existing cross-model refute path.
        const rprof = require('./refuter_profiles.js');
        let refutePrompt, prof;
        try { refutePrompt = rprof.composePrompt(HB_DIR, dag, gate); prof = rprof.gateProfile(HB_DIR, rv); }
        catch (e) { escalate('review_error', `${gate}: ${e.message}`); return 1; }
        const rModel    = (prof && prof.model)    || c.refuteModel;
        const rProvider = (prof && prof.provider) || c.refuteProvider;
        // Cross-model: dispatch the refute on the distinct refuter config (falls back to the doer).
        const refExtra = {};
        if (rModel)    refExtra.HB_EXEC_MODEL = rModel;
        if (rProvider) refExtra.HB_EXEC_PROVIDER = rProvider;
        let refuterId = (c.refuteCmd !== c.cmd) ? `cmd:${c.refuteCmd}` : c.refuteBackend;
        if (rModel) refuterId += ` model=${rModel}`;
        if (c.refuteCmd !== c.cmd || rModel)
          process.stdout.write(`  ↳ refuting ${gate} with a distinct refuter (${refuterId})\n`);
        const refExtraArg = Object.keys(refExtra).length ? refExtra : undefined;
        const payload = { mode: 'refute', gate, prompt: refutePrompt,
          project_dir: PROJECT_DIR, context: sh(`git -C "${PROJECT_DIR}" log --oneline -8`).trim() };
        const verdictCfg = (prof && prof.verdict) || {};
        const panelN = parseInt(verdictCfg.panel || 1, 10) || 1;
        let r;
        if (panelN > 1) {
          // Perspective-diverse panel: run N refuters, aggregate by refute_if. Fail CLOSED if any
          // panelist yields no boolean verdict — an inconclusive panelist can't certify a pass.
          const rule = verdictCfg.refute_if || 'majority';
          const verdicts = [], findings = [];
          for (let i = 0; i < panelN; i++) {
            const ri = await dispatch(c.refuteCmd, 'refute', payload, null, 0, undefined, refExtraArg);
            if (!ri.json || typeof ri.json.refuted !== 'boolean') {
              escalate('review_error', `${gate}: panelist ${i + 1}/${panelN} returned no verdict (fail-closed)`); return 1;
            }
            verdicts.push(ri.json.refuted);
            // Only a panelist that produced ACTUAL text contributes a labelled finding — the
            // `[panelist …]` prefix must never let boilerplate satisfy the pass substance floor.
            const fi = (ri.json.findings || '').trim();
            if (fi) findings.push(`[panelist ${i + 1}/${panelN}] ${fi}`);
          }
          r = { json: { refuted: rprof.aggregateVerdict(verdicts, rule), findings: findings.join('\n\n') } };
        } else {
          r = await dispatch(c.refuteCmd, 'refute', payload, null, 0, undefined, refExtraArg);
        }
        if (!r.json || typeof r.json.refuted !== 'boolean') {
          escalate('review_error', `${gate}: backend returned no verdict`); return 1;
        }
        if (r.json.refuted) {
          hb('review', gate, 'fail', r.json.findings || 'refuted', ...(rModel ? ['--model', rModel] : []));
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
          fs.writeFileSync(fpath, `# Refutation attempt for ${gate}\n\nRefuter: ${refuterId}\nVerdict: could not refute (refuted=false)\n\n${findings}\n`);
          hbAs(refuterActor, 'review', gate, 'pass', '--artifact', fpath, ...(rModel ? ['--model', rModel] : []));
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
