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
  review_pending:     'Spawn a skeptical sub-agent to REFUTE that the phase is done (hollow tests? faked output?) — seed it with `node .hb/hb.js refute-prompt <gate>` (the composed refute prompt: the gate\'s profile persona + a falsification question per criterion + the review angle). Spawn the refuter ON the profile\'s model: read it via `node .hb/hb.js refute-prompt <gate> --json` (.model) and pass it to your agent-spawning tool; inherit the session model only when it is null. Write its full attempt to a findings file, then: node .hb/hb.js review <gate> fail "<holes>" --model <that model>  OR  node .hb/hb.js review <gate> pass --artifact <findings-file> --model <that model> (a pass MUST cite the refuter\'s written attempt — no rubber-stamps; --model records WHAT reviewed, so the per-model impact report has truth to count). Without per-id answers (an unconstrained gate, or the free review) the findings file must carry a line `HOLES: none` or the pass is refused — a hole is a finding: record it with review <gate> fail. CONSTRAINT-FIRST gate (plan-time review.constraints): BEFORE the refute, get the gate-time constraints — `node .hb/hb.js constraints <gate> --prompt` (--json .model = the profile author_model) → an agent that did NOT do the work → HB_ACTOR=<author> node .hb/hb.js constraints <gate> --record <file.json> --model <its model>; the refuter must then answer EVERY id on its own line (<ID>: VIOLATED | NOT-REPRODUCED | N/A — <evidence or reason>); when the profile sets free_review, run `node .hb/hb.js refute-prompt <gate> --free` with another agent (the profile free_model) and record `HB_ACTOR=<free reviewer> node .hb/hb.js review <gate> free --artifact <file> --model <its model>`. The pass is refused until every id is answered and none is VIOLATED.',
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
      else if (substantiveLen(body) < 40) problems.push(`${g} review_passed but backing artifact ${rel} is empty/thin — not a real refutation`);
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
      if (e.holes === 'none') {   // an unconstrained pass: the stored artifact must still say HOLES: none
        let rawH = null;
        try { rawH = fs.readFileSync(path.join(HB_DIR, e.artifact || `reviews/${g}.md`)); } catch (x) {}
        if (rawH === null) continue;
        const hs = checkHoles(rawH.toString('utf8'));
        const shaH = !e.artifact_sha256 || require('crypto').createHash('sha256').update(rawH).digest('hex') === e.artifact_sha256;
        if (!shaH || hs.length)
          problems.push(`${g} review_passed HOLES line no longer holds in ${e.artifact || `reviews/${g}.md`} (${!shaH ? 'the artifact bytes changed since the pass' : hs[0]}) — the stored refutation was altered`);
        continue;
      }
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

  // The stored free review must still be the bytes that were recorded (the pass relied on it).
  {
    const lastFree = {};
    for (const e of readEvents()) if (e.event === 'free_review_recorded') lastFree[e.gate] = e;
    for (const [g, e] of Object.entries(lastFree)) {
      const rel = e.artifact || `reviews/${g}.free.md`;
      let raw = null;
      try { raw = fs.readFileSync(path.join(HB_DIR, rel)); } catch (x) {}
      if (raw === null) problems.push(`${g} recorded free review ${rel} is missing — the free review can no longer be inspected`);
      else if (e.sha256 && require('crypto').createHash('sha256').update(raw).digest('hex') !== e.sha256)
        problems.push(`${g} recorded free review ${rel} changed since recording (sha256 mismatch)`);
    }
  }

  // regate: a pending revision is a NOTE (legitimate in-flight state); the rearm evidence must stay
  // the pinned bytes; an ACCEPTED gate whose criteria were rearmed after its last provenanced pass
  // carries STALE evidence; and the event log (truth) must agree with the dag marker — the documented
  // dag_corrupted recovery restores dag.json from backup, which can silently drop a pending regate.
  {
    const evsR = readEvents();
    for (const [g, gv] of Object.entries(gates)) {
      const blk = regateBlocks(gv);
      if (blk) notes.push(`${g} is being revised — regate pending (by ${blk.actor || '?'}: ${blk.reason || ''}); evaluation refuses until a DIFFERENT actor rearms`);
    }
    const lastRe = {};
    for (const e of evsR) if (e.event === 'gate_rearmed') lastRe[e.gate] = e;
    for (const [g, e] of Object.entries(lastRe)) {
      const rel = e.artifact || `reviews/${g}.regate.md`;
      let raw = null;
      try { raw = fs.readFileSync(path.join(HB_DIR, rel)); } catch (x) {}
      if (raw === null) problems.push(`${g} regate rearm artifact ${rel} is missing — the rearm evidence can no longer be inspected`);   // regate-guard: rearm-rot
      else if (raw.toString('utf8').trim().length < 40) problems.push(`${g} regate rearm artifact ${rel} is empty/thin — not real rearm evidence`);   // regate-guard: rearm-rot
      else if (e.sha256 && require('crypto').createHash('sha256').update(raw).digest('hex') !== e.sha256) problems.push(`${g} regate rearm artifact ${rel} changed since recording (sha256 mismatch) — the rearm evidence was altered`);   // regate-guard: rearm-rot
    }
    const accR = {};
    for (const e of evsR) {
      const rev = !!((gates[e.gate] || {}).review);
      if ((e.event === 'review_passed' && rev) || (e.event === 'gate_passed' && !rev)) accR[e.gate] = true;
      else if (e.event === 'review_failed') delete accR[e.gate];
    }
    for (const g of Object.keys(lastRe)) if (accR[g] && staleRearm(evsR, g)) problems.push(`${g} accepted but its criteria were rearmed after its last provenanced pass — STALE evidence: re-run the gate (bash .hb/gate.sh ${g})`);   // regate-guard: stale-accepted
    const unanswered = {};
    for (const e of evsR) { if (e.event === 'gate_regated') unanswered[e.gate] = true; else if (e.event === 'gate_rearmed') delete unanswered[e.gate]; }
    for (const g of Object.keys(unanswered)) if (!(gates[g] && regateBlocks(gates[g]))) problems.push(`${g}: the event log attests a pending regate (gate_regated unanswered by any gate_rearmed) but dag.json carries ${gates[g] && Object.prototype.hasOwnProperty.call(gates[g], 'regate') ? 'a CLEARED marker (pending edited by hand?)' : 'no regate marker (restored from backup?)'} — re-declare and rearm properly, or investigate (the log is truth)`);   // regate-guard: marker-sync
    for (const [g, gv] of Object.entries(gates)) {   // regate-guard: marker-sync — a rearmed marker must be backed by the event that pins it
      const rmk = gv.regate;
      if (rmk && typeof rmk === 'object' && !Array.isArray(rmk) && rmk.pending === false) {
        const ePin = lastRe[g];
        if (!ePin || ((rmk.rearm || {}).sha256 && ePin.sha256 && rmk.rearm.sha256 !== ePin.sha256)) problems.push(`${g}: the dag records a rearmed regate but the event log ${ePin ? 'pins different bytes (sha256 mismatch with gate_rearmed)' : 'has no gate_rearmed event'} — a fabricated rearm record (the log is truth)`);   // regate-guard: marker-sync
      }
    }
  }

  // detach: a retracted dependency claim is a legitimate in-flight state — NOTES, never problems
  // (topology edits carry no acceptance-laundering risk: the phase's own gate still verifies). But
  // the log is still truth: a dag whose detach fields and detach events disagree was hand-edited or
  // restored from a backup, in either direction, and both are said out loud.
  {
    const evsD = readEvents();
    const liveD = {};
    for (const e of evsD) { if (e.event === 'phase_detached') liveD[e.phase] = true; else if (e.event === 'phase_reattached') liveD[e.phase] = false; }
    for (const p of phases) {
      const hasF = Object.prototype.hasOwnProperty.call(p, 'detached_from');
      if (hasF && !p.gate_entry) notes.push(`${p.id} is detached from ${p.detached_from} (by ${p.detached_by || '?'}: ${p.detached_reason || ''}) — the dependency claim is retracted; re-audit before relying on the order${(() => { const a = readAnchor(`_detach_${p.id}`); return (a && a.detached_at === p.detached_at) ? '' : ' (no detach anchor — change reports widen to _start)'; })()}`);   // detach-guard: doctor — the suffix fires on a MISSING or STAMP-MISMATCHED anchor (changed()'s predicate; a silent widening was a refuter catch)
      if (hasF && liveD[p.id] !== true) notes.push(`${p.id} carries detach fields but the log attests no live detach (no phase_detached, or the last one answered by phase_reattached) — a hand edit or a restored dag: the phase runs UNLOCKED on an unattested claim`);   // detach-guard: doctor
      if (!hasF && liveD[p.id] === true) notes.push(`${p.id}: the log attests an unanswered phase_detached but the dag carries no detach fields — a restored dag silently RE-LOCKED the phase (re-lock)`);   // detach-guard: doctor
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

  // A pending regate on a gate outranks the generic branch ABOUT THAT GATE: the generic recovery
  // commands (gate.sh --check, run the refuter) are exactly what the perimeter refuses.
  const regatedGates = Object.entries(dag.gates || {}).filter(([, gv]) => regateBlocks(gv)).map(([g]) => g);
  const regateRecovery = (g) => {
    const blk = regateBlocks((dag.gates || {})[g]) || {};
    P(`  Gate: ${g} — being revised (regate pending, by ${blk.actor || '?'}: ${blk.reason || ''})`);
    P('  Recover:');
    P('   1. Edit the revised criteria in .hb/dag.json (if not already done).');
    P('   2. Re-audit: node .hb/hb-audit.js .hb/dag.json');
    P(`   3. A DIFFERENT actor rearms: node .hb/hb.js regate ${g} --rearm --artifact <findings-file>`);
    P(`   4. Re-run the gate: bash .hb/gate.sh ${g} — a fresh pass is owed before any review verdict.`);
  };
  if (!reason) {   // infer the most pressing blocker
    if ((state.gate && state.gate.errors) > 0) reason = 'gate_blocked';
    else if (doctor().problems.some(p => /no longer reproducible/.test(p))) reason = 'gate_rot';
    else if ((state.pending_reviews || []).length) reason = 'review_stuck';
    else if ((state.build_stuck_count || 0) >= 5) reason = 'build_stuck';
    else if (regatedGates.length) reason = 'regate_pending';
    else { try { const { resolve } = require('./hb-next-task.js'); const r = resolve(state, dag, HB_DIR); if (r && r.type === 'deadlock') reason = 'deadlock'; } catch (e) {} }
  }
  P(`Diagnosis: ${reason || 'no blocker detected'}`);
  if (!reason) { P('  Not currently blocked. Run: node .hb/hb.js state'); return out.join('\n'); }

  if (reason === 'regate_pending') {
    for (const g of (regatedGates.length ? regatedGates : ['(none found — pass the gate id)'])) regateRecovery(g);
  } else if (reason === 'gate_blocked') {
    let g = null, rf = null;
    for (let i = events.length - 1; i >= 0 && !g; i--) if (['gate_failed', 'gate_passed', 'review_failed'].includes(events[i].event)) { g = events[i].gate; if (events[i].event === 'review_failed') rf = events[i]; }
    if (!g) { const p = (dag.phases || []).find(p => !state.completed_phases.includes(p.id)); g = p && p.gate_exit; }
    if (g && regateBlocks((dag.gates || {})[g])) { regateRecovery(g); return out.join('\n'); }
    P(`  Gate: ${g}`);
    if (rf) {   // the criteria passed; the adversarial review did not
      P('  Cause: review_failed — the criteria pass; the review refuted the phase (or could not run).');
      P(`  Findings: ${String(rf.note || '(none recorded)').replace(/\s+/g, ' ').slice(0, 600)}`);
      P('  Recover:');
      P('   1. A refutation: fix the CODE for the hole it names — never weaken the gate or the review.');
      P('   2. A review that could not run (an error): fix the refuter backend.');
      P(`   3. Then bash .hb/gate.sh ${g} — a pass owes the review again.`);
      return out.join('\n');
    }
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
    if (g && regateBlocks((dag.gates || {})[g])) { regateRecovery(g); return out.join('\n'); }
    if (g && staleRearm(events, g)) {
      P(`  Gate awaiting review: ${g} — revised and re-armed, but its last provenanced pass predates the rearm (stale evidence).`);
      P(`  Recover: re-run the revised gate first — bash .hb/gate.sh ${g}; verdicts are refused until a fresh pass.`);
      return out.join('\n');
    }
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
  let base = phase.gate_entry || '_start';
  const dAnchor = (!phase.gate_entry && Object.prototype.hasOwnProperty.call(phase, 'detached_from')) ? readAnchor(`_detach_${phase.id}`) : null;   // detach-guard: changed-base
  if (dAnchor && dAnchor.detached_at === phase.detached_at) base = `_detach_${phase.id}`;   // detach-guard: changed-base — a stamp mismatch (a stale late write) reads as MISSING, never lies
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
// A gate_rearmed ALSO starts a cycle: gate-time constraints and free reviews were authored against
// the pre-revision criteria, so nothing recorded before the rearm may satisfy the acceptance after
// it (ONE start definition — everything that keys on the cycle moves together).
function reviewCycle(dag, gate) {
  const events = readEvents();
  const pending = (project(events, dag).pending_reviews || []).includes(gate);
  let start = -1;
  events.forEach((e, i) => { if ((e.event === 'review_failed' || e.event === 'review_passed' || e.event === 'gate_rearmed') && e.gate === gate) start = i; });   // regate-guard: cycle-start
  const recorded = events.some((e, i) => i > start && e.event === 'constraints_recorded' && e.gate === gate);
  return { pending, recorded, events, start };
}
// The refuter's per-id answers (constraint-first review). One line per id:
//   <ID>: VIOLATED | NOT-REPRODUCED | N/A — <evidence or reason>
// Markdown-insensitive (list bullets, quotes, headings, *, _, ` are ignored) and case-insensitive on the
// status. Prose that merely mentions an id is not an answer. Twin: review_policy.check_answers.
// EXPLICIT rules, identical in both runtimes (refuter catches, three rounds). Two layers:
// 1. THE WORD. The whole artifact is normalised — NFKC; HTML entities decoded; <br> is a line break;
//    tags and comment MARKERS removed (comment text kept); escape/control/invisible characters removed;
//    Cyrillic/Greek look-alikes folded (ANSWER_CONFUSABLES) — and any line whose letters, squashed
//    together, contain "violated" refuses the pass, evidence included. The word is reserved for
//    VIOLATED answers, so no layout, spelling or markup can put a violation next to a clean answer.
// 2. THE ANSWERS, parsed strictly from the VISIBLE text (comments removed): one line per id,
//    `<ID>: NOT-REPRODUCED | N/A — <evidence or reason>` (ASCII-only lowercased copy — no regex case
//    folding); an answer-shaped line with a malformed status, or a line naming an id with a status that is
//    not well-formed, is refused.
const ANSWER_BREAKS = /\r\n|[\n\r\v\f\x1c\x1d\x1e\x85\u2028\u2029]/;
const ANSWER_INVISIBLE = /[\u200b-\u200f\u2060-\u2064\u2066-\u2069\u202a-\u202e\ufeff\u00ad\u180e\u034f\u061c]/g;
const ANSWER_ANSI = /\x1b\[[0-9;?]*[ -\/]*[@-~]|\x1b[@-_]/g;
const ANSWER_CTRL = /[\x00-\x08\x0b-\x1f\x7f]/g;
const ANSWER_CONFUSABLES = {"\u0410": "a", "\u0412": "b", "\u0415": "e", "\u041a": "k", "\u041c": "m", "\u041d": "h", "\u041e": "o", "\u0420": "p", "\u0421": "c", "\u0422": "t", "\u0425": "x", "\u0430": "a", "\u0435": "e", "\u043e": "o", "\u0440": "p", "\u0441": "c", "\u0443": "y", "\u0445": "x", "\u0456": "i", "\u0458": "j", "\u0455": "s", "\u0501": "d", "\u0406": "i", "\u0408": "j", "\u0405": "s", "\u04cf": "l", "\u0500": "d", "\u04ae": "y", "\u04af": "y", "\u04c0": "l", "\u051b": "q", "\u051d": "w", "\u0391": "a", "\u0392": "b", "\u0395": "e", "\u0396": "z", "\u0397": "h", "\u0399": "i", "\u039a": "k", "\u039c": "m", "\u039d": "n", "\u039f": "o", "\u03a1": "p", "\u03a4": "t", "\u03a5": "y", "\u03a7": "x", "\u03bf": "o", "\u03bd": "v", "\u03b9": "i", "\u03b1": "a", "\u03ba": "k", "\u03c1": "p", "\u03c4": "t", "\u03c5": "u", "\u0131": "i", "\u017f": "s", "\u2113": "l", "\u01c0": "l", "\u0251": "a", "\u0261": "g", "\u1d20": "v", "\u1d05": "d", "\u1d07": "e", "\u1d1b": "t", "\u1d0f": "o", "\u1d00": "a", "\u0299": "b", "\u1d04": "c", "\ua730": "f", "\u0262": "g", "\u029c": "h", "\u026a": "i", "\u1d0a": "j", "\u1d0b": "k", "\u029f": "l", "\u1d0d": "m", "\u0274": "n", "\u1d18": "p", "\u01eb": "q", "\u0280": "r", "\ua731": "s", "\u1d1c": "u", "\u1d21": "w", "\u028f": "y", "\u1d22": "z", "\u0585": "o", "\u057d": "u", "\u0581": "g", "\u0570": "h", "\u0578": "n", "\u0561": "w", "\u0565": "e", "\u056b": "h", "\u056c": "l", "\u057c": "n", "\u1d43": "a", "\u1d47": "b", "\u1d9c": "c", "\u1d48": "d", "\u1d49": "e", "\u1da0": "f", "\u1d4d": "g", "\u02b0": "h", "\u2071": "i", "\u02b2": "j", "\u1d4f": "k", "\u02e1": "l", "\u1d50": "m", "\u207f": "n", "\u1d52": "o", "\u1d56": "p", "\u02b3": "r", "\u02e2": "s", "\u1d57": "t", "\u1d58": "u", "\u1d5b": "v", "\u02b7": "w", "\u02e3": "x", "\u02b8": "y", "\u1dbb": "z", "\u1d2c": "a", "\u1d2e": "b", "\u1d30": "d", "\u1d31": "e", "\u1d33": "g", "\u1d34": "h", "\u1d35": "i", "\u1d36": "j", "\u1d37": "k", "\u1d38": "l", "\u1d39": "m", "\u1d3a": "n", "\u1d3c": "o", "\u1d3e": "p", "\u1d3f": "r", "\u1d40": "t", "\u1d41": "u", "\u2c7d": "v", "\u1d42": "w"};
const ANSWER_ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
// NO platform normalisation (NFKC tables differ between the node and python Unicode versions — a
// refuter catch): full-width ASCII is folded by explicit arithmetic, and STYLED letters (mathematical,
// enclosed, letterlike, legacy-computing blocks — fixed ranges) are refused outright (ANSWER_STYLED).
// (™ U+2122, ℹ U+2139, circled/parenthesized NUMBERS U+2460–249B and regional-indicator flags U+1F1E6–1F1FF
// are ordinary report symbols and stay allowed; Roman-numeral letter forms U+2160–2188 are refused)
const ANSWER_STYLED = /[\u2100-\u2121\u2123-\u2138\u213a-\u214f\u2160-\u2188\u249c-\u24ff\u{1cc00}-\u{1cebf}\u{1d400}-\u{1d7ff}\u{1f100}-\u{1f1e5}]/u;
function foldWidth(t) { return t.replace(/[\uff01-\uff5e]/g, c => String.fromCharCode(c.charCodeAt(0) - 0xfee0)).replace(/[\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000]/g, ' '); }
function answerText(body, commentMode) {
  let t = foldWidth(String(body));
  t = t.replace(/&#([0-9]{1,7});|&#[xX]([0-9a-fA-F]{1,6});|&([a-zA-Z]+);/g, (m, d, h, n) => {
    const cp = d ? parseInt(d, 10) : h ? parseInt(h, 16) : null;
    if (cp !== null) return cp <= 0x10ffff && !(cp >= 0xd800 && cp <= 0xdfff) ? String.fromCodePoint(cp) : '';
    return Object.prototype.hasOwnProperty.call(ANSWER_ENTITIES, n.toLowerCase()) ? ANSWER_ENTITIES[n.toLowerCase()] : m;
  });
  t = t.replace(/<br[ \t]*\/?>/gi, '\n');
  // commentMode: 'keep' → comment markers become spaces, comment text kept (a word inside a comment is
  // seen); 'drop' → comments removed, an UNCLOSED one hiding the rest (what a renderer shows, and a word
  // split across a comment rejoins)
  // inside an inline code span a comment marker is literal text, not a comment
  t = t.replace(/`[^`\n]*`/g, m => m.replace(/<!--/g, '<!- -').replace(/-->/g, '- ->'));
  t = commentMode === 'keep' ? t.replace(/<!--|-->/g, ' ') : t.replace(/<!--[\s\S]*?(?:-->|$(?![\s\S]))/g, '');
  t = t.replace(/<\/?[a-zA-Z][^<>]*>/g, '');
  return foldWidth(t.replace(ANSWER_ANSI, '').replace(ANSWER_INVISIBLE, ''));
}
function squashLetters(s) {
  let o = '';
  for (const c of s) { const f = ANSWER_CONFUSABLES[c] || c; if (/^[A-Za-z]$/.test(f)) o += f.toLowerCase(); }
  return o;
}
function checkAnswers(body, required) {
  const req = new Set(required), seen = {}, errors = [], counts = { violated: 0, not_reproduced: 0, na: 0 };
  const FMT = require('./refuter_profiles.js').ANSWER_FORMAT;
  // 0. styled letters are refused outright (no version-dependent folding)
  // checked on the raw text AND after entity decoding (&#x1D415; is a styled letter too)
  if (ANSWER_STYLED.test(String(body)) || ANSWER_STYLED.test(answerText(body, 'keep'))) errors.push('the artifact uses styled letters (mathematical, enclosed, letterlike or legacy-computing symbols) — write plain text');
  // 1. the word, anywhere: with comment text kept AND with comments removed (a word split by one rejoins)
  const wordCount = (mode) => answerText(body, mode).split(ANSWER_BREAKS).filter(line => {
    const sq = squashLetters(line.replace(ANSWER_CTRL, ''));   // also reversed: a right-to-left override displays it forwards
    return sq.includes('violated') || sq.includes('detaloiv');
  }).length;
  const wordLines = Math.max(wordCount('keep'), wordCount('drop'));
  // an unclosed comment hides everything after it when rendered — say so (instead of "no answer line")
  if (/<!--(?![\s\S]*-->)/.test(String(body).replace(/`[^`\n]*`/g, m => m.replace(/<!--/g, '<!- -').replace(/-->/g, '- ->'))))
    errors.push('the artifact has an unclosed <!-- — everything after it is hidden when rendered: close the comment or remove it');
  // 2. the answers, from the visible text
  let looseId = 0;
  for (const raw of answerText(body, 'drop').split(ANSWER_BREAKS)) {
    const l = raw.replace(ANSWER_CTRL, '').replace(/[*`_]/g, '').replace(/^[ \t]+|[ \t]+$/g, '').replace(/^(?:[\t >+#-]+|[0-9]+[.)][ \t]+)+/, '');
    const lo = l.replace(/[A-Z]/g, c => c.toLowerCase());   // ASCII-only: no regex case folding
    const m = /^([pg][0-9]+)[ \t]*[:：][ \t]*(violated|not-reproduced|not reproduced|n\/a)(?=$|[ \t—–:,.;])(.*)$/.exec(lo);
    const head = /^([pg][0-9]+)[ \t]*[:：]/.exec(lo);
    if (head && !m) { errors.push(`${head[1].toUpperCase()} has an answer-shaped line that is not a well-formed answer (${FMT})`); continue; }
    if (!m) {
      if (/(^|[^a-z0-9])[pg][0-9]+([^0-9]|$)/.test(lo) && /(not[- ]?reproduced|n\/a)/.test(lo)) looseId++;
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
  if (wordLines && !counts.violated) errors.push(`the artifact uses the word "violated" outside a VIOLATED answer (${wordLines} line(s)) — the word is reserved: if a constraint is violated, record the finding with hb review <gate> fail "<finding>"; otherwise say what held instead`);
  if (looseId) errors.push(`a line names a constraint id with a status but is not a well-formed answer (${looseId} line(s)) — answer each id exactly (${FMT})`);
  for (const id of required) if (!seen[id]) errors.push(`${id} has no answer line (${FMT})`);
  return { errors, counts };
}
// A review without per-id answers (an unconstrained pass; the free review) must carry a visible line
// `HOLES: none` — markdown-, width- and case-insensitive, read from the same normalised visible text as the
// answers. No such line, or any HOLES line that lists anything, refuses the pass: a hole is a finding.
// (Several `HOLES: none` lines are fine — a panel's pass joins its CLEAR panelists.) Twin:
// review_policy.check_holes (messages verbatim).
function checkHoles(body) {
  const errors = [];
  const styled = ANSWER_STYLED.test(String(body)) || ANSWER_STYLED.test(answerText(body, 'keep'));   // == checkAnswers
  if (styled) errors.push('the artifact uses styled letters (mathematical, enclosed, letterlike or legacy-computing symbols) — write plain text');
  if (/<!--(?![\s\S]*-->)/.test(String(body).replace(/`[^`\n]*`/g, m => m.replace(/<!--/g, '<!- -').replace(/-->/g, '- ->'))))
    errors.push('the artifact has an unclosed <!-- — everything after it is hidden when rendered: close the comment or remove it');
  let n = 0, listed = 0;
  for (const raw of answerText(body, 'drop').split(ANSWER_BREAKS)) {
    const ln = raw.replace(ANSWER_CTRL, '').replace(/[*`_]/g, '').replace(/^[ \t]+|[ \t]+$/g, '').replace(/^(?:[\t >+#-]+|[0-9]+[.)][ \t]+)+/, '');
    const lo = ln.replace(/[A-Z]/g, c => c.toLowerCase());   // ASCII-only: no regex case folding
    const m = /^holes[ \t]*[:：][ \t]*(.*)$/.exec(lo);
    if (!m) continue;
    n++;
    if (!/^none[ \t.!]*$/.test(m[1])) listed++;
  }
  if (n === 0) errors.push('the artifact has no "HOLES: none" line — a pass must state that no hole was found (a hole is a finding: record it with hb review <gate> fail "<finding>")');
  if (listed) errors.push('a HOLES line lists something other than "none" — a hole is a finding: record it with hb review <gate> fail "<finding>"');
  return errors;
}
// evidence / a reason must contain a character that is not whitespace or invisible (ONE explicit set,
// identical in python)
const ANSWER_TEXT = /[^ \t   -   　⠀ㅤﾠᅟᅠ]/;

// Fail-closed regate predicate: a gate carrying a `regate` key BLOCKS evaluation/acceptance unless
// the record is a well-formed object whose pending is exactly false (a rearmed revision). A
// malformed record (wrong type, truthy junk) blocks — lint names it; a permissive read would let a
// hand-mangled marker silently disarm the perimeter, and the two runtimes' truthiness rules
// disagree on []/{} (a refuter catch). Returns the blocking record ({} when unreadable) or null
// when clear. Twin: state.regate_blocks.
function regateBlocks(gv) {
  if (!gv || !Object.prototype.hasOwnProperty.call(gv, 'regate')) return null;
  const r = gv.regate;
  if (r && typeof r === 'object' && !Array.isArray(r) && r.pending === false) return null;
  return (r && typeof r === 'object' && !Array.isArray(r)) ? r : {};
}

// Substantive length with ONE explicit whitespace set (ASCII " \t\n\r\f\v" — the lint blankFree
// precedent): JS trim() and python strip() disagree on ﻿ / \x85 / \x1c-\x1f, so a thin-artifact
// boundary judged with the native trims DIVERGES between the runtimes — the same bytes accepted by
// one and refused by the other (a refuter catch). Twin: state.substantive_len.
function substantiveLen(s) {
  const m = String(s).match(/^[ \t\n\r\f\v]*([\s\S]*?)[ \t\n\r\f\v]*$/);
  // CODE POINTS, not UTF-16 units: python counts code points, and an astral character (emoji)
  // must weigh the same on both runtimes or the thin boundary diverges (a refuter catch).
  return [...(m ? m[1] : String(s))].length;
}

// True while the log attests an UNANSWERED revision: a gate_regated with no later gate_rearmed.
// The event log is truth — a hand-cleared, hand-restored or fabricated dag marker must not launder
// an acceptance past the rearm bar (a refuter catch: setting pending=false by hand skipped the
// whole bar while doctor and lint stayed silent). Twin: state.unanswered_regate.
function unansweredRegate(events, gate) {
  let un = false;
  for (const e of events) {
    if (e.event === 'gate_regated' && e.gate === gate) un = true;
    else if (e.event === 'gate_rearmed' && e.gate === gate) un = false;
  }
  return un;
}

// True when <gate> has a gate_rearmed with NO LATER provenanced gate_passed. "Provenanced" =
// the criteria/runtime evidence fields a real evaluation stamps — `hb import`'s bare synthetic
// {event:gate_passed, gate} never counts, so it cannot launder a revision into an acceptance.
// Review verdicts and the executors refuse in this window: acceptance after a revision requires
// a FRESH pass of the revised criteria. Twin: state.stale_rearm.
function staleRearm(events, gate) {
  let last = -1;
  events.forEach((e, i) => { if (e.event === 'gate_rearmed' && e.gate === gate) last = i; });
  if (last === -1) return false;
  for (let i = last + 1; i < events.length; i++) {
    const e = events[i];
    if (e.event === 'gate_passed' && e.gate === gate &&
        ((Array.isArray(e.criteria) && e.criteria.length) || e.runtime)) return false;
  }
  return true;
}

// The weasel-vector loudness for `hb detach`: detaching FROM a gate in any of these states removes
// a dependency claim that was doing real work, so the declare carries a warning. PER-CHANNEL
// liveness (a merged last-verdict stream under-fires on the refuted steady state — review_failed,
// then the gate re-run and det-passed with the review still owed — a plan-refuter catch): a live
// gate_failed is one with no later gate_passed for THAT gate; a live review_failed is one with no
// later review_passed — a later gate_passed does NOT clear it, mirroring the projection's
// acceptance semantics. Plus the regate family: a blocking marker, an unanswered declare in the
// log (hand-cleared markers must not disarm the loudness), and the stale-rearm window.
// Twin: the python cli's _detach_warn.
function detachWarn(events, gv, gate) {
  let gf = false, rf = false;
  for (const e of events) {
    if (e.gate !== gate) continue;
    if (e.event === 'gate_failed') gf = true;
    else if (e.event === 'gate_passed') gf = false;
    else if (e.event === 'review_failed') rf = true;
    else if (e.event === 'review_passed') rf = false;
  }
  return gf || rf || !!regateBlocks(gv) || unansweredRegate(events, gate) || staleRearm(events, gate);
}

// The detach-time anchor: the base `hb changed` reports a DETACHED phase against — the tree at the
// detach moment (never _start: that widens the report to other phases' work). DIRECT write, never
// tryAnchor: it is REWRITTEN by each successful declare (write-once would lie on a re-detach), and
// STAMPED with the declare's detached_at so a late-landing stale write reads as missing instead of
// lying. A write failure is warned on stderr and never blocks the declare (changed() then falls
// back to _start and doctor's live-detach note says so). Twin: the python cli's detach handler.
function writeDetachAnchor(phaseId, detachedAt) {
  try {
    let commit = null;
    if (inGitWorktree()) {
      try { commit = require('child_process').execFileSync('git', ['-C', PROJECT_DIR, 'rev-parse', 'HEAD'], { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim() || null; } catch (e) {}
    }
    const a = { gate: `_detach_${phaseId}`, ts: nowIso(), commit, files: listProjectFiles(), detached_at: detachedAt };
    fs.mkdirSync(ANCHORS, { recursive: true });
    atomicWrite(path.join(ANCHORS, `_detach_${phaseId}.json`), JSON.stringify(a, null, 2) + '\n');
  } catch (e) { process.stderr.write(`⚠ detach anchor for ${phaseId} not recorded: ${e.message} — change reports will widen to _start\n`); }
}

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
// A gate-time constraint must name what this phase changed: at least one subject that is a file in the
// phase's `hb changed` list (added, modified or deleted) or a directory holding one. Without a change list
// (no entry anchor — a project that predates anchors) or with an empty one, a project-relative path that
// exists is enough. A `:12` / `:12-30` line suffix and a `::symbol` / `#anchor` suffix are stripped first;
// an absolute path, one with `..`, or `.` never grounds. Areas and unchanged files may sit alongside.
// Twin: constraints.grounding_errors / _subject_path (messages verbatim).
function subjectPath(s) {
  let p = String(s).trim().replace(/^(?:\.\/)+/, '');
  p = p.replace(/(?:::[^/]*|#[^/]*|:[0-9]+(?:-[0-9]+)?)$/, '').replace(/\/+$/, '');
  if (!p || p === '.' || p.startsWith('/') || /^[A-Za-z]:[\\/]/.test(p) || p.split(/[\\/]/).includes('..')) return null;
  return p;
}
function groundingErrors(list, gate) {
  let touched = [];
  try { const c = changed(gate); touched = [...c.added, ...c.modified, ...c.deleted].sort(); } catch (e) {}
  const byChange = touched.length > 0;
  const grounded = (s) => {
    const p = subjectPath(s);
    if (p === null) return false;
    if (byChange) return touched.some(t => t === p || t.startsWith(p + '/'));
    return fs.existsSync(path.join(PROJECT_DIR, p));
  };
  const errs = [];
  for (const c of list) {
    if ((c.subjects || []).some(grounded)) continue;
    const subs = (c.subjects || []).map(s => JSON.stringify(String(s))).join(', ');
    if (byChange) errs.push(`${c.id}: no subject names a file this phase changed (hb changed) or a directory holding one (subjects: ${subs}) — name at least one of: ${touched.slice(0, 5).join(', ')}${touched.length > 5 ? ', …' : ''}; areas and unchanged files may sit alongside`);
    else errs.push(`${c.id}: no subject names a real project path (subjects: ${subs}) — name at least one file or directory of this project (one that exists); areas may sit alongside`);
  }
  return errs;
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
  L.push('- subjects: the files/areas it covers — at least one must be a file this phase changed (in the change list above) or a directory holding one (a :line or ::symbol suffix is fine); a constraint that names none is refused');
  L.push('- violation: the concrete, observable result that would falsify it');
  L.push('Record it (as an actor who did not do this phase\'s work):');
  L.push(`  hb constraints ${gate} --record <file.json>`);
  return L.join('\n');
}

// Exported BEFORE the CLI dispatch: refuter_profiles.js requires this module while hb.js is running
// as the CLI (a circular require sees only what is already assigned).
module.exports = { project, phaseByGateExit, initialState, PROTOCOL, renderProtocolMd, withWlock, changed, recordedConstraints, safePath, checkAnswers, checkHoles, subjectPath,
  planConstraints, reviewCycle, composeAuthorPrompt, regateBlocks, staleRearm, substantiveLen, unansweredRegate };

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
    { const rga = regateBlocks((readDag().gates || {})[arg1]);   // regate-guard: anchor — write-once acceptance records must not freeze a revised, unverified tree (refuter catch)
      if (rga) die(`anchor: ${arg1} is being revised (regate pending, by ${rga.actor || '?'}: ${rga.reason || ''}) — no acceptance anchor until a rearm and a fresh pass of the revised criteria.`); }   // regate-guard: anchor
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
    const rgc = regateBlocks((dag.gates || {})[gate]);   // regate-guard: constraints — no targets over a revision (fail-closed on malformed records)
    if (rgc) die(`hb constraints --record refused on ${gate}: the gate is being revised (regate pending, by ${rgc.actor || '?'}: ${rgc.reason || ''}) — a DIFFERENT actor rearms first: node .hb/hb.js regate ${gate} --rearm --artifact <findings-file>; constraints are authored against the criteria that will be enforced.`);   // regate-guard: constraints
    if (unansweredRegate(readEvents(), gate)) die(`hb constraints --record refused on ${gate}: the event log attests an UNANSWERED revision (gate_regated with no gate_rearmed) — a hand-edited dag marker cannot clear it; rearm first.`);   // regate-guard: log-truth
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
    const gerrs = groundingErrors(list, gate);
    if (gerrs.length) die('hb constraints --record: ' + gerrs.join('; '));
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
    const dag0 = readDag(), gates0 = dag0.gates || {};   // regate-guard: review — no verdict over a revision
    const gv0 = gates0[gate] || gates0[((dag0.phases || []).find(p => p.id === gate) || {}).gate_exit];   // regate-guard: review — a phase id must not bypass the guard (refuter catch)
    const rgv = regateBlocks(gv0);   // regate-guard: review — fail-closed: a malformed record blocks too
    if (rgv) die(`review ${verdict} refused on ${gate}: the gate is being revised (regate pending, by ${rgv.actor || '?'}: ${rgv.reason || ''}) — a DIFFERENT actor rearms first: node .hb/hb.js regate ${gate} --rearm --artifact <findings-file>; a fresh pass of the revised criteria is then owed before any verdict.`);   // regate-guard: review
    const rGateName = gates0[gate] ? gate : ((((dag0.phases || []).find(p => p.id === gate) || {}).gate_exit) || gate);   // regate-guard: review — shared by the log-truth and stale-pass guards below
    if (unansweredRegate(readEvents(), rGateName)) die(`review ${verdict} refused on ${gate}: the event log attests an UNANSWERED revision of ${rGateName} (gate_regated with no gate_rearmed) — a hand-edited dag marker cannot clear it: a DIFFERENT actor rearms (node .hb/hb.js regate ${rGateName} --rearm --artifact <findings-file>), then a fresh pass is owed.`);   // regate-guard: log-truth
    if (staleRearm(readEvents(), rGateName)) die(`review ${verdict} refused on ${gate}: the gate was revised and re-armed but its last provenanced pass predates the rearm (stale evidence) — re-run the revised gate first: bash .hb/gate.sh ${rGateName}; a fresh pass is owed before any verdict.`);   // regate-guard: stale-pass
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
    if (substantiveLen(body) < 40) die(`${vw}: artifact ${artifact} is too thin (${substantiveLen(body)} chars) to be a real refutation attempt — a rubber-stamp is not a review.`);
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
      const hf = checkHoles(body);
      if (hf.length) die(`review free refused on ${gate}: ${hf.join('; ')}`);
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
    } else {
      const hp = checkHoles(body);
      if (hp.length) die(`review pass refused on ${gate}: ${hp.join('; ')}`);
    }
    const revDir = path.join(HB_DIR, 'reviews');
    try { fs.mkdirSync(revDir, { recursive: true }); } catch (e) {}
    fs.writeFileSync(path.join(revDir, `${gate}.md`), body);
    const autocommit = gitPolicy();
    mutate({ event: 'review_passed', gate, model, artifact: `reviews/${gate}.md`, artifact_chars: substantiveLen(body), cited, reviewer, git: { autocommit },
             ...(answers ? { answers, constraint_ids: constraintIds, artifact_sha256: require('crypto').createHash('sha256').update(body, 'utf8').digest('hex') }
                         : { holes: 'none', artifact_sha256: require('crypto').createHash('sha256').update(body, 'utf8').digest('hex') }),
             ...(note ? { note } : {}) });
    // Reviewed acceptance creates the phase's restore point (commit+tag) — deferred from the
    // deterministic pass so the tag only ever certifies a reviewed-good state.
    if (autocommit) {
      const p = (dag.phases || []).find(x => x.gate_exit === gate);
      gitSnapshot(gate, p ? `heartbeat(${p.id}): ${p.title} [${gate}]` : `heartbeat: ${gate} accepted`);
    }
    tryAnchor(gate);   // acceptance anchor — after the restore point, so its commit is the accepted HEAD
    process.stdout.write(`review pass ${gate} (backed by reviews/${gate}.md, ${substantiveLen(body)} chars, cites: ${cited.slice(0, 3).join(', ')})\n`);
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

  case 'regate': {
    // Sanctioned gate revision — the fail-closed sibling of park. A gate whose PREMISES died
    // (a deleted volume, a dev-mode assumption) is re-grounded through regate, never by a silent
    // hand-edit: declare snapshots the criteria and marks the gate pending; while pending, every
    // evaluation/acceptance path refuses (gate.sh exit 3; review; constraints --record); the
    // rearm half (RG2) re-enables evaluation behind an evidence bar.
    if (!arg1) die('usage: hb regate <GATE_ID|PHASE_ID> <reason…>  |  hb regate <GATE_ID|PHASE_ID> --rearm --artifact <findings-file> [--model <m>]');
    const dag = readDag();
    const phases = dag.phases || [];
    let gate = null;
    if ((dag.gates || {})[arg1]) gate = arg1;
    else {
      const ph = phases.find(p => p.id === arg1);
      if (ph && !ph.gate_exit) die(`regate: phase ${arg1} has no gate_exit — nothing to revise`);
      gate = ph && ph.gate_exit;
    }
    if (!gate || !(dag.gates || {})[gate]) die(`regate: unknown gate or phase: ${arg1}`);

    if (rest.includes('--rearm')) {
      // ── the rearm half: evidence-gated re-grounding ──
      const toks = rest.filter(t => t !== '--rearm');
      let artifact = null, model = null;
      for (let i = 0; i < toks.length; i++) {
        if (toks[i] === '--artifact') artifact = toks[++i];
        else if (toks[i] === '--model') model = toks[++i] ?? null;
        else die(`regate --rearm: unexpected argument ${toks[i]}`);
      }
      if (!artifact || /^--/.test(String(artifact)))
        die('regate --rearm requires --artifact <findings-file>: the written evidence that the revision RE-GROUNDS the gate (what premise died, what the revised criteria now exercise).');
      const actor = process.env.HB_ACTOR;
      if (!actor || !actor.trim() || actor.trim().toLowerCase() === 'unknown')
        die('regate --rearm: set HB_ACTOR to the rearm reviewer\'s identity');
      const gv = dag.gates[gate];
      if (!regateBlocks(gv)) die(`regate --rearm: no pending regate on ${gate} — nothing to rearm`);
      if (!(gv.regate && typeof gv.regate === 'object' && !Array.isArray(gv.regate)) || gv.regate.pending !== true || typeof gv.regate.actor !== 'string')
        die(`regate --rearm: the regate record on ${gate} is malformed — lint names the shape; fix .hb/dag.json (or restore it from git) before rearming.`);
      if (gv.regate.actor.trim().toLowerCase() === actor.trim().toLowerCase())   // regate-guard: rearm-actor — the declarer cannot certify their own revision
        die(`regate --rearm: '${actor}' declared this revision — the rearm must come from a DIFFERENT actor (the review-pass precedent).`);   // regate-guard: rearm-actor
      const ap = path.isAbsolute(artifact) ? artifact : path.join(PROJECT_DIR, artifact);
      let body = '';
      try { body = fs.readFileSync(ap, 'utf8'); } catch (e) { die(`regate --rearm: cannot read artifact ${artifact} (${e.code || e.message})`); }
      if (substantiveLen(body) < 40)
        die(`regate --rearm: artifact ${artifact} is too thin (${substantiveLen(body)} chars) to justify re-arming a revised gate.`);
      // Substance: the evidence must cite a real anchor of the phase — gate id, phase id, a task id,
      // or a path the REVISED criteria reference (the review-pass precedent).
      const phaseR = phases.find(p => p.gate_exit === gate);
      const anchorsR = new Set([gate]);
      if (phaseR) { anchorsR.add(phaseR.id); for (const t of (phaseR.tasks || [])) anchorsR.add(t.id); }
      const { extractPaths } = require('./hb-lint.js');
      for (const c of (gv.criteria || [])) for (const pth of extractPaths(c.cmd || '')) { anchorsR.add(pth); anchorsR.add(pth.split('/').pop()); }
      const hayR = body.toLowerCase();
      const citedR = [...anchorsR].filter(a => a && String(a).length > 1 && hayR.includes(String(a).toLowerCase()));
      if (!citedR.length)
        die(`regate --rearm: artifact ${artifact} does not reference the phase under revision (expected one of: ${[...anchorsR].filter(a => a && String(a).length > 1).join(', ')}).`);
      const sha = require('crypto').createHash('sha256').update(body, 'utf8').digest('hex');
      const verdictR = withWlock(() => {
        const dag2 = readDag();
        const gv2 = (dag2.gates || {})[gate];
        const rg2 = gv2 && gv2.regate;
        if (!rg2 || typeof rg2 !== 'object' || Array.isArray(rg2) || rg2.pending !== true)
          return `regate --rearm: no pending regate on ${gate} (it changed underneath — re-check the dag)`;
        const auditRes = require('./hb-audit.js').audit(dag2);   // regate-guard: rearm-audit — audited INSIDE the lock: an edit landing between an earlier audit and the write would rearm unaudited (a refuter catch)
        if (auditRes.errors) return `regate --rearm refused on ${gate}: the DAG is not audit-clean (${auditRes.errors} error(s)) — a hollow revision cannot rearm:\n` + auditRes.findings.filter(f => f.severity === 'error').map(f => '  ✗ ' + f.message).join('\n');   // regate-guard: rearm-audit
        const rd = path.join(HB_DIR, 'reviews');
        fs.mkdirSync(rd, { recursive: true });
        fs.writeFileSync(path.join(rd, `${gate}.regate.md`), body);
        rg2.pending = false;
        rg2.rearm = { at: nowIso(), actor, model: model ?? null, artifact: `reviews/${gate}.regate.md`, sha256: sha };
        fs.writeFileSync(DAG, JSON.stringify(dag2, null, 2));
        appendEvent({ event: 'gate_rearmed', gate, model: model ?? null, artifact: `reviews/${gate}.regate.md`, sha256: sha });   // audit-only
        reproject();
        return null;
      });
      if (verdictR) die(verdictR);
      process.stdout.write(
        `🔁 rearm ${gate} (by ${actor}${model ? ', model ' + model : ''}): evidence stored at .hb/reviews/${gate}.regate.md\n` +
        `   evaluation re-enabled — the revised criteria are now the gate; a FRESH pass is owed before any review verdict:\n` +
        `   bash .hb/gate.sh ${gate}\n`);
      break;
    }

    const reason = rest.join(' ').trim();
    for (const t of rest) if (/^--/.test(t)) die(`regate: unknown option ${t}`);
    if (!reason) die('regate: a reason is required — say why the gate\'s premises changed');
    const actor = process.env.HB_ACTOR;
    if (!actor || !actor.trim() || actor.trim().toLowerCase() === 'unknown')
      die('regate: set HB_ACTOR to the reviser\'s identity (the rearm must come from a DIFFERENT actor)');
    // Check-then-write under ONE write lock (the constraints --record precedent): two concurrent
    // declares must not both see "no pending regate" — a refuter catch (3 events from 6 racers).
    const verdict = withWlock(() => {
      const dag2 = readDag();
      const gv2 = (dag2.gates || {})[gate];
      if (!gv2) return `regate: unknown gate or phase: ${arg1}`;
      if (regateBlocks(gv2)) {
        const r2 = (gv2.regate && typeof gv2.regate === 'object' && !Array.isArray(gv2.regate)) ? gv2.regate : {};
        return `regate: ${gate} already has a pending regate (by ${r2.actor || '?'}: ${r2.reason || ''}) — edit the criteria and rearm that revision first`;
      }
      gv2.regate = { at: nowIso(), reason, actor,
                     prev_criteria: JSON.parse(JSON.stringify(gv2.criteria || [])), pending: true };
      fs.writeFileSync(DAG, JSON.stringify(dag2, null, 2));
      appendEvent({ event: 'gate_regated', gate, reason });   // audit-only: the projection ignores it
      reproject();
      return null;
    });
    if (verdict) die(verdict);
    process.stdout.write(
      `🔧 regate ${gate} (by ${actor}): ${reason}\n` +
      `   criteria snapshotted (prev_criteria) — ${gate} now REFUSES evaluation and acceptance (fail-closed).\n` +
      `   Next: 1. edit the criteria in .hb/dag.json   2. re-audit: node .hb/hb-audit.js .hb/dag.json\n` +
      `         3. a DIFFERENT actor rearms with evidence: node .hb/hb.js regate ${gate} --rearm --artifact <findings-file>\n`);
    break;
  }

  case 'detach': {
    // Retract a phase's DEPENDENCY CLAIM (park's fail-closed sibling for topology): gate_entry →
    // null — the resolver's EXISTING unlocked semantics, zero resolver change — recorded, loud,
    // reversible. The dag is the editable plan; detach makes the edit attributed and reviewed.
    if (!arg1) die('usage: hb detach <PHASE_ID|GATE_ID> <reason…>');
    const reasonD = rest.join(' ').trim();
    if (!reasonD) die('detach: a reason is required — why is the dependency claim no longer true?');   // detach-guard: validate
    const actorD = process.env.HB_ACTOR || '';
    if (!actorD.trim() || actorD.trim().toLowerCase() === 'unknown') die('detach: set HB_ACTOR to the reviser\'s identity');   // detach-guard: validate
    const dag0 = readDag();
    const t0 = (dag0.phases || []).find(p => p.id === arg1) || (dag0.phases || []).find(p => p.gate_exit === arg1);
    let warnD = false;
    if (t0 && t0.gate_entry) warnD = detachWarn(readEvents(), (dag0.gates || {})[t0.gate_entry] || {}, t0.gate_entry);   // detach-guard: warn
    const verdictD = withWlock(() => {   // check-then-write under the write lock: concurrent declares and parks must not lose edits (teeth: the 6-way race in tests/detach.sh — a structural line is not strip-testable)
      const dag = readDag();
      const phases = dag.phases || [];
      const target = phases.find(p => p.id === arg1) || phases.find(p => p.gate_exit === arg1);
      if (!target) return `detach: unknown phase or gate: ${arg1}`;
      if (!SAFE_GATE_ID.test(target.id)) return `detach: phase id '${target.id}' is not usable as an anchor file name — rename the phase first`;   // detach-guard: validate
      if (project(readEvents(), dag).completed_phases.includes(target.id)) return `detach: ${target.id} is already complete — a satisfied dependency has nothing to unlock`;   // detach-guard: validate
      if (!target.gate_entry) return Object.prototype.hasOwnProperty.call(target, 'detached_from') ? `detach: ${target.id} is already detached (from ${target.detached_from}) — reverse with: node .hb/hb.js reattach ${target.id}` : `detach: ${target.id} has no gate_entry — nothing to detach`;   // detach-guard: validate
      const from = target.gate_entry;
      const at = nowIso();
      target.detached_from = from;
      target.detached_reason = reasonD;
      target.detached_by = actorD;
      target.detached_at = at;
      target.gate_entry = null;
      fs.writeFileSync(DAG, JSON.stringify(dag, null, 2));
      appendEvent({ event: 'phase_detached', phase: target.id, from, reason: reasonD });   // audit-only: attribution in the log
      reproject();
      return { id: target.id, from, at };
    });
    if (typeof verdictD === 'string') die(verdictD);
    writeDetachAnchor(verdictD.id, verdictD.at);   // detach-guard: anchor — the honest change base (hashed after the lock; changed() falls back to _start without it, and DT2's doctor note will say so)
    process.stdout.write(`⟂ detached ${verdictD.id} from ${verdictD.from} (by ${actorD}): ${reasonD}\n` +
      `   the dependency claim is RETRACTED — ${verdictD.id} is unlocked; re-audit the plan: node .hb/hb-audit.js .hb/dag.json\n` +
      `   reverse with: node .hb/hb.js reattach ${verdictD.id}\n`);
    if (warnD) process.stdout.write(`   ⚠ ${verdictD.from} is failing, refuted or under revision — the claim is REMOVED, not satisfied: this does not unblock or accept ${verdictD.from}; the reason is on record.\n`);
    break;
  }

  case 'reattach': {
    if (!arg1) die('usage: hb reattach <PHASE_ID|GATE_ID>');
    const verdictA = withWlock(() => {   // locked read-modify-write (teeth: the races case)
      const dag = readDag();
      const phases = dag.phases || [];
      const target = phases.find(p => p.id === arg1) || phases.find(p => p.gate_exit === arg1);
      if (!target) return `reattach: unknown phase or gate: ${arg1}`;
      if (!Object.prototype.hasOwnProperty.call(target, 'detached_from')) return `reattach: ${target.id} is not detached`;
      const to = target.detached_from;
      const isExit = phases.some(p => p.gate_exit === to);   // detach-guard: reattach — a defined-but-orphaned gate would lock the phase forever
      if (!(dag.gates || {})[to] || !isExit) return `reattach: ${to} is ${!(dag.gates || {})[to] ? 'no longer defined' : "no phase's gate_exit"} — restoring it would lock ${target.id} forever (the lint 'phase locked forever' brick); fix the dag first`;   // detach-guard: reattach
      target.gate_entry = to;
      delete target.detached_from;
      delete target.detached_reason;
      delete target.detached_by;
      delete target.detached_at;
      fs.writeFileSync(DAG, JSON.stringify(dag, null, 2));
      appendEvent({ event: 'phase_reattached', phase: target.id, to });   // audit-only
      reproject();
      return { id: target.id, to };
    });
    if (typeof verdictA === 'string') die(verdictA);
    process.stdout.write(`▶ reattached ${verdictA.id} to ${verdictA.to} — the dependency claim is restored; re-audit before running: node .hb/hb-audit.js .hb/dag.json\n`);
    break;
  }

  case 'park':
  case 'unpark': {
    // The CLI path for retiring a phase — no hand-editing, no deletion (deleting a gate
    // dangles the phase's gate_exit; parking keeps every reference intact and reversible).
    // Accepts a phase id OR a gate id (resolved to the phase carrying it as gate_exit).
    if (!arg1) die(`usage: hb ${cmd} <PHASE_ID|GATE_ID> [reason…]`);
    // Read-modify-write of dag.json under the write lock: an UNLOCKED rewrite raced against a
    // concurrent declare erased the fresh regate marker (lost update — a refuter catch, 2/40).
    const parkRes = withWlock(() => {
      const dag = readDag();
      const phases = dag.phases || [];
      const target = phases.find(p => p.id === arg1) || phases.find(p => p.gate_exit === arg1);
      if (!target) return `unknown phase or gate: ${arg1}`;
      if (cmd === 'park') {
        target.parked = true;
        const reason = rest.join(' ').trim();
        if (reason) target.parked_reason = reason;
      } else {
        delete target.parked;
        delete target.parked_reason;
      }
      fs.writeFileSync(DAG, JSON.stringify(dag, null, 2));
      return { id: target.id, gateNote: target.gate_exit ? ` [gate: ${target.gate_exit}]` : '' };
    });
    if (typeof parkRes === 'string') die(parkRes);
    process.stdout.write(cmd === 'park'
      ? `⏸ parked phase ${parkRes.id}${parkRes.gateNote} — out of the plan's live surface (resolver, audit, report, and the --all sweep all skip it). Reverse with: node .hb/hb.js unpark ${parkRes.id}\n`
      : `▶ unparked phase ${parkRes.id}${parkRes.gateNote} — back in the plan (re-audit before running: node .hb/hb-audit.js .hb/dag.json)\n`);
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
    die('usage: hb <start|done|fail|heartbeat|ready|review|doctor|diagnose|protocol|rebuild|state|park|unpark|regate|detach|reattach|refuters|refute-prompt|changed|constraints|import> [args]');
}
}

