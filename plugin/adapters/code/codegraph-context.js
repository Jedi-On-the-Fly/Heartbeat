#!/usr/bin/env node
/**
 * codegraph-context.js — Seam 2 provider: render a task's code subgraph as context text.
 *
 * Given the codemap contract (see README.md) and a task id, emit a readable block naming the
 * symbols the task touches and their DIRECT neighbors (what each depends on, and what uses it) —
 * the subgraph an agent needs to do the task, not the whole graph. Fed to Stage B via the
 * executor's generic `context_cmd` hook (HB_EXEC_CONTEXT_CMD). Parity surface: the Python twin is
 * py/src/heartbeat/adapters/code/codegraph_context.py (node ≡ python, T94). Imports nothing from core.
 *
 * Usage: node codegraph-context.js <codemap.json> <TASKID>
 */
'use strict';
const fs = require('fs');

function contextFor(codemap, taskId) {
  const edges = codemap.edges || [];
  const touched = (codemap.tasks || {})[taskId] || [];
  const out = [`Code context for task ${taskId} — the symbols it touches and their direct neighbors:`];
  if (!touched.length) { out.push('  (no symbols mapped to this task)'); return out.join('\n'); }
  for (const sym of touched) {
    const deps  = [...new Set(edges.filter(e => e[0] === sym).map(e => e[1]))];   // sym depends on these
    const users = [...new Set(edges.filter(e => e[1] === sym).map(e => e[0]))];   // these use sym
    out.push(`  ${sym}`);
    if (deps.length)  out.push(`    depends on: ${deps.join(', ')}`);
    if (users.length) out.push(`    used by:    ${users.join(', ')}`);
  }
  return out.join('\n');
}

if (require.main === module) {
  const [mapPath, taskId] = process.argv.slice(2);
  if (!mapPath || !taskId) { console.error('usage: codegraph-context.js <codemap.json> <TASKID>'); process.exit(2); }
  console.log(contextFor(JSON.parse(fs.readFileSync(mapPath, 'utf8')), taskId));
}

module.exports = { contextFor };
