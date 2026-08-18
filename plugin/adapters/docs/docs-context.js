#!/usr/bin/env node
/**
 * docs-context.js — docs Seam-2 provider: render the TEXT of the sections a task directly cites.
 *
 * Given the corpus + the codemap + a task id, find the sections that task touches, follow their
 * DIRECT citations (edges from them), and render each cited section's text — the "read these before
 * writing" block fed to Stage B through the generic context_cmd hook. Parity surface: the Python
 * twin is py/src/heartbeat/adapters/docs/docs_context.py (node ≡ python, T95). Imports nothing from core.
 *
 * Usage: node docs-context.js <corpusDir> <codemap.json> <taskId>
 */
'use strict';
const fs = require('fs');
const path = require('path');

function citedContext(corpusDir, codemap, taskId) {
  const edges = codemap.edges || [];
  const sections = (codemap.tasks || {})[taskId] || [];
  const cited = [];
  for (const s of sections) for (const e of edges) if (e[0] === s && !cited.includes(e[1])) cited.push(e[1]);
  const out = [`Context for task ${taskId} — read the sections it directly cites before writing:`];
  if (!cited.length) { out.push('  (this task cites nothing)'); return out.join('\n'); }
  for (const c of cited) {
    let text;
    try { text = fs.readFileSync(path.join(corpusDir, c + '.md'), 'utf8').trim(); }
    catch (e) { text = '(section text unavailable)'; }
    out.push(`\n--- ${c} ---\n${text}`);
  }
  return out.join('\n');
}

if (require.main === module) {
  const [corpus, mapPath, taskId] = process.argv.slice(2);
  if (!corpus || !mapPath || !taskId) { console.error('usage: docs-context.js <corpusDir> <codemap.json> <taskId>'); process.exit(2); }
  console.log(citedContext(corpus, JSON.parse(fs.readFileSync(mapPath, 'utf8')), taskId));
}

module.exports = { citedContext };
