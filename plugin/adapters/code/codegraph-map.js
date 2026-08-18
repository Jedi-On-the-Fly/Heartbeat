#!/usr/bin/env node
/**
 * codegraph-map.js — CodeGraph provider for the codemap contract (see README.md).
 *
 * Turns CodeGraph's graph rows into the codemap `edges` the dep-lint engine consumes:
 * resolves node id -> qualified_name and keeps only DEPENDENCY-BEARING edge types.
 *
 * NOTE on fidelity: CodeGraph is not vendored in this repo, so the internal row shape below
 * (nodes: {id, qualified_name, file, kind}; edges: {from_id, to_id, type}) is our own stable
 * contract that the pure mapping (mapCodegraph) and the suite fixtures gate. The live DB read
 * (readCodegraphDb) maps CodeGraph's ACTUAL columns onto it — confirmed against CodeGraph 1.5.0
 * (nodes.file_path, edges.source/target/kind; a dependency is any resolved edge except structural
 * `contains`) and proved harness-first by tests/real-codegraph-map.sh. The pure mapping is gated.
 *
 * Usage: node codegraph-map.js <rows.json>          # rows JSON -> codemap JSON (gated)
 *        node codegraph-map.js <db-path> --db        # read a CodeGraph .db (harness-first)
 */
'use strict';
const fs = require('fs');

// Structural containment is NOT a dependency; every other resolved edge is. A DENYLIST (not an
// allowlist) so a new CodeGraph dependency kind is never silently dropped — the failure mode that
// hid 1.5.0's `extends`/`instantiates` behind a stale `{calls,imports,inheritance}` allowlist.
// This mirrors CodeGraph's OWN dependency rule (`WHERE e.kind != 'contains'`). 1.5.0 edge kinds:
// calls, imports, exports, extends, implements, references, type_of, returns, instantiates,
// overrides, decorates (all dependency-bearing) + contains (structural — the sole exclusion).
const NON_DEP_TYPES = new Set(['contains']);

function mapCodegraph(rows) {
  const id2qn = {};
  for (const n of (rows.nodes || [])) id2qn[n.id] = n.qualified_name;
  const edges = [];
  for (const e of (rows.edges || [])) {
    if (NON_DEP_TYPES.has(e.type)) continue;              // drop structural containment
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
  // CodeGraph 1.5.0 schema, aliased onto our internal row keys (see NOTE above).
  return {
    nodes: JSON.parse(q('SELECT id, qualified_name, file_path AS file, kind FROM nodes') || '[]'),
    edges: JSON.parse(q('SELECT source AS from_id, target AS to_id, kind AS type FROM edges') || '[]'),
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
