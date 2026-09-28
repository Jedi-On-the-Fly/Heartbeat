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
 *   hb changed <gate> [--json] what the phase exiting <gate> changed (anchors, below)
 *   hb constraints <gate> --prompt [--json] | --record <file.json> [--model <m>]
 *                              gate-time constraint author (constraint-first review)
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
const { execSync } = require('child_process');

const HB_DIR = process.env.HB_DIR || __dirname;
const PROJECT_DIR = path.dirname(HB_DIR);
const EVENTS = path.join(HB_DIR, 'events.jsonl');
const STATE  = path.join(HB_DIR, 'state.json');
const DAG    = path.join(HB_DIR, 'dag.json');
const LEASES = path.join(HB_DIR, 'leases');          // used by P4
const WLOCK  = path.join(HB_DIR, '.wlock');
const LOCK_STALE_S = parseInt(process.env.LOCK_STALE_S || '1800', 10);

const nowIso = () => new Date().toISOString();
const sleepMs = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

// v1.7: single source of truth for the tick protocol (reason → action). Rendered
// into: the tick's self-describing `data.action`, `.hb/PROTOCOL.md`, and `hb protocol`.
// Keeping it here means it is always version-matched to the tick that emits reasons.
const PROTOCOL = {
  next_task:          'hb start <id> → do the work → hb done <id> (or hb fail <id> if you could not complete it). Never hand-edit state.json.',
  gate_pending:       'bash .hb/gate.sh <gate> — a pass advances the phase, UNLESS the gate has a review block (then a review is owed next).',
  review_pending:     'Spawn a skeptical sub-agent to REFUTE that the phase is done (hollow tests? faked output?) — seed it with `node .hb/hb.js refute-prompt <gate>` (the composed refute prompt: the gate\'s profile persona + a falsification question per criterion + the review angle). Spawn the refuter ON the profile\'s model: read it via `node .hb/hb.js refute-prompt <gate> --json` (.model) and pass it to your agent-spawning tool; inherit the session model only when it is null. Write its full attempt to a findings file, then: node .hb/hb.js review <gate> fail "<holes>" --model <that model>  OR  node .hb/hb.js review <gate> pass --artifact <findings-file> --model <that model> (a pass MUST cite the refuter\'s written attempt — no rubber-stamps; --model records WHAT reviewed, so the per-model impact report has truth to count).',
  gate_blocked:       'Run: node .hb/hb.js diagnose — fix the ROOT cause (do NOT weaken the gate), then re-run bash .hb/gate.sh <gate>.',
  at_capacity:        'Nothing to do — max tasks already in flight. No action.',
  state_corrupted:    'node .hb/hb.js rebuild (replays events.jsonl). The tick self-heals this; only surfaces if the log itself is unusable.',
  dag_corrupted:      'Restore dag.json from git/backup — its structure is immutable.',
  deadlock:           'Run: node .hb/hb.js diagnose — active_orphan: free the IDs; dag_invalid: fix the DAG and re-lint.',
  unsanctioned_drift: 'Review the diff. If the change is intended: bash .hb/tick.sh --freeze.',
  gate_rot:           'Run: node .hb/hb.js diagnose — a completed phase\'s gate references a deleted file; restore it or re-point the gate.',
  build_stuck:        'Run: node .hb/hb.js diagnose — woken repeatedly without progress; root-cause it or surface a blocker report for a human.',
  review_stuck:       'The adversarial review never resolved — spawn the refuter, write its findings to a file, and record hb review <gate> fail "<holes>" or hb review <gate> pass --artifact <file>, or surface for a human.',
  all_done:           'Write the final project report.',
};
function renderProtocolMd() {
  let md = '# HeartBeat — tick protocol\n\nWhen a tick returns `wakeAgent:true`, act on `data.reason`. The tick also embeds\nthe action for the current reason in `data.action`. Full reference:\n\n| reason | action |\n|---|---|\n';
  for (const [r, a] of Object.entries(PROTOCOL)) md += `| \`${r}\` | ${a.replace(/\|/g, '\\|')} |\n`;
  md += '\nNever hand-edit `state.json` — it is a projection of `events.jsonl`; mutate state\nonly through the `hb` CLI.\n';
  return md;
}

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
    pending_reviews: [],
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
  // v1.4: per-gate progress. det = deterministic gate passed; rev = adversarial
  // review passed. A phase completes only when det AND (review not required OR rev).
  const gateState = {};
  const gs = (g) => (gateState[g] ||= { det: false, rev: false });

  for (const ev of events) {
    switch (ev.event) {
      case 'initialized':
        completed.clear(); active.clear();
        for (const k of Object.keys(gateState)) delete gateState[k];
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
      case 'gate_passed':
        gs(ev.gate).det = true;
        s.gate.errors = 0; s.build_stuck_count = 0;
        break;
      case 'gate_failed':
        gs(ev.gate).det = false;
        s.gate.errors = 1; s.build_stuck_count += 1;
        break;
      case 'review_passed':          // v1.4: adversarial reviewer could not refute
        gs(ev.gate).rev = true;
        break;
      case 'review_failed':          // v1.4: reviewer found holes → re-run the gate
        gs(ev.gate).det = false; gs(ev.gate).rev = false;
        s.gate.errors = 1; s.build_stuck_count += 1;
        break;
      default: /* audit-only event → no state change */ break;
    }
    if (ev.event) s.last_event = ev.event;
  }

  const phases = dag.phases || [];
  const gates  = dag.gates  || {};
  const completedPhases = new Set();
  const pendingReviews  = [];
  for (const phase of phases) {
    const G = phase.gate_exit;
    if (!G) continue;
    const st = gateState[G];
    if (!st || !st.det) continue;
    const reviewRequired = !!(gates[G] && gates[G].review);
    if (reviewRequired && !st.rev) continue;      // deterministic pass, review owed
    completedPhases.add(phase.id);
  }
  for (const G of Object.keys(gates)) {
    if (gates[G].review && gateState[G] && gateState[G].det && !gateState[G].rev) pendingReviews.push(G);
  }

  s.completed_tasks = [...completed];
  s.active_tasks = [...active];
  s.completed_phases = [...completedPhases];
  s.pending_reviews = pendingReviews;             // v1.4

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

const ACTOR = process.env.HB_ACTOR || 'unknown';

