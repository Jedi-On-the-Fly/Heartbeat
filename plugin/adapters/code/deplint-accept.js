#!/usr/bin/env node
/**
 * deplint-accept.js — plan-acceptance wrapper for code dep-lint (Seam 1).
 *
 * Auto-surfaces dep-lint at plan acceptance: RESOLVES a codemap from the project, then delegates to
 * the real `deplint` (same report). Resolution order:
 *   --codemap <f>                     explicit codemap
 *   <dir>/codemap.json                a codemap you authored
 *   <dir>/.codegraph/codegraph.db     provisional: CodeGraph edges + fuzzy task→symbol (harness-first)
 *   else                              SKIP cleanly (non-code / un-indexed project)
 *
 * Advisory by default (exit 0); --strict exits 1 iff missing or collision. It never rewrites the DAG.
 * The db-build path is harness-first — proved by tests/real-deplint-accept.sh (skips without CodeGraph).
 *
 * Usage: node deplint-accept.js --dir <proj> --dag <dag.json> [--codemap <f>] [--strict]
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { deplint, formatReport } = require('./deplint.js');

function arg(args, name) { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; }

// Resolve a codemap for <dir>+<dag>, or null to signal SKIP. The db-build branch is harness-first.
function resolveCodemap(dir, dag, explicit) {
  if (explicit) return { codemap: JSON.parse(fs.readFileSync(explicit, 'utf8')), note: null };
  if (dir) {
    const cm = path.join(dir, 'codemap.json');
    if (fs.existsSync(cm)) return { codemap: JSON.parse(fs.readFileSync(cm, 'utf8')), note: null };
    const db = path.join(dir, '.codegraph', 'codegraph.db');
    if (fs.existsSync(db)) {
      const { readCodegraphDb, mapCodegraph, resolveTaskSymbols } = require('./codegraph-map.js');
      const rows = readCodegraphDb(db);
      const codemap = { edges: mapCodegraph(rows).edges, tasks: resolveTaskSymbols(dag, rows.nodes) };
      return { codemap, note: 'NOTE: provisional codemap (CodeGraph edges + fuzzy task→symbol) — confirm' };
    }
  }
  return null;
}

// accept(dir, dag, {explicit, strict}) -> { text, code }. Pure w.r.t. output (no printing).
function accept(dir, dag, opts) {
  opts = opts || {};
  const resolved = resolveCodemap(dir, dag, opts.explicit);
  if (!resolved) {
    return { text: `DEPLINT-ACCEPT-SKIP: no codemap or CodeGraph index in ${dir} (deplint skipped)`, code: 0 };
  }
  const r = deplint(dag, resolved.codemap);
  const report = formatReport(r);
  const text = resolved.note ? `${resolved.note}\n${report}` : report;
  const code = opts.strict && (r.missing.length || r.collision.length) ? 1 : 0;
  return { text, code };
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const dir = arg(args, '--dir');
  const dagPath = arg(args, '--dag');
  const explicit = arg(args, '--codemap');
  const strict = args.includes('--strict');
  if (!dagPath) { console.error('usage: deplint-accept.js --dir <proj> --dag <dag.json> [--codemap <f>] [--strict]'); process.exit(2); }
  const dag = JSON.parse(fs.readFileSync(dagPath, 'utf8'));
  const { text, code } = accept(dir, dag, { explicit, strict });
  console.log(text);
  process.exit(code);
}

module.exports = { accept, resolveCodemap };
