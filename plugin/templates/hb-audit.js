#!/usr/bin/env node
/**
 * hb-audit.js — adversarial DAG reviewer (deterministic gate-quality audit).
 *
 * Applies refute-don't-confirm to the PLAN before it runs: HeartBeat verifies execution
 * rigorously but otherwise trusts the DAG, and a hollow gate (e.g. `test -f`) turns the
 * whole apparatus into theatre. This flags gates that don't actually prove their phase's
 * work. Deterministic; the agent-refutation layer (a skeptical second read) sits on top.
 *
 * Ruleset is shared verbatim with the Python port (see planning/parity-notes.md).
 *
 * Usage:  node hb-audit.js <dag.json> [--json]     (exit 1 if any error-severity finding)
 * Module: const { audit } = require('./hb-audit.js')  → { findings, errors, warns }
 */
'use strict';
const fs = require('fs');
const { extractPaths } = require('./hb-lint.js');

const VACUOUS   = /^\s*(true|:|exit\s+0|echo\b|test\s+1\s*=\s*1|\[\s+1\s+=\s+1\s+\])\s*;?\s*$/;
const EXISTENCE = /^\s*(test\s+-[efds]\b|\[\s+-[efds]\b|ls(\s|$))/;
// Sources that can change a VERDICT between runs (network, time, randomness). `mktemp` is deliberately
// not listed: it randomises a NAME, and isolating a check in a fresh temp dir is what keeps a gate
// deterministic — a verdict that compares against the random name is left to the refuter's review.
const NONDET    = /\bcurl\b|\bwget\b|\bnc\b|\bping\b|\bsleep\b|\bRANDOM\b|\bshuf\b|\/dev\/urandom|\bSECONDS\b|\$\$|\bdate\b|https?:\/\/(?!localhost|127\.0\.0\.1)/;
// A criterion that CREATES evidence can fabricate its own pass. Gates must observe
// reality, not produce it. Read-only redirections (/dev/null, /tmp scratch, 2>&1) are
// exempt, and so is `=>` (a JS arrow in an inline `node -e`); writes into the project tree are the risk.
const SIDE_EFFECT = /(^|[^0-9>=])>{1,2}\s*(?!\/dev\/null|\/tmp|&\s*[12])|\btee\b|\bcp\b|\bmv\b|\bmkdir\b|\btouch\b|\bdd\b|\bsed\s+-i\b|\binstall\s+-D\b/;

// A non-string cmd reads as '' (its shape is a lint error, never a crash here), and an EMPTY
// cmd is VACUOUS: the runner evals '' → exit 0 → a trivial pass, so it must never count as
// the behavioral criterion that saves a gate from hollow_gate (a refuter-era latent hole).
function classify(cmd) {
  const c = (typeof cmd === 'string' ? cmd : '').trim();
  if (!c) return 'vacuous';
  if (VACUOUS.test(c)) return 'vacuous';
  if (EXISTENCE.test(c)) return 'existence';
  return 'behavioral';
}
const isNondet = (cmd) => NONDET.test(typeof cmd === 'string' ? cmd : '');
const isSideEffecting = (cmd) => SIDE_EFFECT.test(typeof cmd === 'string' ? cmd : '');

// A `grep` that keys on a test-suite marker (a coverage gate) vs a grep of a source string.
const COVERAGE = /\bgrep\b[^|]*(GROUPS-PASSED|\bT[0-9]+\b|[A-Z][A-Z0-9-]*-OK)/;

// --questions: derive, from each criterion's CLASS, a "how could this FALSELY pass?" question — the
// deterministic seed for the adversarial review (turns the audit taxonomy into a falsification checklist).
function criterionQuestion(c) {
  const cmd = (c.cmd || '').trim(), id = c.id || '?', cls = classify(cmd);
  if (cls === 'vacuous')
    return `${id}: looks trivially true — does it assert anything about the phase's real work, or would it pass on ANY code?`;
  if (cls === 'existence')
    return `${id}: checks a path's PRESENCE — does existence prove the behaviour, or could an empty / placeholder / wrong file pass it?`;
  if (isSideEffecting(cmd))
    return `${id}: WRITES/creates files — could it fabricate its own evidence? A gate must OBSERVE reality, not produce it.`;
  if (COVERAGE.test(cmd))
    return `${id}: keys on a suite marker — does it assert the group actually PASSED (zero failures), or could it match a header printed before a RED RUN failed?`;
  if (/\bgrep\b/.test(cmd))
    return `${id}: greps for a string in source — could it pass on a hollow STUB that merely contains the string? Verify the code is EXECUTED, not just matched.`;
  if (isNondet(cmd))
    return `${id}: touches time/network/randomness — could it pass or fail by luck rather than by the behaviour?`;
  return `${id}: runs code — does the assertion pin the REAL required behaviour, or a weak PROXY that a TRIVIAL stub could satisfy?`;
}

function reviewQuestions(dag, gate) {
  const g = ((dag || {}).gates || {})[gate];
  if (!g) return `no gate '${gate}' in this DAG\n`;
  const lines = [`Falsification checklist for ${gate} — for each criterion, how could it FALSELY pass?`];
  for (const c of (g.criteria || [])) lines.push(`  - ${criterionQuestion(c && typeof c === 'object' && !Array.isArray(c) ? c : {})}`);
  lines.push(`  - PHASE CLAIM: "${g.desc || gate}". Could every criterion above pass while this is still broken? Is any criterion testing the WRONG behaviour? Is the REAL runtime exercised (not mocked/stubbed)?`);
  return lines.join('\n') + '\n';
}

// speculative_tail: a plan whose TRAILING live phases are unverified (no gate, no criteria, or no
// behavioral criterion — a zero-task zero-gate placeholder included) behind a verified head was
// planned past its knowledge horizon: those phases are guesses dressed as a plan. Fires once, warn
// (the hollow members already carry their own errors) — its job is the DIAGNOSIS: the cut point.
// Twin: audit._speculative_tail.
// Hostile shapes (a non-object gates map or gate value, a non-array criteria, a non-string
// gate_exit) are lint errors; here they read as EMPTY on both runtimes — never a crash, never a
// divergence (a refuter catch: node threw on string criteria, python on a string gate value).
// Twin: audit._gate_obj.
const gateId = (p) => (typeof p.gate_exit === 'string' && p.gate_exit) ? p.gate_exit : null;   // a non-string gate_exit is no gate
function gateObj(gates, g) {
  const gv = typeof g === 'string' ? gates[g] : undefined;
  return (gv && typeof gv === 'object' && !Array.isArray(gv)) ? gv : {};
}
function phaseVerified(p, gates) {
  const gx = gateId(p);
  if (!gx) return false;
  const crit = gateObj(gates, gx).criteria;
  if (!Array.isArray(crit) || !crit.length) return false;
  return crit.some(c => c && typeof c === 'object' && !Array.isArray(c) && classify(c.cmd) === 'behavioral');
}
function speculativeTail(phases, gates, F) {
  const live = phases.filter(p => !p.parked);
  const rid = (p) => (typeof p.id === 'string' && p.id) ? p.id : '?';
  let k = 0;
  while (k < live.length && !phaseVerified(live[live.length - 1 - k], gates)) k++;
  if (k < 2 || k === live.length) return;
  const tail = live.slice(live.length - k).map(rid), cut = rid(live[live.length - k - 1]);
  F('warn', 'speculative_tail', tail[0],
    `phases ${tail.join(', ')} trail the plan unverified after ${cut} — a speculative tail (plans past the knowledge horizon are guesses): end the plan at ${cut} with "horizon": true and plan the tail when its spec is known (docs/howto/plan-to-the-horizon.md)`,
    { tail, cut });
}

function audit(dag) {
  const findings = [];
  const phases = dag.phases || [];
  const gates = (dag.gates && typeof dag.gates === 'object' && !Array.isArray(dag.gates)) ? dag.gates : {};
  const parked = [];
  const F = (severity, rule, phase, message, extra) => findings.push({ severity, rule, phase, message, ...(extra || {}) });

  for (const p of phases) {
    if (p.parked) {
      // A parked phase is out of the plan's live surface — its gate is not audited (an
      // unsound-but-parked gate must not block audit-clean). The skip is returned in
      // `parked` so callers report it; unpark re-audits (rule: audit-clean before run).
      parked.push(p.id);
      continue;
    }
    const tasks = p.tasks || [];
    const gx = gateId(p);
    if (tasks.length && !gx) {
      F('warn', 'unguarded_phase', p.id, `phase ${p.id} has tasks but no gate_exit — its work is never verified`);
      continue;
    }
    if (!gx) continue;
    const crit0 = gateObj(gates, gx).criteria;
    const crit = Array.isArray(crit0) ? crit0 : [];
    if (crit.length === 0) {
      F('error', 'ungated', p.id, `gate ${gx} has no criteria — phase ${p.id} is not verified`, { gate: gx });
      continue;
    }
    let behavioral = 0;
    for (let c of crit) {
      if (!c || typeof c !== 'object' || Array.isArray(c)) c = {};   // a non-object entry is a lint error (criteria-shape rule); here it is simply not behavioral
      const cls = classify(c.cmd);
      if (cls === 'behavioral') behavioral++;
      else F('info', cls, p.id,
        `${gx}[${c.id}] is ${cls === 'vacuous' ? 'trivially true' : 'an existence-only check'} — assert behaviour, not ${cls === 'vacuous' ? 'nothing' : 'mere existence'}`,
        { gate: gx, criterion: c.id });
      if (isNondet(c.cmd)) F('warn', 'nondeterministic', p.id,
        `${gx}[${c.id}] touches network/time — may flake; gates must be deterministic`,
        { gate: gx, criterion: c.id });
      if (isSideEffecting(c.cmd)) F('warn', 'side_effecting', p.id,
        `${gx}[${c.id}] writes/creates files — a gate must OBSERVE, not PRODUCE its evidence (self-fabricated pass)`,
        { gate: gx, criterion: c.id });
      if (/[\x1e\x1f]/.test(c.cmd || '') || /[\x1e\x1f]/.test(c.desc || '')) F('error', 'control_char', p.id,
        `${gx}[${c.id}] cmd/desc contains a \\x1e/\\x1f control byte — it would corrupt the gate runner's record transport; remove it`,
        { gate: gx, criterion: c.id });
    }
    if (behavioral === 0)
      F('error', 'hollow_gate', p.id,
        `gate ${gx} has NO behavioural criterion — phase ${p.id} passes without proving its work`,
        { gate: gx });
    // "Has a review" = the review value is an object (a non-array dict — the same test both
    // runtimes use); any other shape is a lint error, never a crash here.
    const rv = gateObj(gates, gx).review;
    if (rv !== null && typeof rv === 'object' && !Array.isArray(rv) && !(Array.isArray(rv.constraints) && rv.constraints.length))
      F('warn', 'unconstrained_review', p.id,
        `gate ${gx} has an adversarial review but no plan-time constraints — the refuter's target is implicit (add review.constraints)`,
        { gate: gx });

    const taskText = tasks.map(t => `${t.title || ''} ${t.description || ''}`).join(' ').toLowerCase();
    const paths = new Set();
    for (const c of crit) { if (!c || typeof c !== 'object' || Array.isArray(c) || typeof c.cmd !== 'string') continue; for (const pth of extractPaths(c.cmd)) paths.add(pth); }   // hostile shapes are lint errors, skipped here
    if (paths.size && ![...paths].some(pth => {
      const base = pth.replace(/\/$/, '').split('/').pop().toLowerCase();
      return taskText.includes(pth.toLowerCase()) || taskText.includes(base);
    }))
      F('warn', 'gate_offphase', p.id,
        `gate ${gx} references files no task in ${p.id} mentions — it may not be testing this phase's work`,
        { gate: gx });
  }

  speculativeTail(phases, gates, F);   // horizon-guard: audit

  return {
    findings,
    errors: findings.filter(f => f.severity === 'error').length,
    warns: findings.filter(f => f.severity === 'warn').length,
    parked,
  };
}

if (require.main === module) {
  const file = process.argv[2];
  const asJson = process.argv.includes('--json');
  if (!file) { console.error('Usage: hb-audit.js <dag.json> [--json]'); process.exit(2); }
  let dag;
  try { dag = JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (e) { console.error(`✗ dag.json unreadable: ${e.message}`); process.exit(1); }
  const qi = process.argv.indexOf('--questions');
  if (qi !== -1) { process.stdout.write(reviewQuestions(dag, process.argv[qi + 1])); process.exit(0); }
  const r = audit(dag);
  if (asJson) { console.log(JSON.stringify(r)); process.exit(r.errors ? 1 : 0); }
  const icon = { error: '✗', warn: '⚠', info: '·' };
  for (const f of r.findings) console.log(`  ${icon[f.severity]} [${f.rule}] ${f.message}`);
  if (r.parked.length)   // loud — a skipped phase must be visible in the audit
    console.log(`  ⏸ skipped ${r.parked.length} parked phase(s): ${r.parked.join(' ')} (unpark to re-audit)`);
  console.log(r.errors
    ? `✗ ${r.errors} error(s), ${r.warns} warning(s) — this DAG has hollow gates; fix before running`
    : `✓ gates look behavioural (${r.warns} warning(s))`);
  process.exit(r.errors ? 1 : 0);
}


// Canonical non-behavioral-criterion check (shared with hb-exec.js strict mode — single source).
function nonBehavioral(cmd) {
  // A criterion that only checks a file/dir EXISTS (not that it behaves).
  return /^\s*(test\s+-[efds]\b|\[\s+-[efds]\b|ls\b)/.test(typeof cmd === 'string' ? cmd : '');
}

module.exports = { audit, classify, isNondet, reviewQuestions, nonBehavioral };