function appendEvent(ev) {
  ev.ts = ev.ts || nowIso();
  if (ev.actor === undefined) ev.actor = ACTOR;   // who recorded this (identity for adversarial review)
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

// v1.5: static integrity check. The headline is rot detection — a COMPLETED phase
// whose gate references a file that no longer exists (that gate can no longer be
// reproduced). Also surfaces DAG errors, state/log drift, and stale leases. Read-only.
function doctor() {
  const dag = readDag();
  const state = project(readEvents(), dag);
  const gates = dag.gates || {}, phases = dag.phases || [];
  const completed = new Set(state.completed_phases);
  const { lint, extractPaths } = require('./hb-lint.js');
  const problems = [], notes = [];

  const gateToPhase = {};
  for (const p of phases) if (p.gate_exit) gateToPhase[p.gate_exit] = p.id;
  for (const [g, gv] of Object.entries(gates)) {
    const phaseId = gateToPhase[g];
    const isDone = phaseId && completed.has(phaseId);
    for (const c of (gv.criteria || [])) {
      for (const rel of extractPaths(c.cmd || '')) {
        if (fs.existsSync(path.join(PROJECT_DIR, rel.replace(/\/$/, '')))) continue;
        (isDone ? problems : notes).push(
          `${g} [${c.id}] → missing ${rel}` +
          (isDone ? ` (phase ${phaseId} DONE — gate no longer reproducible)`
                  : ` (phase ${phaseId || '?'} not built yet)`));
      }
    }
  }

  for (const e of lint(dag).errors) problems.push(`dag: ${e}`);

  let onDisk = null;
  try { onDisk = JSON.parse(fs.readFileSync(STATE, 'utf8')); } catch (e) {}
  if (onDisk) {
    const k = s => JSON.stringify([...(s || [])].sort());
    if (k(onDisk.completed_tasks) !== k(state.completed_tasks) ||
        k(onDisk.completed_phases) !== k(state.completed_phases)) {
      notes.push('state.json differs from the event-log projection — run: hb rebuild');
    }
  }

  try {
    for (const t of fs.readdirSync(LEASES)) {
      const age = (Date.now() - fs.statSync(path.join(LEASES, t)).mtimeMs) / 1000;
      if (age > LOCK_STALE_S) notes.push(`stale lease ${t} (~${Math.round(age)}s) — a tick will reclaim it`);
    }
  } catch (e) {}

  // Sev-1: every review_passed must remain backed by a readable, substantive artifact.
  // A pass whose findings file is gone/emptied is un-reinspectable = rot.
  {
    const passedRev = {};
    for (const e of readEvents()) {
      if (e.event === 'review_passed') passedRev[e.gate] = e;
      if (e.event === 'review_failed') delete passedRev[e.gate];
    }
    for (const [g, e] of Object.entries(passedRev)) {
      const rel = e.artifact || `reviews/${g}.md`;
      let body = null;
      try { body = fs.readFileSync(path.join(HB_DIR, rel), 'utf8'); } catch (x) {}
      if (body == null) problems.push(`${g} review_passed but backing artifact ${rel} is missing — the refutation can no longer be inspected (Sev-1 rot)`);
      else if (body.trim().length < 40) problems.push(`${g} review_passed but backing artifact ${rel} is empty/thin — not a real refutation`);
    }
  }

  // Restore points: every ACCEPTED gate (review gate: last review verdict is a pass; review-less: a
  // gate_passed) must have no restore failure after its last acceptance and — if its recorded policy
  // was autocommit-on — its git tag (legacy events carry neither, so they are never flagged). The
  // acceptance-ANCHOR check applies only once anchors exist (a log that predates them has no _start).
  {
    const anchored = !!readAnchor('_start');
    // acc: the gate's LAST acceptance event; rpf: a restore_point_failed that follows it.
    const acc = {}, rpf = {};
    for (const e of readEvents()) {
      const rev = !!((gates[e.gate] || {}).review);
      if ((e.event === 'review_passed' && rev) || (e.event === 'gate_passed' && !rev)) { acc[e.gate] = e; delete rpf[e.gate]; }
      else if (e.event === 'review_failed') { delete acc[e.gate]; delete rpf[e.gate]; }
      else if (e.event === 'restore_point_failed' && acc[e.gate]) rpf[e.gate] = e;
    }
    let gitOk = true;   // git absent from PATH ⇒ tag state unknown ⇒ tag checks skipped (never a false alarm)
    try { require('child_process').execFileSync('git', ['--version'], { stdio: 'ignore' }); } catch (x) { gitOk = false; }
    for (const g of Object.keys(gates)) {
      const e = acc[g];
      if (!e) continue;
      if (anchored && !readAnchor(g)) problems.push(`${g} accepted but has no acceptance anchor (.hb/anchors/${g}.json) — hb changed cannot report its phase`);
      if (rpf[g]) problems.push(`${g} accepted but its restore point failed (git ${rpf[g].step}) — no tag certifies the accepted state`);
      else if (gitOk && e.git && e.git.autocommit === true) {
        let tagged = false;
        try { require('child_process').execFileSync('git', ['-C', PROJECT_DIR, 'rev-parse', '-q', '--verify', `refs/tags/${g}`], { stdio: 'ignore' }); tagged = true; } catch (x) {}
        if (!tagged) problems.push(`${g} accepted with autocommit on but has no git tag ${g} — no restore point`);
      }
    }
  }

  // A constrained review pass: the stored artifact must still answer the ids it answered.
  {
    const lastPass = {};
    for (const e of readEvents()) {
      if (e.event === 'review_passed') lastPass[e.gate] = e;
      if (e.event === 'review_failed') delete lastPass[e.gate];
    }
    for (const [g, e] of Object.entries(lastPass)) {
      if (!Array.isArray(e.constraint_ids)) continue;
      let raw = null;
      try { raw = fs.readFileSync(path.join(HB_DIR, e.artifact || `reviews/${g}.md`)); } catch (x) {}
      if (raw === null) continue;   // a missing artifact is already a Sev-1 problem above
      const a = checkAnswers(raw.toString('utf8'), e.constraint_ids);
      const shaOk = !e.artifact_sha256 || require('crypto').createHash('sha256').update(raw).digest('hex') === e.artifact_sha256;
      if (!shaOk || a.errors.length || JSON.stringify(a.counts) !== JSON.stringify(e.answers))
        problems.push(`${g} review_passed answers no longer hold in ${e.artifact || `reviews/${g}.md`} (${!shaOk ? 'the artifact bytes changed since the pass' : (a.errors[0] || 'answer counts changed')}) — the stored refutation was altered`);
    }
  }

  // Recorded gate-time constraints must still be the bytes that were recorded (they are the review's
  // targets; an edit after recording silently moves them).
  {
    const lastRec = {};
    for (const e of readEvents()) if (e.event === 'constraints_recorded') lastRec[e.gate] = e;
    for (const [g, e] of Object.entries(lastRec)) {
      let raw = null;
      try { raw = fs.readFileSync(path.join(HB_DIR, 'constraints', `${g}.json`)); } catch (x) {}
      if (raw === null) problems.push(`${g} recorded constraints .hb/constraints/${g}.json are missing — the review's targets can no longer be inspected`);
      else if (require('crypto').createHash('sha256').update(raw).digest('hex') !== e.sha256)
        problems.push(`${g} recorded constraints .hb/constraints/${g}.json changed since recording (sha256 mismatch) — the review's targets were altered`);
    }
  }

  return { problems, notes };
}

// v1.7: read-only, never throws. Compute-what-you-can root-cause for a blocked state.
function sh(cmd) {
  try { return execSync(cmd, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 8000 }); }
  catch (e) { return (e && e.stdout) || ''; }
}
function diagnose(reason) {
  const dag = readDag(), events = readEvents(), state = project(events, dag);
  const out = [];
  const P = s => out.push(s);

  if (!reason) {   // infer the most pressing blocker
    if ((state.gate && state.gate.errors) > 0) reason = 'gate_blocked';
    else if (doctor().problems.some(p => /no longer reproducible/.test(p))) reason = 'gate_rot';
    else if ((state.pending_reviews || []).length) reason = 'review_stuck';
    else if ((state.build_stuck_count || 0) >= 5) reason = 'build_stuck';
    else { try { const { resolve } = require('./hb-next-task.js'); const r = resolve(state, dag, HB_DIR); if (r && r.type === 'deadlock') reason = 'deadlock'; } catch (e) {} }
  }
  P(`Diagnosis: ${reason || 'no blocker detected'}`);
  if (!reason) { P('  Not currently blocked. Run: node .hb/hb.js state'); return out.join('\n'); }

  if (reason === 'gate_blocked') {
    let g = null;
    for (let i = events.length - 1; i >= 0 && !g; i--) if (['gate_failed', 'gate_passed'].includes(events[i].event)) g = events[i].gate;
    if (!g) { const p = (dag.phases || []).find(p => !state.completed_phases.includes(p.id)); g = p && p.gate_exit; }
    P(`  Gate: ${g}`);
    P('  Observe (read-only re-run):');
    const fails = sh(`bash "${HB_DIR}/gate.sh" --check "${g}"`).split('\n').filter(l => l.includes('✗'));
    (fails.length ? fails : ['   (run: bash .hb/gate.sh --check ' + g + ')']).forEach(l => P('   ' + l.trim()));
    P(`  Attempts: this gate has failed ${events.filter(e => e.event === 'gate_failed' && e.gate === g).length}× (build_stuck at 5).`);
    P('  Recover:');
    P('   1. Root-cause each ✗ from its real output — fix the CODE, not the test.');
    P(`   2. bash .hb/gate.sh --check ${g}   (read-only) until all ✓.`);
    P(`   3. Then bash .hb/gate.sh ${g} for real.`);
    P('  Do NOT weaken a criterion to make it pass. If you have tried the same fix twice, surface for a human.');
  } else if (reason === 'gate_rot') {
    P('  Observe: a completed phase\'s gate references a file that no longer exists.');
    for (const pr of doctor().problems.filter(p => /no longer reproducible/.test(p))) {
      P('   ' + pr);
      const m = pr.match(/missing (\S+)/);
      if (m) { const del = sh(`git -C "${PROJECT_DIR}" log --diff-filter=D --oneline -1 -- "${m[1]}"`).trim(); if (del) P(`     traced: deleted in ${del}`); }
    }
    P('  Recover:');
    P('   1. Was that coverage genuinely moved? Confirm a current spec asserts the same behavior.');
    P('   2. If yes → re-point the gate criterion in .hb/dag.json.');
    P('   3. If no  → restore the file: git checkout <commit>^ -- <file>.');
    P('   4. Re-verify read-only: bash .hb/gate.sh --all.  Do NOT weaken the criterion.');
  } else if (reason === 'deadlock') {
    let r = {}; try { const { resolve } = require('./hb-next-task.js'); r = resolve(state, dag, HB_DIR) || {}; } catch (e) {}
    P(`  Cause: ${r.cause || 'unknown'}`);
    if (r.cause === 'active_orphan') P('  Recover: free the orphan IDs (hb fail <id>): ' + JSON.stringify((r.detail || {}).tasks || []));
    else if (r.cause === 'dag_invalid') P('  Recover: fix the DAG, then: node .hb/hb-lint.js .hb/dag.json\n  ' + JSON.stringify((r.detail || {}).errors || []));
    else P('  Recover: no eligible task — run node .hb/hb-lint.js .hb/dag.json and check requires/gates.');
  } else if (reason === 'build_stuck') {
    let task = null;
    for (let i = events.length - 1; i >= 0 && !task; i--) if (events[i].event === 'wake' && events[i].task) task = events[i].task;
    P(`  Task: ${task || '(unknown)'} — woken ${events.filter(e => e.event === 'wake' && e.task === task).length}×, failed ${events.filter(e => e.event === 'task_failed' && e.task === task).length}×, stuck_count=${state.build_stuck_count}.`);
    P('  Recover:');
    P('   1. Read what happened each attempt (events.jsonl). Are you repeating the same fix?');
    P('   2. If genuinely blocked, produce a blocker report and surface for a human.');
    P(`   3. If it is an orphan (started, never finished): node .hb/hb.js fail ${task || '<id>'}.`);
  } else if (reason === 'review_stuck') {
    const g = (state.pending_reviews || [])[0];
    P(`  Gate awaiting review: ${g}`);
    P('  Recover:');
    P('   1. Spawn a skeptical sub-agent to REFUTE that the phase is done.');
    P(`   2. Record the verdict: node .hb/hb.js review ${g} pass|fail "<findings>".`);
  } else {
    P('  (no structured diagnosis for this reason — see: node .hb/hb.js protocol ' + reason + ')');
  }
  return out.join('\n');
}

