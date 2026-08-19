#!/usr/bin/env node
/**
 * codegraph-discover.js — discovery mode for the code adapter (Seam 1, used FORWARD).
 *
 * Given a codemap ({edges:[[A,B]]}, A depends on B) and entry-point symbols, compute the
 * transitively-reachable AFFECTED set in a direction, plus the induced subgraph — so a planner can
 * scope a change before authoring the DAG, then map the affected symbols to tasks (deplint verifies
 * ordering). This is ADVISORY: the graph models resolved static edges only (not dynamic/framework
 * bindings or not-yet-existing symbols), and it never rewrites the DAG.
 *
 *   dependents   = reverse reachability — who transitively depends on the entry = CHANGE IMPACT
 *   dependencies = forward reachability — what the entry transitively needs
 *   both         = the union
 *
 * Output is DETERMINISTIC (sorted) so it is a parity surface: the Python twin
 * (py/src/heartbeat/adapters/code/codegraph_discover.py) emits byte-identical JSON (proof T98).
 *
 * Usage: node codegraph-discover.js <codemap.json> <e1,e2,...> [--dependents|--dependencies|--both]
 */
'use strict';
const fs = require('fs');

function discover(codemap, entries, direction) {
  const dir = direction || 'both';
  const fwd = new Map();   // A -> set of B   (A depends on B)
  const rev = new Map();   // B -> set of A
  for (const e of (codemap.edges || [])) {
    const a = e[0], b = e[1];
    if (!fwd.has(a)) fwd.set(a, new Set()); fwd.get(a).add(b);
    if (!rev.has(b)) rev.set(b, new Set()); rev.get(b).add(a);
  }
  const reach = (adj, seeds) => {                     // transitive closure from seeds over adj
    const seen = new Set(seeds);
    const stack = [...seeds];
    while (stack.length) {
      const n = stack.pop();
      for (const m of (adj.get(n) || [])) if (!seen.has(m)) { seen.add(m); stack.push(m); }
    }
    return seen;
  };
  const seeds = [...new Set(entries)];
  let affected;
  if (dir === 'dependents') affected = reach(rev, seeds);
  else if (dir === 'dependencies') affected = reach(fwd, seeds);
  else affected = new Set([...reach(rev, seeds), ...reach(fwd, seeds)]);   // both
  const inAff = s => affected.has(s);
  const edges = (codemap.edges || [])
    .filter(e => inAff(e[0]) && inAff(e[1]))
    .map(e => [e[0], e[1]]);
  edges.sort((x, y) => (x[0] < y[0] ? -1 : x[0] > y[0] ? 1 : x[1] < y[1] ? -1 : x[1] > y[1] ? 1 : 0));
  return {
    entry: seeds.slice().sort(),
    direction: dir,
    affected: [...affected].sort(),
    edges,
  };
}

if (require.main === module) {
  const [mapPath, entriesArg, flag] = process.argv.slice(2);
  if (!mapPath || !entriesArg) {
    console.error('usage: codegraph-discover.js <codemap.json> <e1,e2,...> [--dependents|--dependencies|--both]');
    process.exit(2);
  }
  const dir = (flag || '--both').replace(/^--/, '');
  if (!['dependents', 'dependencies', 'both'].includes(dir)) { console.error(`bad direction: ${flag}`); process.exit(2); }
  const codemap = JSON.parse(fs.readFileSync(mapPath, 'utf8'));
  const entries = entriesArg.split(',').filter(Boolean);
  console.log(JSON.stringify(discover(codemap, entries, dir)));
}

module.exports = { discover };
