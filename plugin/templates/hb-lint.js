#!/usr/bin/env node
/**
 * hb-lint.js — Static validation of dag.json
 *
 * Errors (exit 1):
 *   - duplicate task IDs
 *   - requires pointing to a non-existent ID
 *   - dependency cycle
 *   - gate_entry / gate_exit referencing an undefined gate
 *   - gate_entry that is no phase's gate_exit (phase locked forever)
 * Warnings (exit 0):
 *   - phase > 8 tasks (context-loss risk)
 *   - gate defined but never referenced
 *   - leftover template/skeleton text (v1.4)
 *   - gate cmd references a file no task produces (v1.4)
 *
 * Usage: node hb-lint.js <dag.json> [--json]
 * Module: const { lint } = require('./hb-lint.js')  → { errors, warnings }
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
      warnings.push(`[${p.id}] ${tasks.length} tasks (>8) — context-loss risk, consider sub-phases`);
    }
    for (const t of tasks) {
      if (taskIds.has(t.id)) errors.push(`duplicate task ID: ${t.id}`);
      taskIds.add(t.id);
      taskMap[t.id] = t;
    }
    for (const g of [p.gate_entry, p.gate_exit]) {
      if (g && !gates[g]) errors.push(`[${p.id}] undefined gate: ${g}`);
    }
    if (p.gate_entry && !phases.some(q => q.gate_exit === p.gate_entry)) {
      errors.push(`[${p.id}] gate_entry ${p.gate_entry} is no phase's gate_exit — phase locked forever`);
    }
  }

  for (const id of taskIds) {
    for (const r of (taskMap[id].requires ?? [])) {
      if (!taskIds.has(r)) errors.push(`[${id}] requires a non-existent task: ${r}`);
    }
  }

  // Cycles — tri-color DFS
  const color = {}; const stack = [];
  function dfs(id) {
    color[id] = 1; stack.push(id);
    for (const r of (taskMap[id]?.requires ?? [])) {
      if (!taskMap[r]) continue;
      if (color[r] === 1) {
        errors.push(`dependency cycle: ${[...stack.slice(stack.indexOf(r)), r].join(' → ')}`);
        continue;
      }
      if (!color[r]) dfs(r);
    }
    stack.pop(); color[id] = 2;
  }
  for (const id of taskIds) if (!color[id]) dfs(id);

  for (const g of Object.keys(gates)) {
    if (!phases.some(p => p.gate_entry === g || p.gate_exit === g)) {
      warnings.push(`gate defined but never referenced: ${g}`);
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
    warnings.push(`DAG still contains skeleton/template text (${hits.slice(0, 3).join(', ')}${hits.length > 3 ? ', …' : ''}) — replace with the real plan`);
  }
}

// v1.4 (#1): warn when a gate cmd references a file/dir that no task appears to
// produce (heuristic). Catches "gate runs tests/e2e/x.spec.js but nothing writes it".
// Drop single-quoted spans that sit OUTSIDE double quotes: in shell those are literal
// strings the command searches FOR (grep/sed patterns, e.g. grep '@import "blocks/x.css"'),
// not files it depends on. A single quote INSIDE a double-quoted string is just a character
// — "require('$PROJECT_DIR/f.js')" keeps its path.
function stripSingleQuoted(cmd) {
  let out = '', inDouble = false;
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i];
    if (c === '"') { inDouble = !inDouble; out += c; }
    else if (c === "'" && !inDouble) {
      const j = cmd.indexOf("'", i + 1);
      if (j === -1) { out += cmd.slice(i); break; }
      out += ' '; i = j;
    } else out += c;
  }
  return out;
}
function extractPaths(cmd) {
  const out = new Set();
  const src = stripSingleQuoted(cmd);
  for (const tokRaw of (src.match(/[\w.\-/${}]+/g) || [])) {
    if (!tokRaw.includes('/')) continue;            // must look like a path
    if (/HB_DIR/.test(tokRaw)) continue;            // HeartBeat's own dir
    let p = tokRaw.replace(/\$\{?PROJECT_DIR\}?\//, '').replace(/^\.\//, '');
    if (!p || /[${}]/.test(p)) continue;            // unresolved var anywhere (blocks/$n.css, ${X:-…} shrapnel)
    if (p.startsWith('/')) continue;                // absolute path — a system/tool path, not a produced artifact
    if (p.includes('.hb/')) continue;
    const base = p.replace(/\/$/, '').split('/').pop();
    if (['state.json', 'dag.json', 'events.jsonl'].includes(base)) continue;
    // Exclude shell constructs that merely contain slashes — sed `s/a/b/`, `y/a/b/` — which start with a
    // single-letter command segment. A real artifact path (`tests/x.js`, `dist/`, `a/b/Dockerfile`) does
    // not. (Absolute paths and awk `/re/` are already excluded above by the leading-`/` check.) This
    // keeps EXTENSIONLESS artifacts (Dockerfile, Makefile, bin/hb) tracked for rot.
    if (/^[A-Za-z]\//.test(p)) continue;
    // Only rot-check tokens that look like a produced FILE: a file extension, or a known extensionless
    // artifact name (Dockerfile/Makefile). Drops relative path-shaped non-files — module specifiers
    // (playwright/test), URL paths (host:3000/health), route args (api/v1/users) — that are never on disk.
    if (!/\.[A-Za-z0-9]+$/.test(base) && base !== 'Dockerfile' && base !== 'Makefile') continue;
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
        warnings.push(`gate references ${p} — no task appears to produce it (make sure a task writes it)`);
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
    if (asJson) console.log(JSON.stringify({ errors: [`dag.json unreadable: ${e.message}`], warnings: [] }));
    else console.error(`✗ dag.json unreadable: ${e.message}`);
    process.exit(1);
  }
  const { errors, warnings } = lint(dag);
  if (asJson) console.log(JSON.stringify({ errors, warnings }));
  else {
    for (const e of errors)   console.log(`  ✗ ${e}`);
    for (const w of warnings) console.log(`  ⚠ ${w}`);
    console.log(errors.length ? `✗ ${errors.length} error(s), ${warnings.length} warning(s)`
                              : `✓ DAG valid (${warnings.length} warning(s))`);
  }
  process.exit(errors.length ? 1 : 0);
}
module.exports = { lint, extractPaths };