// ── Restore points: the git policy in force + a snapshot whose failures are LOUD ──
// autocommit = HB_NO_GIT unset AND HB_GIT_AUTOCOMMIT != 0 AND git present AND inside a worktree.
// It is recorded on the acceptance event (git:{autocommit}) so doctor judges a missing tag by the
// policy of the time, not of the day doctor runs.
function gitPolicy() {
  if (process.env.HB_NO_GIT || process.env.HB_GIT_AUTOCOMMIT === '0') return false;
  return inGitWorktree();
}
function gitSnapshot(gate, msg) {
  const cp = require('child_process');
  const run = (args) => { try { cp.execFileSync('git', args, { stdio: ['ignore', 'ignore', 'pipe'] }); return null; }
                          catch (e) { return ((e.stderr || '').toString().trim().split('\n').pop()) || e.message; } };
  const failed = (step, error) => {
    process.stderr.write(`⚠ restore point for ${gate}: git ${step} failed — ${error}\n`);
    mutate({ event: 'restore_point_failed', gate, step, error });
  };
  // A failed add/commit returns BEFORE tagging: a tag on the pre-phase HEAD would make the
  // documented restore (git reset --hard <GATE>) silently discard the phase's work.
  let err = run(['-C', PROJECT_DIR, 'add', '-A']);
  if (err) return failed('add', err);
  // Nothing staged ⇒ nothing to commit: not a failure (the tag then marks the current HEAD).
  if (run(['-C', PROJECT_DIR, 'diff', '--cached', '--quiet']) !== null) {
    err = run(['-c', 'user.name=HeartBeat', '-c', 'user.email=heartbeat@local', '-C', PROJECT_DIR, 'commit', '-q', '--no-verify', '-m', msg]);
    if (err) return failed('commit', err);
  }
  err = run(['-C', PROJECT_DIR, 'tag', '-f', gate]);
  if (err) failed('tag', err);
}

