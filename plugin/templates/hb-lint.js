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
  return { errors, warnings };
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
