#!/usr/bin/env node
/**
 * codegraph-map.js — CodeGraph provider for the codemap contract (see README.md).
 *
 * Turns CodeGraph's graph rows into the codemap `edges` the dep-lint engine consumes:
 * resolves node id -> qualified_name and keeps only DEPENDENCY-BEARING edge types.
 *
 * NOTE on fidelity: CodeGraph is not vendored in this repo, so the row shape below
 * (nodes: {id, qualified_name, file, kind}; edges: {from_id, to_id, type}) and the
 * dependency-type allowlist are our documented, best-effort model of its schema — NOT
 * confirmed against a live database. The live DB read (readCodegraphDb) is harness-first
 * and unproven in-repo; the pure mapping (mapCodegraph) is what the suite gates.
 *
 * Usage: node codegraph-map.js <rows.json>          # rows JSON -> codemap JSON (gated)
 *        node codegraph-map.js <db-path> --db        # read a CodeGraph .db (harness-first)
 */
'use strict';
const fs = require('fs');

// Dependency-bearing edge types (allowlist). A structural/containment edge is not a dependency.
const DEP_TYPES = new Set(['calls', 'imports', 'inheritance']);

function mapCodegraph(rows) {
  const id2qn = {};
  for (const n of (rows.nodes || [])) id2qn[n.id] = n.qualified_name;
  const edges = [];
  for (const e of (rows.edges || [])) {
    if (!DEP_TYPES.has(e.type)) continue;                 // drop non-dependency edges
    const from = id2qn[e.from_id], to = id2qn[e.to_id];
    if (from == null || to == null) continue;             // skip edges to unknown nodes
    edges.push([from, to]);
  }
  return { edges };
}

// HARNESS-FIRST: read a CodeGraph .codegraph/codegraph.db into the rows shape via the sqlite3
// CLI. Needs CodeGraph + sqlite3; NOT wired into the suite (unproven in-repo). Degrades clearly.
function readCodegraphDb(dbPath) {
  const { execFileSync } = require('child_process');
  const q = sql => {
    try { return execFileSync('sqlite3', ['-json', dbPath, sql], { encoding: 'utf8' }); }
    catch (e) { throw new Error(`codegraph-map: cannot read ${dbPath} via sqlite3 (${e.message}). ` +
      `This path is harness-first — it needs CodeGraph's database and the sqlite3 CLI.`); }
  };
  return {
    nodes: JSON.parse(q('SELECT id, qualified_name, file, kind FROM nodes') || '[]'),
    edges: JSON.parse(q('SELECT from_id, to_id, type FROM edges') || '[]'),
  };
}

// BEST-EFFORT / FUZZY (advisory, not gated): map each task to the qualified_names its title or
// description mentions by leaf-name substring. The plan author confirms — never auto-applied.
function resolveTaskSymbols(dag, nodes) {
  const qns = (nodes || []).map(n => n.qualified_name).filter(Boolean);
  const tasks = {};
  for (const p of (dag.phases || [])) for (const t of (p.tasks || [])) {
    const hay = ((t.title || '') + ' ' + (t.description || '')).toLowerCase();
    tasks[t.id] = qns.filter(qn => { const leaf = qn.split('::').pop().toLowerCase(); return leaf && hay.includes(leaf); });
  }
  return tasks;
}

if (require.main === module) {
  const [pathArg, flag] = process.argv.slice(2);
  if (!pathArg) { console.error('usage: codegraph-map.js <rows.json>  |  codegraph-map.js <db> --db'); process.exit(2); }
  const rows = flag === '--db' ? readCodegraphDb(pathArg) : JSON.parse(fs.readFileSync(pathArg, 'utf8'));
  console.log(JSON.stringify(mapCodegraph(rows)));
}

module.exports = { mapCodegraph, readCodegraphDb, resolveTaskSymbols };