// ── Anchors: HeartBeat's own record of the tree at plan start and at each gate acceptance ──
// .hb/anchors/<name>.json = {gate, ts, commit, files:{path:sha256}}. Listing: inside a git
// worktree `git ls-files -co --exclude-standard` (read-only: HB_NO_GIT only disables writes);
// outside git a walk that skips ANCHOR_SKIP dirs at any depth. .hb/ and .git/ are never listed;
// only regular files are hashed. `hb changed` diffs two anchors (or an anchor vs the live tree).
const ANCHORS = path.join(HB_DIR, 'anchors');
const ANCHOR_SKIP = new Set(['.hb', '.git', 'node_modules', '__pycache__', '.venv']);
function inGitWorktree() {
  try {
    return require('child_process').execFileSync('git', ['-C', PROJECT_DIR, 'rev-parse', '--is-inside-work-tree'],
      { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim() === 'true';
  } catch (e) { return false; }
}
function listProjectFiles() {
  const hbRel = path.relative(PROJECT_DIR, HB_DIR).split(path.sep).join('/');
  let rels = [];
  if (inGitWorktree()) {
    const out = require('child_process').execFileSync('git', ['-C', PROJECT_DIR, 'ls-files', '-co', '--exclude-standard', '-z'],
      { stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 1 << 28 }).toString();
    rels = out.split('\0').filter(Boolean);
  } else {
    const walk = (rel) => {
      let ents = [];
      try { ents = fs.readdirSync(path.join(PROJECT_DIR, rel), { withFileTypes: true }); } catch (e) { return; }
      for (const d of ents) {
        const r = rel ? rel + '/' + d.name : d.name;
        if (d.isDirectory()) { if (!ANCHOR_SKIP.has(d.name)) walk(r); }
        else rels.push(r);
      }
    };
    walk('');
  }
  const files = {};
  for (const r of rels.sort()) {
    if (r === hbRel || r.startsWith(hbRel + '/') || r.split('/')[0] === '.git') continue;
    const abs = path.join(PROJECT_DIR, r);
    let st;
    try { st = fs.lstatSync(abs); } catch (e) { continue; }   // tracked but deleted from the worktree
    if (!st.isFile()) continue;
    try { files[r] = hashFile(abs); } catch (e) { continue; }   // unreadable (EACCES…): skipped, as python does
  }
  return files;
}
function hashFile(abs) {   // streamed in chunks — no whole-file buffer (files past 2 GiB hash too)
  const h = require('crypto').createHash('sha256'), buf = Buffer.allocUnsafe(1 << 20);
  const fd = fs.openSync(abs, 'r');
  try { let n; while ((n = fs.readSync(fd, buf, 0, buf.length, null)) > 0) h.update(buf.subarray(0, n)); }
  finally { fs.closeSync(fd); }
  return h.digest('hex');
}
function writeAnchor(name) {
  let commit = null;
  if (inGitWorktree()) {
    try { commit = require('child_process').execFileSync('git', ['-C', PROJECT_DIR, 'rev-parse', 'HEAD'], { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim() || null; } catch (e) {}
  }
  const a = { gate: name, ts: nowIso(), commit, files: listProjectFiles() };
  fs.mkdirSync(ANCHORS, { recursive: true });
  atomicWrite(path.join(ANCHORS, `${name}.json`), JSON.stringify(a, null, 2) + '\n');
  return a;
}
// Report, never swallow: an anchor that silently fails to write would make `changed` lie later.
// Write-once: an accepted gate's anchor is its acceptance record — re-running the gate later must
// not move it (later phases' work would leak into its report).
function tryAnchor(name) {
  if (readAnchor(name)) return true;
  try { writeAnchor(name); return true; }
  catch (e) { process.stderr.write(`⚠ anchor ${name} not recorded: ${e.message}\n`); return false; }
}
function readAnchor(name) {
  try { return JSON.parse(fs.readFileSync(path.join(ANCHORS, `${name}.json`), 'utf8')); } catch (e) { return null; }
}
// changed(gate) → {gate, base, target, added, modified, deleted}: the phase's entry anchor (its
// gate_entry's, or _start) vs the gate's own anchor once accepted, else the live working tree.
function changed(gate) {
  const phase = (readDag().phases || []).find(p => p.gate_exit === gate);
  if (!phase) throw new Error(`no phase exits through gate ${gate}`);
  const base = phase.gate_entry || '_start';
  const from = readAnchor(base);
  if (!from) throw new Error(`no entry anchor '${base}' for ${gate} (recorded at the first task start / the entry gate's acceptance)`);
  const own = readAnchor(gate);
  const to = own ? own.files : listProjectFiles();
  const a = from.files || {};
  const out = { gate, base, target: own ? gate : 'worktree', added: [], modified: [], deleted: [] };
  for (const p of Object.keys(to).sort()) {
    if (!(p in a)) out.added.push(p); else if (a[p] !== to[p]) out.modified.push(p);
  }
  for (const p of Object.keys(a).sort()) if (!(p in to)) out.deleted.push(p);
  return out;
}

// ── Gate-time constraint author (constraint-first review) ──
// A CONSTRAINED gate has non-empty plan-time review.constraints. At review time an author who did
// not do the work writes G-id constraints from the plan + what the phase changed; HeartBeat records
// them once per REVIEW CYCLE (a deterministic pass leaving the gate review_pending, until its review
// verdict) as .hb/constraints/<gate>.json + a constraints_recorded {gate, ids, sha256, actor, model}.
function planConstraints(dag, gate) {
  const cs = ((((dag.gates || {})[gate] || {}).review) || {}).constraints;
  return Array.isArray(cs) ? cs : [];
}
function phaseDoers(dag, gate, events) {
  const ph = (dag.phases || []).find(p => p.gate_exit === gate);
  const ids = new Set(((ph && ph.tasks) || []).map(t => t.id));
  const doers = new Set();
  for (const e of events) if (e.event === 'task_done' && ids.has(e.task) && e.actor && e.actor !== 'unknown') doers.add(e.actor);
  return doers;
}
// The current review cycle of <gate>: pending (review owed) + whether a set was recorded in it. A
// cycle starts after the gate's last REVIEW VERDICT — re-running the gate while the review is owed
// (a new gate_passed) must NOT start a new cycle, or a second author could re-record a weaker set.
function reviewCycle(dag, gate) {
  const events = readEvents();
  const pending = (project(events, dag).pending_reviews || []).includes(gate);
  let start = -1;
  events.forEach((e, i) => { if ((e.event === 'review_failed' || e.event === 'review_passed') && e.gate === gate) start = i; });
  const recorded = events.some((e, i) => i > start && e.event === 'constraints_recorded' && e.gate === gate);
  return { pending, recorded, events, start };
}
// The refuter's per-id answers (constraint-first review). One line per id:
//   <ID>: VIOLATED | NOT-REPRODUCED | N/A — <evidence or reason>
// Markdown-insensitive (list bullets, quotes, headings, *, _, ` are ignored) and case-insensitive on the
// status. Prose that merely mentions an id is not an answer. Twin: review_policy.check_answers.
// EXPLICIT rules, identical in both runtimes (JS and python primitives disagree on line breaks, trim
// sets and Unicode case folding — refuter catches). Each line: split on ANY line break; terminal escape
// sequences, control characters and invisible characters removed; markdown emphasis removed; list
// markers (-, *, +, >, #, "1.", "2)") removed; matched on an ASCII-only lowercased copy (no regex case
// folding). The rule is by CONTENT, not by shape: a line that says "violated" is refused unless it is a
// well-formed non-VIOLATED answer, and a line naming a constraint id with a status must be well-formed —
// so a violation can never sit in the artifact, in any layout, next to a clean answer.
const ANSWER_BREAKS = /\r\n|[\n\r\v\f\x1c\x1d\x1e\x85\u2028\u2029]/;
const ANSWER_INVISIBLE = /[​-‏⁠-⁤﻿­᠎͏؜]/g;
const ANSWER_ANSI = /\x1b\[[0-9;?]*[ -\/]*[@-~]|\x1b[@-_]/g;
const ANSWER_CTRL = /[\x00-\x08\x0b-\x1f\x7f]/g;
function checkAnswers(body, required) {
  const req = new Set(required), seen = {}, errors = [], counts = { violated: 0, not_reproduced: 0, na: 0 };
  const FMT = require('./refuter_profiles.js').ANSWER_FORMAT;
  let loose = 0, looseId = 0, inComment = false;
  for (const raw of String(body).split(ANSWER_BREAKS)) {
    // an HTML comment is invisible when rendered: an answer inside one is refused (a violation inside
    // one is refused by the content rule below, like anywhere else)
    const commented = inComment || raw.includes('<!--');
    if (raw.includes('<!--')) inComment = !/<!--[\s\S]*-->/.test(raw.slice(raw.lastIndexOf('<!--')));
    else if (inComment && raw.includes('-->')) inComment = false;
    const l = raw.replace(ANSWER_ANSI, '').replace(ANSWER_CTRL, '').replace(ANSWER_INVISIBLE, '').replace(/[*`_]/g, '')
      .replace(/^[ \t]+|[ \t]+$/g, '').replace(/^(?:[\t >+#-]+|[0-9]+[.)][ \t]+)+/, '');
    const lo = l.replace(/[A-Z]/g, c => c.toLowerCase());   // ASCII-only: no regex case folding
    const m = /^([pg][0-9]+)[ \t]*[:：][ \t]*(violated|not-reproduced|not reproduced|n\/a)(?=$|[ \t—–:,.;])(.*)$/.exec(lo);
    const head = /^([pg][0-9]+)[ \t]*[:：]/.exec(lo);
    if (head && (!m || commented)) {   // shaped like an answer but malformed (or hidden in a comment): refused
      errors.push(`${head[1].toUpperCase()} has an answer-shaped line that is not a visible, well-formed answer (${FMT})`);
      continue;
    }
    if (!m) {
      if (/(^|[^a-z0-9])violated([^a-z0-9]|$)/.test(lo)) loose++;
      else if (/(^|[^a-z0-9])[pg][0-9]+([^0-9]|$)/.test(lo) && /(not[- ]?reproduced|n\/a)/.test(lo)) looseId++;
      continue;
    }
    const id = m[1].toUpperCase(), st = m[2].toUpperCase().replace(' ', '-');
    const rest = m[3].replace(/^[ \t]*[—–:,.;-]+/, '');
    if (!req.has(id)) { errors.push(`${id} is not a constraint of this gate (an unknown id was answered)`); continue; }
    if (seen[id]) { errors.push(`${id} is answered twice — one line per id`); continue; }
    seen[id] = st;
    if (st === 'VIOLATED') { counts.violated++; errors.push(`${id} is answered VIOLATED — a violation is a finding: record it with hb review <gate> fail "<finding>"`); }
    else if (!ANSWER_TEXT.test(rest)) errors.push(`${id} is answered ${st} without ${st === 'N/A' ? 'a reason' : 'evidence (the probe you ran)'}`);
    else if (st === 'N/A') counts.na++;
    else counts.not_reproduced++;
  }
  if (loose) errors.push(`the artifact says VIOLATED outside a well-formed answer line (${loose} line(s)) — a violation is a finding: record it with hb review <gate> fail "<finding>"; otherwise answer each id exactly (${FMT})`);
  if (looseId) errors.push(`a line names a constraint id with a status but is not a well-formed answer (${looseId} line(s)) — answer each id exactly (${FMT})`);
  for (const id of required) if (!seen[id]) errors.push(`${id} has no answer line (${FMT})`);
  return { errors, counts };
}
// evidence / a reason must contain a character that is not whitespace or invisible (ONE explicit set,
// identical in python)
const ANSWER_TEXT = /[^ \t   -   　⠀ㅤﾠᅟᅠ]/;

// A path shown to an agent: control characters (a newline in a file name) would let a doer forge
// prompt sections, so such a path is rendered JSON-quoted. Twin: anchors.safe_path.
function safePath(p) { return /[\x00-\x1f\x7f]/.test(p) ? JSON.stringify(p) : p; }
// A gate id used as a file name must stay inside .hb/constraints/.
const SAFE_GATE_ID = /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/;
// The gate-time set recorded in THIS review cycle (empty when none). Refuses a set whose bytes no
// longer match its constraints_recorded event (fail closed: the review's targets were altered).
function recordedConstraints(gate) {
  const dag = readDag();
  const cyc = reviewCycle(dag, gate);
  if (!cyc.recorded) return [];
  let ev = null;
  for (const e of cyc.events) if (e.event === 'constraints_recorded' && e.gate === gate) ev = e;
  let raw;
  try { raw = fs.readFileSync(path.join(HB_DIR, 'constraints', `${gate}.json`)); }
  catch (e) { throw new Error(`the recorded constraints of ${gate} are missing (.hb/constraints/${gate}.json)`); }
  if (require('crypto').createHash('sha256').update(raw).digest('hex') !== ev.sha256)
    throw new Error(`the recorded constraints of ${gate} changed since recording (sha256 mismatch) — refusing to compose against altered targets`);
  return JSON.parse(raw.toString('utf8'));
}
function composeAuthorPrompt(dag, gate) {
  const ph = (dag.phases || []).find(p => p.gate_exit === gate) || { id: '?', tasks: [] };
  const gv = (dag.gates || {})[gate] || {};
  const L = [];
  L.push(`You are the CONSTRAINT AUTHOR for HeartBeat gate ${gate} (phase ${ph.id}: ${ph.title || ph.id}).`);
  L.push('Write falsifiable constraints on the behaviour this phase claims to deliver — do not hunt for bugs and do not judge the work; a separate refuter will test each constraint you write.');
  L.push('');
  L.push(`## Phase ${ph.id}: ${ph.title || ph.id}`);
  if (typeof ph.desc === 'string' && ph.desc) L.push(ph.desc);
  L.push('Tasks:');
  for (const t of (ph.tasks || [])) L.push(`  - ${t.id}: ${t.title || ''}${t.description ? ' — ' + t.description : ''}`);
  L.push('');
  L.push(`## Gate ${gate}`);
  L.push(typeof gv.desc === 'string' && gv.desc ? gv.desc : '(no description)');
  L.push('');
  L.push('## Plan-time constraints (fixed at plan time — do not repeat them)');
  for (const c of planConstraints(dag, gate)) {
    L.push(`  - ${c.id}: ${safePath(String(c.claim))}`);   // one line: a newline cannot forge a section
    L.push(`      subjects: ${(c.subjects || []).map(s => safePath(String(s))).join(', ')}`);
    L.push(`      violated if: ${safePath(String(c.violation))}`);
  }
  L.push('');
  let ch = null, why = null;
  try { ch = changed(gate); } catch (e) { why = e.message; }
  L.push(ch ? `## What this phase changed (${ch.base} → ${ch.target})` : '## What this phase changed');
  if (!ch) L.push(`  (unavailable: ${why})`);
  else {
    for (const [k, t] of [['A', ch.added], ['M', ch.modified], ['D', ch.deleted]]) for (const p of t) L.push(`  ${k} ${safePath(p)}`);
    if (!ch.added.length && !ch.modified.length && !ch.deleted.length) L.push('  (no changes)');
  }
  L.push('');
  L.push('## Your output');
  L.push('A JSON array, ids G1..Gn in order:');
  L.push('[{"id": "G1", "claim": "…", "subjects": ["…"], "violation": "…"}]');
  L.push('- claim: a property of the changed behaviour that the plan-time constraints do not already pin');
  L.push('- subjects: the files/areas it covers (from the change list above)');
  L.push('- violation: the concrete, observable result that would falsify it');
  L.push('Record it (as an actor who did not do this phase\'s work):');
  L.push(`  hb constraints ${gate} --record <file.json>`);
  return L.join('\n');
}

// Exported BEFORE the CLI dispatch: refuter_profiles.js requires this module while hb.js is running
// as the CLI (a circular require sees only what is already assigned).
module.exports = { project, phaseByGateExit, initialState, PROTOCOL, renderProtocolMd, withWlock, changed, recordedConstraints, safePath, checkAnswers };

// ── CLI ───────────────────────────────────────────────────────────────────────
// v1.7: guard the dispatch so hb.js is safely requirable (the tick requires it to
// read PROTOCOL). Without this, require() would run the switch → default → exit.
if (require.main === module) {
const [cmd, arg1, ...rest] = process.argv.slice(2);
const die = (msg) => { process.stderr.write(msg + '\n'); process.exit(1); };

switch (cmd) {
  case 'start':
    if (!arg1) die('usage: hb start <taskId>');
    fs.mkdirSync(LEASES, { recursive: true });
    try { fs.mkdirSync(path.join(LEASES, arg1)); } catch (e) { /* idempotent: tick may have leased it */ }
    // The plan's start anchor: taken on the first LIVE task_started only (never on rebuild/import).
    // "Is this the first?" is decided inside the write lock (exactly one caller can see a count of
    // 1); the tree hash runs AFTER release, so a large project never holds other writers past the
    // lock timeout.
    const first = withWlock(() => {
      appendEvent({ event: 'task_started', task: arg1 });
      const f = !readAnchor('_start') && readEvents().filter(e => e.event === 'task_started').length === 1;
      reproject();
      return f;
    });
    if (first) tryAnchor('_start');
    process.stdout.write(`started ${arg1}\n`);
    break;

  case 'anchor':
    // Internal: gate.sh records a review-less gate's acceptance anchor through this.
    if (!arg1) die('usage: hb anchor <gate>');
    if (!tryAnchor(arg1)) process.exit(1);
    break;

  case 'constraints': {
    const cArgs = [arg1, ...rest].filter(a => a !== undefined);
    const flag = (f) => cArgs.includes(f);
    const val = (f) => { const i = cArgs.indexOf(f); return i !== -1 ? cArgs[i + 1] : undefined; };
    const gate = cArgs.find((a, i) => !a.startsWith('--') && !['--record', '--model'].includes(cArgs[i - 1]));
    if (!gate || (!flag('--prompt') && !flag('--record')))
      die('usage: hb constraints <gate> --prompt [--json] | --record <file.json> [--model <m>]');
    const dag = readDag();
    if (!planConstraints(dag, gate).length)
      die(`hb constraints: ${gate} has no plan-time constraints (review.constraints) — constraint-first review applies to constrained gates only`);
    if (flag('--prompt')) {
      const prompt = composeAuthorPrompt(dag, gate);
      if (flag('--json')) {
        let prof = null;
        try { prof = require('./refuter_profiles.js').gateProfile(HB_DIR, ((dag.gates || {})[gate] || {}).review || {}); }
        catch (e) { die('hb constraints: ' + e.message); }
        process.stdout.write(JSON.stringify({ gate, prompt, model: (prof && prof.author_model) ?? null }) + '\n');
      } else process.stdout.write(prompt + '\n');
      break;
    }
    const file = val('--record');
    if (!file || file.startsWith('--')) die('hb constraints: --record needs <file.json>');
    if (cArgs.includes('--model') && (val('--model') === undefined || val('--model').startsWith('--')))
      die('hb constraints: --model needs a value');
    const model = val('--model') ?? null;
    if (!SAFE_GATE_ID.test(gate)) die(`hb constraints --record: gate id '${gate}' is not usable as a file name`);
    const actor = process.env.HB_ACTOR;
    const norm = (a) => String(a).trim().toLowerCase();
    let raw, list;
    try { raw = fs.readFileSync(path.isAbsolute(file) ? file : path.join(process.cwd(), file)); } catch (e) { die(`hb constraints --record: cannot read ${file} (${e.code || e.message})`); }
    // Strict JSON, identical in both runtimes: valid UTF-8 only (python rejects invalid bytes), and
    // JSON.parse already rejects NaN/Infinity (python is told to).
    try { list = JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(raw)); }   // ignoreBOM: a BOM stays in the text → JSON.parse refuses it, as python does
    catch (e) { die(`hb constraints --record: ${file} is not valid JSON (${e.message})`); }
    if (!Array.isArray(list) || !list.length) die('hb constraints --record: expected a non-empty JSON array of {id G<n>, claim, subjects, violation}');
    const errs = require('./hb-lint.js').constraintErrors(list, 'G');
    if (errs.length) die('hb constraints --record: ' + errs.join('; '));
    // Check-then-write under ONE write lock: two concurrent records cannot both see "not recorded".
    const verdict = withWlock(() => {
      const cyc = reviewCycle(dag, gate);
      if (!cyc.pending) return `hb constraints --record: ${gate} is not awaiting review — record after its deterministic pass (review_pending)`;
      if (cyc.recorded) return `hb constraints --record: a constraint set is already recorded for ${gate} in this review cycle — it is write-once until the review verdict`;
      if (!actor || norm(actor) === 'unknown') return 'hb constraints --record: set HB_ACTOR to the author\'s identity (the author must not have done this phase\'s work)';
      if ([...phaseDoers(dag, gate, cyc.events)].some(d => norm(d) === norm(actor)))
        return `hb constraints --record: '${actor}' did this phase's work — the constraint author must be a different actor`;
      const dir = path.join(HB_DIR, 'constraints');
      fs.mkdirSync(dir, { recursive: true });
      atomicWrite(path.join(dir, `${gate}.json`), raw);   // tmp + rename: replaces a planted symlink, never writes through it
      const sha256 = require('crypto').createHash('sha256').update(raw).digest('hex');
      appendEvent({ event: 'constraints_recorded', gate, ids: list.map(c => c.id), sha256, actor, model });
      reproject();
      return null;
    });
    if (verdict) die(verdict);
    process.stdout.write(`constraints recorded for ${gate}: ${list.map(c => c.id).join(', ')} (.hb/constraints/${gate}.json)\n`);
    break;
  }

  case 'changed': {
    const asJson = rest.includes('--json') || arg1 === '--json';
    const gate = arg1 === '--json' ? rest[0] : arg1;
    if (!gate) die('usage: hb changed <gate> [--json]');
    let c;
    try { c = changed(gate); } catch (e) { die(`hb changed: ${e.message}`); }
    if (asJson) { process.stdout.write(JSON.stringify(c) + '\n'); break; }
    process.stdout.write(`changes in the phase exiting ${gate} (${c.base} → ${c.target}):\n`);
    for (const [k, t] of [['A', c.added], ['M', c.modified], ['D', c.deleted]]) for (const p of t) process.stdout.write(`  ${k} ${safePath(p)}\n`);
    if (!c.added.length && !c.modified.length && !c.deleted.length) process.stdout.write('  (no changes)\n');
    break;
  }

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

  case 'review': {
    // Sev-1 hardening: a PASS is only accepted when backed by a stored refutation
    // artifact — the refuter's actual findings on disk — that (a) is substantive,
    // (b) cites real anchors from THIS phase, and (c) was recorded by a DIFFERENT
    // actor than the one who did the phase's work. Closes the self-pass hole.
    const gate = arg1, verdict = rest[0];
    const ai = rest.indexOf('--artifact');
    let artifact = null;
    if (ai !== -1) { artifact = rest[ai + 1]; rest.splice(ai, 2); }
    // --model: the model that reviewed — recorded on the event (null when omitted: honest,
    // never fabricated; interactive values are the recorder's self-report).
    const mi = rest.indexOf('--model');
    let model = null;
    if (mi !== -1) { model = rest[mi + 1] ?? null; rest.splice(mi, 2); }
    // The note must be ONE (quoted) argument — same rule as the python CLI. With a free-form
    // token list, a flag-shaped token INSIDE an unquoted note was consumed as --model,
    // fabricating provenance from note text and silently truncating the findings (GATE_RE2
    // refuter catch). Arity is the only reliable distinguisher (the executor legitimately
    // passes findings as one element with trailing flags), so: refuse loudly, never guess.
    const noteToks = rest.slice(1);
    if (noteToks.length > 1)
      die(`review: the note must be ONE (quoted) argument — got ${noteToks.length} tokens; refusing rather than guessing (a mis-parse could fabricate provenance).`);
    if (noteToks[0] && /^--\S+$/.test(noteToks[0]))
      die(`review: unrecognized flag-shaped token '${noteToks[0]}' in the note position — quote the note (refusing rather than guessing).`);
    const note = noteToks[0] || '';
    if (!gate || (verdict !== 'pass' && verdict !== 'fail' && verdict !== 'free'))
      die('usage: hb review <gate> pass|fail|free [--artifact <findings-file>] [--model <m>] [note]');
    if (verdict === 'fail') {
      mutate({ event: 'review_failed', gate, model, ...(note ? { note } : {}) });
      process.stdout.write(`review fail ${gate}\n`);
      break;
    }
    const vw = verdict === 'free' ? 'review free' : 'review pass';
    if (!artifact) die(verdict === 'free'
      ? 'review free requires --artifact <findings-file>: the free reviewer\'s written breadth review.'
      : 'review pass requires --artifact <findings-file>: the refuter\'s written attempt to break the phase (a pass must cite evidence, not just assert one).');
    const ap = path.isAbsolute(artifact) ? artifact : path.join(PROJECT_DIR, artifact);
    let body = '';
    try { body = fs.readFileSync(ap, 'utf8'); } catch (e) { die(`${vw}: cannot read artifact ${artifact} (${e.code || e.message})`); }
    if (body.trim().length < 40) die(`${vw}: artifact ${artifact} is too thin (${body.trim().length} chars) to be a real refutation attempt — a rubber-stamp is not a review.`);
    // Substance: a genuine refutation inspects THIS phase's actual work, so require the
    // artifact to cite real anchors — the gate id, a phase task id, or a path the gate's
    // criteria reference. Filler references none.
    const dag = readDag();
    const phaseForGate = (dag.phases || []).find(p => p.gate_exit === gate);
    const anchors = new Set([gate]);
    if (phaseForGate) { anchors.add(phaseForGate.id); for (const t of (phaseForGate.tasks || [])) anchors.add(t.id); }
    const { extractPaths } = require('./hb-lint.js');
    for (const c of (((dag.gates || {})[gate] || {}).criteria || []))
      for (const pth of extractPaths(c.cmd || '')) { anchors.add(pth); anchors.add(pth.split('/').pop()); }
    const hay = body.toLowerCase();
    const cited = [...anchors].filter(a => a && String(a).length > 1 && hay.includes(String(a).toLowerCase()));
    if (cited.length === 0)
      die(`${vw}: artifact ${artifact} does not reference the phase under review (it cites nothing real; expected one of: ${[...anchors].filter(a => a && String(a).length > 1).join(', ')}).`);
    // Identity: reject a self-review — a pass whose actor also recorded this phase's
    // task_done events is grading its own homework. Adjudicated only when actors are set.
    const reviewer = process.env.HB_ACTOR || 'unknown';
    const norm = (a) => String(a).trim().toLowerCase();
    if (reviewer !== 'unknown' && phaseForGate) {
      const phaseTaskIds = new Set((phaseForGate.tasks || []).map(t => t.id));
      const doers = new Set();
      for (const e of readEvents())
        if (e.event === 'task_done' && phaseTaskIds.has(e.task) && e.actor && e.actor !== 'unknown') doers.add(e.actor);
      if ([...doers].some(d => norm(d) === norm(reviewer)))
        die(`${vw}: reviewer '${reviewer}' also executed this phase's work — a self-review is not adversarial. Have a DIFFERENT actor refute (set HB_ACTOR).`);
    }
    // ── constraint-first review (a CONSTRAINED gate only; an unconstrained gate is unchanged) ──
    const constrained = planConstraints(dag, gate).length > 0;
    let answers = null, constraintIds = null;
    if (verdict === 'free') {
      if (!constrained) die(`review free: ${gate} has no plan-time constraints — the free review belongs to the constraint-first review of a constrained gate`);
      const cyc = reviewCycle(dag, gate);
      if (!cyc.pending) die(`review free: ${gate} is not awaiting review`);
      if (!reviewer || !norm(reviewer) || norm(reviewer) === 'unknown') die('review free: set HB_ACTOR to the free reviewer\'s identity');
      if ([...phaseDoers(dag, gate, cyc.events)].some(d => norm(d) === norm(reviewer)))
        die(`review free: '${reviewer}' did this phase's work — the free reviewer must be a different actor`);
      const revDirF = path.join(HB_DIR, 'reviews');
      fs.mkdirSync(revDirF, { recursive: true });
      fs.writeFileSync(path.join(revDirF, `${gate}.free.md`), body);
      const sha256 = require('crypto').createHash('sha256').update(body).digest('hex');
      mutate({ event: 'free_review_recorded', gate, actor: reviewer, model, artifact: `reviews/${gate}.free.md`, sha256 });
      process.stdout.write(`review free ${gate} recorded (reviews/${gate}.free.md, by ${reviewer})\n`);
      break;
    }
    if (constrained) {
      const cyc = reviewCycle(dag, gate);
      if (!cyc.recorded)
        die(`review pass refused on ${gate}: no gate-time constraints were recorded in this review cycle — run hb constraints ${gate} --prompt, have a non-doer author them, then hb constraints ${gate} --record <file.json>`);
      let gset;
      try { gset = recordedConstraints(gate); } catch (e) { die(`review pass refused on ${gate}: ${e.message}`); }
      constraintIds = planConstraints(dag, gate).map(c => c.id).concat(gset.map(c => c.id));
      const a = checkAnswers(body, constraintIds);
      if (a.errors.length) die(`review pass refused on ${gate}: ${a.errors.join('; ')}`);
      answers = a.counts;
      let prof = null;
      try { prof = require('./refuter_profiles.js').gateProfile(HB_DIR, ((dag.gates || {})[gate] || {}).review || {}); }
      catch (e) { die(`review pass refused on ${gate}: ${e.message}`); }
      if (prof && prof.free_review) {
        const ok = cyc.events.some((e, i) => i > cyc.start && e.event === 'free_review_recorded' && e.gate === gate &&
                                              norm(e.actor || '') !== norm(reviewer));
        if (!ok) die(`review pass refused on ${gate}: the profile requires a free review — record one in this review cycle from an actor other than '${reviewer}': hb review ${gate} free --artifact <file>`);
      }
    }
    const revDir = path.join(HB_DIR, 'reviews');
    try { fs.mkdirSync(revDir, { recursive: true }); } catch (e) {}
    fs.writeFileSync(path.join(revDir, `${gate}.md`), body);
    const autocommit = gitPolicy();
    mutate({ event: 'review_passed', gate, model, artifact: `reviews/${gate}.md`, artifact_chars: body.trim().length, cited, reviewer, git: { autocommit },
             ...(answers ? { answers, constraint_ids: constraintIds, artifact_sha256: require('crypto').createHash('sha256').update(body, 'utf8').digest('hex') } : {}),
             ...(note ? { note } : {}) });
    // Reviewed acceptance creates the phase's restore point (commit+tag) — deferred from the
    // deterministic pass so the tag only ever certifies a reviewed-good state.
    if (autocommit) {
      const p = (dag.phases || []).find(x => x.gate_exit === gate);
      gitSnapshot(gate, p ? `heartbeat(${p.id}): ${p.title} [${gate}]` : `heartbeat: ${gate} accepted`);
    }
    tryAnchor(gate);   // acceptance anchor — after the restore point, so its commit is the accepted HEAD
    process.stdout.write(`review pass ${gate} (backed by reviews/${gate}.md, ${body.trim().length} chars, cites: ${cited.slice(0, 3).join(', ')})\n`);
    break;
  }
  case 'evidence': {
    // The provenance of a gate's acceptance: what was proven, how, on which commit.
    const gate = arg1;
    if (!gate) die('usage: hb evidence <gate>');
    const evs = readEvents();
    const gp = [...evs].reverse().find(e => e.event === 'gate_passed' && e.gate === gate);
    if (!gp) { process.stdout.write(`no recorded gate pass for ${gate}\n`); break; }
    process.stdout.write(`evidence for ${gate} — runtime: ${gp.runtime || '?'}, commit: ${gp.commit || 'none'}\n`);
    for (const c of (gp.criteria || [])) process.stdout.write(`  [exit ${c.exit}] ${c.id}: ${c.cmd}\n`);
    const rp = [...evs].reverse().find(e => e.event === 'review_passed' && e.gate === gate);
    if (rp) process.stdout.write(`  reviewed by ${rp.reviewer || '?'} → ${rp.artifact}\n`);
    break;
  }

  case 'doctor': {
    const { problems, notes } = doctor();
    for (const n of notes)    process.stdout.write(`  ⚠ ${n}\n`);
    for (const p of problems) process.stdout.write(`  ✗ ${p}\n`);
    process.stdout.write(problems.length
      ? `✗ hb doctor: ${problems.length} problem(s), ${notes.length} note(s)\n`
      : `✓ hb doctor: healthy${notes.length ? ` (${notes.length} note(s))` : ''}\n`);
    process.exit(problems.length ? 1 : 0);
  }

  case 'diagnose':
    process.stdout.write(diagnose(arg1 && !arg1.startsWith('-') ? arg1 : null) + '\n');
    break;

  case 'protocol': {
    // v1.7: hb protocol            → the full reason→action table
    //       hb protocol <reason>   → one reason's action
    //       hb protocol --md       → PROTOCOL.md (rendered)
    //       hb protocol <reason> --oneline → bare action string (used by the tick)
    if (rest.includes('--md') || arg1 === '--md') { process.stdout.write(renderProtocolMd()); break; }
    const reason = (arg1 && !arg1.startsWith('--')) ? arg1 : null;
    if (reason) {
      const a = PROTOCOL[reason];
      if (!a) { process.stderr.write(`unknown reason: ${reason}\n`); process.exit(1); }
      process.stdout.write((rest.includes('--oneline') ? a : `${reason}: ${a}`) + '\n');
    } else {
      for (const [r, a] of Object.entries(PROTOCOL)) process.stdout.write(`${r}: ${a}\n`);
    }
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

  case 'ready': {
    // v1.4 (#4): the concurrently-runnable set — eligible, unleased, requires-
    // independent tasks (up to N). Fan these out as isolated parallel agents.
    const limit = arg1 ? Math.max(0, parseInt(arg1, 10) || 0) : 0;
    const { readyTasks } = require('./hb-next-task.js');
    const dag = readDag();
    const ready = readyTasks(project(readEvents(), dag), dag, HB_DIR, limit);
    process.stdout.write(JSON.stringify(ready) + '\n');
    break;
  }

  case 'refuters': {
    // `hb refuters new <name> [--from <starter>] [--lite]` scaffolds a new refuter; bare lists them.
    if (arg1 === 'new') {
      // Shared hand-parser (python twin: cli.py `refuters new`). Grammar: `<name>` FIRST (not a flag),
      // then [--from <v>|--from=<v>] [--lite], last --from wins. A flag before the name, a second
      // positional, `--`, or an unknown option errors — identically in both runtimes, by construction.
      if (rest[0] === undefined || rest[0].startsWith('-'))
        die('usage: hb refuters new <name> [--from <starter>] [--lite]');
      const name = rest[0];
      let from, lite = false;
      for (let i = 1; i < rest.length; i++) {
        const a = rest[i];
        if (a === '--lite') lite = true;
        else if (a === '--from') {
          if (rest[i + 1] === undefined || rest[i + 1].startsWith('--')) die('refuters new: --from requires a value');
          from = rest[++i];
        } else if (a.startsWith('--from=')) from = a.slice(7);
        else if (a.startsWith('--')) die('refuters new: unknown option ' + a);
        else die('refuters new: unexpected argument ' + a);
      }
      const { scaffold } = require('./refuter_profiles.js');
      let p;
      try { p = scaffold(HB_DIR, name, { from, lite }); }
      catch (e) { die('refuters new: ' + e.message); }
      process.stdout.write('wrote ' + p + '\n');
      break;
    }
    if (arg1) die('unknown refuters action: ' + arg1);
    // Discovery: the refuter profiles available to this project (.hb/refuters/, shipped ones
    // seeded by bootstrap + any project-authored). Sorted names, one per line — node ≡ python.
    const dir = path.join(HB_DIR, 'refuters');
    const names = new Set();
    try {
      for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        if (e.isFile() && e.name.endsWith('.json')) names.add(e.name.slice(0, -5));
        else if (e.isFile() && e.name.endsWith('.md')) names.add(e.name.slice(0, -3));
        else if (e.isDirectory() && fs.existsSync(path.join(dir, e.name, 'SKILL.md'))) names.add(e.name);
      }
    } catch (e) {}
    process.stdout.write([...names].sort().map(n => n + '\n').join(''));
    break;
  }

  case 'refute-prompt': {
    // The ONE compose used by every refute surface — resolve the gate's profile and print the
    // composed refute prompt (backward-compat when no profile). Unknown profile → error (fail-closed).
    // --json: machine-readable binding for an INTERACTIVE host — json.prompt IS the text compose's
    // bytes (one compose, no drift); model/provider/panel/refute_if from the resolved profile so the
    // spawner can route the refuter without parsing prose. All null when no profile — never fabricated.
    // Flag-order-safe parsing (a leading --json must never be consumed AS the gate name —
    // that silently emitted a bogus text prompt with exit 0; caught by GATE_RE1's refuter).
    const rpArgs = [arg1, ...rest].filter(Boolean);
    const rpJson = rpArgs.includes('--json');
    const rpFree = rpArgs.includes('--free');
    const rpGate = rpArgs.find(a => a !== '--json' && a !== '--free');
    if (!rpGate) die('usage: hb refute-prompt <gate> [--json] [--free]');
    const { composePrompt, gateProfile } = require('./refuter_profiles.js');
    let out;
    try { out = composePrompt(HB_DIR, readDag(), rpGate, { free: rpFree }); }
    catch (e) { die('refute-prompt: ' + e.message); }
    if (rpJson) {
      let prof = null;
      try {
        const g = (readDag().gates || {})[rpGate] || {};
        prof = gateProfile(HB_DIR, g.review || {});
      } catch (e) { die('refute-prompt: ' + e.message); }
      const v = (prof && prof.verdict) || {};
      process.stdout.write(JSON.stringify({
        prompt: out,
        model: (prof && prof.model) ?? null,
        provider: (prof && prof.provider) ?? null,
        panel: v.panel ?? null,
        refute_if: v.refute_if ?? null,
        author_model: (prof && prof.author_model) ?? null,
        free_review: !!(prof && prof.free_review),
        free_model: (prof && prof.free_model) ?? null,
      }) + '\n');
    } else {
      process.stdout.write(out + '\n');
    }
    break;
  }

  case 'park':
  case 'unpark': {
    // The CLI path for retiring a phase — no hand-editing, no deletion (deleting a gate
    // dangles the phase's gate_exit; parking keeps every reference intact and reversible).
    // Accepts a phase id OR a gate id (resolved to the phase carrying it as gate_exit).
    if (!arg1) die(`usage: hb ${cmd} <PHASE_ID|GATE_ID> [reason…]`);
    const dag = readDag();
    const phases = dag.phases || [];
    const target = phases.find(p => p.id === arg1) || phases.find(p => p.gate_exit === arg1);
    if (!target) die(`unknown phase or gate: ${arg1}`);
    if (cmd === 'park') {
      target.parked = true;
      const reason = rest.join(' ').trim();
      if (reason) target.parked_reason = reason;
    } else {
      delete target.parked;
      delete target.parked_reason;
    }
    fs.writeFileSync(DAG, JSON.stringify(dag, null, 2));
    const gateNote = target.gate_exit ? ` [gate: ${target.gate_exit}]` : '';
    process.stdout.write(cmd === 'park'
      ? `⏸ parked phase ${target.id}${gateNote} — out of the plan's live surface (resolver, audit, report, and the --all sweep all skip it). Reverse with: node .hb/hb.js unpark ${target.id}\n`
      : `▶ unparked phase ${target.id}${gateNote} — back in the plan (re-audit before running: node .hb/hb-audit.js .hb/dag.json)\n`);
    break;
  }

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
    die('usage: hb <start|done|fail|heartbeat|ready|review|doctor|diagnose|protocol|rebuild|state|park|unpark|refuters|refute-prompt|changed|constraints|import> [args]');
}
}

