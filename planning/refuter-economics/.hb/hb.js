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
    if (!gate || (verdict !== 'pass' && verdict !== 'fail'))
      die('usage: hb review <gate> pass|fail [--artifact <findings-file>] [--model <m>] [note]');
    if (verdict === 'fail') {
      mutate({ event: 'review_failed', gate, model, ...(note ? { note } : {}) });
      process.stdout.write(`review fail ${gate}\n`);
      break;
    }
    if (!artifact) die('review pass requires --artifact <findings-file>: the refuter\'s written attempt to break the phase (a pass must cite evidence, not just assert one).');
    const ap = path.isAbsolute(artifact) ? artifact : path.join(PROJECT_DIR, artifact);
    let body = '';
    try { body = fs.readFileSync(ap, 'utf8'); } catch (e) { die(`review pass: cannot read artifact ${artifact} (${e.code || e.message})`); }
    if (body.trim().length < 40) die(`review pass: artifact ${artifact} is too thin (${body.trim().length} chars) to be a real refutation attempt — a rubber-stamp is not a review.`);
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
      die(`review pass: artifact ${artifact} does not reference the phase under review (it cites nothing real; expected one of: ${[...anchors].filter(a => a && String(a).length > 1).join(', ')}).`);
    // Identity: reject a self-review — a pass whose actor also recorded this phase's
    // task_done events is grading its own homework. Adjudicated only when actors are set.
    const reviewer = process.env.HB_ACTOR || 'unknown';
    if (reviewer !== 'unknown' && phaseForGate) {
      const phaseTaskIds = new Set((phaseForGate.tasks || []).map(t => t.id));
      const doers = new Set();
      for (const e of readEvents())
        if (e.event === 'task_done' && phaseTaskIds.has(e.task) && e.actor && e.actor !== 'unknown') doers.add(e.actor);
      if (doers.has(reviewer))
        die(`review pass: reviewer '${reviewer}' also executed this phase's work — a self-review is not adversarial. Have a DIFFERENT actor refute (set HB_ACTOR).`);
    }
    const revDir = path.join(HB_DIR, 'reviews');
    try { fs.mkdirSync(revDir, { recursive: true }); } catch (e) {}
    fs.writeFileSync(path.join(revDir, `${gate}.md`), body);
    mutate({ event: 'review_passed', gate, model, artifact: `reviews/${gate}.md`, artifact_chars: body.trim().length, cited, reviewer, ...(note ? { note } : {}) });
    // Reviewed acceptance creates the phase's restore point (commit+tag) — deferred from the
    // deterministic pass so the tag only ever certifies a reviewed-good state.
    if (!process.env.HB_NO_GIT && process.env.HB_GIT_AUTOCOMMIT !== '0') {
      const cp = require('child_process');
      let inRepo = false;
      try { cp.execFileSync('git', ['-C', PROJECT_DIR, 'rev-parse', '--is-inside-work-tree'], { stdio: 'ignore' }); inRepo = true; } catch (e) {}
      if (inRepo) {
        const p = (dag.phases || []).find(x => x.gate_exit === gate);
        const msg = p ? `heartbeat(${p.id}): ${p.title} [${gate}]` : `heartbeat: ${gate} accepted`;
        try { cp.execFileSync('git', ['-C', PROJECT_DIR, 'add', '-A'], { stdio: 'ignore' }); } catch (e) {}
        try { cp.execFileSync('git', ['-c', 'user.name=HeartBeat', '-c', 'user.email=heartbeat@local', '-C', PROJECT_DIR, 'commit', '-q', '--no-verify', '-m', msg], { stdio: 'ignore' }); } catch (e) {}
        try { cp.execFileSync('git', ['-C', PROJECT_DIR, 'tag', '-f', gate], { stdio: 'ignore' }); } catch (e) {}
      }
    }
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
    const rpGate = rpArgs.find(a => a !== '--json');
    if (!rpGate) die('usage: hb refute-prompt <gate> [--json]');
    const { composePrompt, gateProfile } = require('./refuter_profiles.js');
    let out;
    try { out = composePrompt(HB_DIR, readDag(), rpGate); }
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
    die('usage: hb <start|done|fail|heartbeat|ready|review|doctor|diagnose|protocol|rebuild|state|park|unpark|refuters|refute-prompt|import> [args]');
}
}

module.exports = { project, phaseByGateExit, initialState, PROTOCOL, renderProtocolMd, withWlock };
