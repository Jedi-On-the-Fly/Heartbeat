#!/usr/bin/env node
/**
 * hb-lint.js — Validation statique de dag.json (v1.2)
 *
 * Erreurs (exit 1) :
 *   - IDs de tâches dupliqués
 *   - requires vers un ID inexistant
 *   - cycle de dépendances
 *   - gate_entry / gate_exit référençant une gate non définie
 *   - gate_entry qui n'est la gate_exit d'aucune phase (phase verrouillée à jamais)
 * Warnings (exit 0) :
 *   - phase > 8 tâches (leçon vizcore-demo : perte de contexte)
 *   - gate définie mais jamais référencée
 *
 * Usage : node hb-lint.js <dag.json> [--json]
 * Module : const { lint } = require('./hb-lint.js')  → { errors, warnings }
 */
'use strict';
const fs = require('fs');

function lint(dag) {
  const errors = [], warnings = [];
  const gates  = dag.gates  ?? {};
  const phases = dag.phases ?? [];
  const taskIds = new Set();
  const taskMap = {};

  for (const p of phases) {
    const tasks = p.tasks ?? [];
    if (tasks.length > 8) {
      warnings.push(`[${p.id}] ${tasks.length} tâches (>8) — risque de perte de contexte, envisager des sous-phases`);
    }
    for (const t of tasks) {
      if (taskIds.has(t.id)) errors.push(`ID de tâche dupliqué: ${t.id}`);
      taskIds.add(t.id);
      taskMap[t.id] = t;
    }
    for (const g of [p.gate_entry, p.gate_exit]) {
      if (g && !gates[g]) errors.push(`[${p.id}] gate non définie: ${g}`);
    }
    if (p.gate_entry && !phases.some(q => q.gate_exit === p.gate_entry)) {
      errors.push(`[${p.id}] gate_entry ${p.gate_entry} n'est la gate_exit d'aucune phase — phase verrouillée à jamais`);
    }
  }

  for (const id of taskIds) {
    for (const r of (taskMap[id].requires ?? [])) {
      if (!taskIds.has(r)) errors.push(`[${id}] requires une tâche inexistante: ${r}`);
    }
  }

  // Cycles — DFS tricolore
  const color = {}; const stack = [];
  function dfs(id) {
    color[id] = 1; stack.push(id);
    for (const r of (taskMap[id]?.requires ?? [])) {
      if (!taskMap[r]) continue;
      if (color[r] === 1) {
        errors.push(`Cycle de dépendances: ${[...stack.slice(stack.indexOf(r)), r].join(' → ')}`);
        continue;
      }
      if (!color[r]) dfs(r);
    }
    stack.pop(); color[id] = 2;
  }
  for (const id of taskIds) if (!color[id]) dfs(id);

  for (const g of Object.keys(gates)) {
    if (!phases.some(p => p.gate_entry === g || p.gate_exit === g)) {
      warnings.push(`Gate définie mais jamais référencée: ${g}`);
    }
  }

  checkPlaceholders(dag, warnings);
  checkGateArtifacts(dag, warnings);
  return { errors, warnings };
}

// v1.4 (#1): warn if the DAG still carries bootstrap-skeleton text — catches
// "the agent claimed a plan but left the template". Advisory (exit 0).
const PLACEHOLDER_MARKERS = [
  'Implement feature A', 'Implement feature B',
  'Description of what this task produces.',
  'Create all required directories and config files.',
  'Check that all required tools and dependencies are available.',
  'Verify A and B work together correctly.',
  'output/result.json',
];
function checkPlaceholders(dag, warnings) {
  const hits = [];
  if (dag._meta && dag._meta.project === 'my-project') hits.push('_meta.project = "my-project"');
  const flat = JSON.stringify(dag);
  for (const m of PLACEHOLDER_MARKERS) if (flat.includes(m)) hits.push(`"${m}"`);
  if (hits.length) {
    warnings.push(`DAG contient encore du texte du squelette (${hits.slice(0, 3).join(', ')}${hits.length > 3 ? ', …' : ''}) — remplacer par le vrai plan`);
  }
}

// v1.4 (#1): warn when a gate cmd references a file/dir that no task appears to
// produce (heuristic). Catches "gate runs tests/e2e/x.spec.js but nothing writes it".
function extractPaths(cmd) {
  const out = new Set();
  for (const tokRaw of (cmd.match(/[\w.\-/${}]+/g) || [])) {
    if (!tokRaw.includes('/')) continue;            // must look like a path
    if (/HB_DIR/.test(tokRaw)) continue;            // HeartBeat's own dir
    let p = tokRaw.replace(/\$\{?PROJECT_DIR\}?\//, '').replace(/^\.\//, '');
    if (!p || p.startsWith('$')) continue;          // bare/unresolved var
    if (p.includes('.hb/')) continue;
    const base = p.replace(/\/$/, '').split('/').pop();
    if (['state.json', 'dag.json', 'events.jsonl'].includes(base)) continue;
    out.add(p);
  }
  return out;
}
function checkGateArtifacts(dag, warnings) {
  const phases = dag.phases ?? [];
  const taskText = phases.flatMap(p => p.tasks ?? [])
    .map(t => `${t.title ?? ''} ${t.description ?? ''}`).join(' ').toLowerCase();
  const seen = new Set();
  for (const g of Object.values(dag.gates ?? {})) {
    for (const c of (g.criteria ?? [])) {
      for (const p of extractPaths(c.cmd ?? '')) {
        if (seen.has(p)) continue; seen.add(p);
        const base  = p.replace(/\/$/, '').split('/').pop().toLowerCase();
        const noext = base.replace(/\.\w+$/, '');
        const pl    = p.toLowerCase();
        if (taskText.includes(pl) || taskText.includes(base) ||
            (noext.length >= 3 && taskText.includes(noext))) continue;
        warnings.push(`gate référence ${p} — aucune tâche ne semble le produire (vérifier qu'une tâche l'écrit)`);
      }
    }
  }
}

if (require.main === module) {
  const file   = process.argv[2];
  const asJson = process.argv.includes('--json');
  if (!file) { console.error('Usage: hb-lint.js <dag.json> [--json]'); process.exit(2); }
  let dag;
  try { dag = JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (e) {
    if (asJson) console.log(JSON.stringify({ errors: [`dag.json illisible: ${e.message}`], warnings: [] }));
    else console.error(`✗ dag.json illisible: ${e.message}`);
    process.exit(1);
  }
  const { errors, warnings } = lint(dag);
  if (asJson) console.log(JSON.stringify({ errors, warnings }));
  else {
    for (const e of errors)   console.log(`  ✗ ${e}`);
    for (const w of warnings) console.log(`  ⚠ ${w}`);
    console.log(errors.length ? `✗ ${errors.length} erreur(s), ${warnings.length} warning(s)`
                              : `✓ DAG valide (${warnings.length} warning(s))`);
  }
  process.exit(errors.length ? 1 : 0);
}
module.exports = { lint };
