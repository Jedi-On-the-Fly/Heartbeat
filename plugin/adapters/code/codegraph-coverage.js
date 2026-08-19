#!/usr/bin/env node
/**
 * codegraph-coverage.js — graph coverage / blind-spot report for the code adapter.
 *
 * Don't trust all code context equally: for each task in the DAG, count the symbols the codemap
 * resolves for it, and explicitly LIST the GRAPH-BLIND tasks — those with zero resolved symbols. A
 * blind task is one the static graph can't model (a not-yet-existing file, a dynamic/framework
 * binding like Alpine methods or template bindings) — read it manually; the graph won't help there.
 * Advisory; node ≡ python (byte-identical, T106); imports nothing from core.
 *
 * Usage: node codegraph-coverage.js <codemap.json> <dag.json>
 */
'use strict';
const fs = require('fs');

function coverage(codemap, dag) {
  const taskSyms = ((codemap || {}).tasks) || {};
  const ids = [];
  for (const p of (((dag || {}).phases) || [])) for (const t of (p.tasks || [])) ids.push(t.id);
  ids.sort();
  const lines = ['Graph coverage:'];
  const blind = [];
  for (const id of ids) {
    const n = (taskSyms[id] || []).length;
    lines.push(`  ${id}: ${n} symbol${n === 1 ? '' : 's'}`);
    if (n === 0) blind.push(id);
  }
  blind.sort();
  lines.push(blind.length ? `GRAPH-BLIND (read manually): ${blind.join(', ')}` : 'GRAPH-BLIND: none');
  return lines.join('\n');
}

if (require.main === module) {
  const [cmPath, dagPath] = process.argv.slice(2);
  if (!cmPath || !dagPath) { console.error('usage: codegraph-coverage.js <codemap.json> <dag.json>'); process.exit(2); }
  const codemap = JSON.parse(fs.readFileSync(cmPath, 'utf8'));
  const dag = JSON.parse(fs.readFileSync(dagPath, 'utf8'));
  console.log(coverage(codemap, dag));
}

module.exports = { coverage };
