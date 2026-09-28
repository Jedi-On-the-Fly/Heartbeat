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
const NONDET    = /\bcurl\b|\bwget\b|\bnc\b|\bping\b|\bsleep\b|\bRANDOM\b|\bshuf\b|\/dev\/urandom|\bSECONDS\b|\$\$|\bmktemp\b(?!\s+-u)|\bdate\b|https?:\/\/(?!localhost|127\.0\.0\.1)/;
// A criterion that CREATES evidence can fabricate its own pass. Gates must observe
// reality, not produce it. Read-only redirections (/dev/null, /tmp scratch, 2>&1) are
// exempt; writes into the project tree are the risk.
const SIDE_EFFECT = /(^|[^0-9>])>{1,2}\s*(?!\/dev\/null|\/tmp|&\s*[12])|\btee\b|\bcp\b|\bmv\b|\bmkdir\b|\btouch\b|\bdd\b|\bsed\s+-i\b|\binstall\s+-D\b/;

function classify(cmd) {
  const c = (cmd || '').trim();
  if (VACUOUS.test(c)) return 'vacuous';
  if (EXISTENCE.test(c)) return 'existence';
  return 'behavioral';
}
const isNondet = (cmd) => NONDET.test(cmd || '');
const isSideEffecting = (cmd) => SIDE_EFFECT.test(cmd || '');

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
  for (const c of (g.criteria || [])) lines.push(`  - ${criterionQuestion(c)}`);
  lines.push(`  - PHASE CLAIM: "${g.desc || gate}". Could every criterion above pass while this is still broken? Is any criterion testing the WRONG behaviour? Is the REAL runtime exercised (not mocked/stubbed)?`);
  return lines.join('\n') + '\n';
}

function audit(dag) {
  const findings = [];
  const phases = dag.phases || [];
  const gates = dag.gates || {};
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
    if (tasks.length && !p.gate_exit) {
      F('warn', 'unguarded_phase', p.id, `phase ${p.id} has tasks but no gate_exit — its work is never verified`);
      continue;
    }
    if (!p.gate_exit) continue;
    const crit = (gates[p.gate_exit] || {}).criteria || [];
    if (crit.length === 0) {
      F('error', 'ungated', p.id, `gate ${p.gate_exit} has no criteria — phase ${p.id} is not verified`, { gate: p.gate_exit });
      continue;
    }
    let behavioral = 0;
    for (const c of crit) {
      const cls = classify(c.cmd);
      if (cls === 'behavioral') behavioral++;
      else F('info', cls, p.id,
        `${p.gate_exit}[${c.id}] is ${cls === 'vacuous' ? 'trivially true' : 'an existence-only check'} — assert behaviour, not ${cls === 'vacuous' ? 'nothing' : 'mere existence'}`,
        { gate: p.gate_exit, criterion: c.id });
      if (isNondet(c.cmd)) F('warn', 'nondeterministic', p.id,
        `${p.gate_exit}[${c.id}] touches network/time — may flake; gates must be deterministic`,
        { gate: p.gate_exit, criterion: c.id });
      if (isSideEffecting(c.cmd)) F('warn', 'side_effecting', p.id,
        `${p.gate_exit}[${c.id}] writes/creates files — a gate must OBSERVE, not PRODUCE its evidence (self-fabricated pass)`,
        { gate: p.gate_exit, criterion: c.id });
      if (/[\x1e\x1f]/.test(c.cmd || '') || /[\x1e\x1f]/.test(c.desc || '')) F('error', 'control_char', p.id,
        `${p.gate_exit}[${c.id}] cmd/desc contains a \\x1e/\\x1f control byte — it would corrupt the gate runner's record transport; remove it`,
        { gate: p.gate_exit, criterion: c.id });
    }
    if (behavioral === 0)
      F('error', 'hollow_gate', p.id,
        `gate ${p.gate_exit} has NO behavioural criterion — phase ${p.id} passes without proving its work`,
        { gate: p.gate_exit });
    const rv = (gates[p.gate_exit] || {}).review;
    if (rv && !(Array.isArray(rv.constraints) && rv.constraints.length))
      F('warn', 'unconstrained_review', p.id,
        `gate ${p.gate_exit} has an adversarial review but no plan-time constraints — the refuter's target is implicit (add review.constraints)`,
        { gate: p.gate_exit });

    const taskText = tasks.map(t => `${t.title || ''} ${t.description || ''}`).join(' ').toLowerCase();
    const paths = new Set();
    for (const c of crit) for (const pth of extractPaths(c.cmd || '')) paths.add(pth);
    if (paths.size && ![...paths].some(pth => {
      const base = pth.replace(/\/$/, '').split('/').pop().toLowerCase();
      return taskText.includes(pth.toLowerCase()) || taskText.includes(base);
    }))
      F('warn', 'gate_offphase', p.id,
        `gate ${p.gate_exit} references files no task in ${p.id} mentions — it may not be testing this phase's work`,
        { gate: p.gate_exit });
  }

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
  return /^\s*(test\s+-[efds]\b|\[\s+-[efds]\b|ls\b)/.test(cmd || '');
}

module.exports = { audit, classify, isNondet, reviewQuestions, nonBehavioral };
