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
const NONDET    = /\bcurl\b|\bwget\b|\bnc\b|\bping\b|\bsleep\b|\$RANDOM\b|\bdate\b|https?:\/\/(?!localhost|127\.0\.0\.1)/;

function classify(cmd) {
  const c = (cmd || '').trim();
  if (VACUOUS.test(c)) return 'vacuous';
  if (EXISTENCE.test(c)) return 'existence';
  return 'behavioral';
}
const isNondet = (cmd) => NONDET.test(cmd || '');

function audit(dag) {
  const findings = [];
  const phases = dag.phases || [];
  const gates = dag.gates || {};
  const F = (severity, rule, phase, message, extra) => findings.push({ severity, rule, phase, message, ...(extra || {}) });

  for (const p of phases) {
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
    }
    if (behavioral === 0)
      F('error', 'hollow_gate', p.id,
        `gate ${p.gate_exit} has NO behavioural criterion — phase ${p.id} passes without proving its work`,
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
  };
}

if (require.main === module) {
  const file = process.argv[2];
  const asJson = process.argv.includes('--json');
  if (!file) { console.error('Usage: hb-audit.js <dag.json> [--json]'); process.exit(2); }
  let dag;
  try { dag = JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (e) { console.error(`✗ dag.json unreadable: ${e.message}`); process.exit(1); }
  const r = audit(dag);
  if (asJson) { console.log(JSON.stringify(r)); process.exit(r.errors ? 1 : 0); }
  const icon = { error: '✗', warn: '⚠', info: '·' };
  for (const f of r.findings) console.log(`  ${icon[f.severity]} [${f.rule}] ${f.message}`);
  console.log(r.errors
    ? `✗ ${r.errors} error(s), ${r.warns} warning(s) — this DAG has hollow gates; fix before running`
    : `✓ gates look behavioural (${r.warns} warning(s))`);
  process.exit(r.errors ? 1 : 0);
}

module.exports = { audit, classify, isNondet };
