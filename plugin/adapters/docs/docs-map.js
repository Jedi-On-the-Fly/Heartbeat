#!/usr/bin/env node
/**
 * docs-map.js — docs/research provider for the codemap contract (the SECOND domain).
 *
 * Turns a markdown corpus's CITATION graph into the same codemap the code adapter uses, so the
 * UNCHANGED dep-lint engine (plugin/adapters/code/deplint.js) validates a docs authoring DAG:
 *   - edges: [citerId, citedId]  — a section that links to another "builds on" it (depends on it)
 *   - tasks: { sectionId: [sectionId] } — the docs convention that one authoring task = one section
 * Unit id = the .md basename. Only relative links to another .md IN the corpus count; http(s)/
 * mailto/#anchors and links outside the corpus are ignored. Parity surface: the Python twin is
 * py/src/heartbeat/adapters/docs/docs_map.py (set-equal node ≡ python, T95). Imports nothing from core.
 *
 * Usage: node docs-map.js <corpusDir>
 */
'use strict';
const fs = require('fs');
const path = require('path');

function citationMap(corpusDir) {
  const files = fs.readdirSync(corpusDir).filter(f => f.endsWith('.md'));
  const ids = new Set(files.map(f => f.replace(/\.md$/, '')));
  const edges = [], seen = new Set();
  const inline = /\[[^\]]*\]\(([^)]+)\)/g;                          // [text](target)
  const refUse = /\[([^\]]*)\]\[([^\]]*)\]/g;                       // [text][label] or [text][] (collapsed)
  const refDef = /^[ \t]*\[([^\]]+)\]:[ \t]*(\S+)/gm;               // [label]: target  (definition line)
  for (const f of files) {
    const id = f.replace(/\.md$/, '');
    const text = fs.readFileSync(path.join(corpusDir, f), 'utf8');
    const defs = {};                                               // label(lower) -> target
    let d; while ((d = refDef.exec(text))) defs[d[1].trim().toLowerCase()] = d[2];
    const targets = [];                                            // raw link targets (inline + resolved refs)
    let m; while ((m = inline.exec(text))) targets.push(m[1]);
    let r; while ((r = refUse.exec(text))) {
      const label = (r[2].trim() || r[1].trim()).toLowerCase();    // collapsed [text][] -> label = text
      if (Object.prototype.hasOwnProperty.call(defs, label)) targets.push(defs[label]);
    }
    for (let target of targets) {
      target = target.trim();
      if (/^(https?:|mailto:|#)/i.test(target)) continue;          // external / anchor
      target = target.split('#')[0].split('?')[0];                 // strip fragment/query
      if (!target.endsWith('.md')) continue;
      const tid = path.basename(target).replace(/\.md$/, '');
      if (!ids.has(tid) || tid === id) continue;                   // outside corpus, or self-link
      const key = id + '|' + tid;
      if (!seen.has(key)) { seen.add(key); edges.push([id, tid]); }
    }
  }
  const tasks = {};
  for (const id of [...ids].sort()) tasks[id] = [id];              // one authoring task per section
  return { edges, tasks };
}

if (require.main === module) {
  const dir = process.argv[2];
  if (!dir) { console.error('usage: docs-map.js <corpusDir>'); process.exit(2); }
  console.log(JSON.stringify(citationMap(dir)));
}

module.exports = { citationMap };
