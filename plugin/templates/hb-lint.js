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
 *   - malformed plan-time constraints (gates.<G>.review.constraints)
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
  const phaseIds = new Set();

  for (const p of phases) {
    // A duplicate phase id silently MERGES two phases in the projection — the append-time
    // mistake (replanning adds phases to a dag whose ids are already taken). Same bar as tasks.
    // Scoped to non-empty STRING ids so both runtimes classify degenerate shapes (missing id,
    // null, numbers) identically — a refuter catch: p["id"] crashed python on an id-less phase.
    if (typeof p.id === 'string' && p.id) {
      if (phaseIds.has(p.id)) errors.push(`duplicate phase ID: ${p.id}`);
      phaseIds.add(p.id);
    }
    const pidS = (typeof p.id === 'string' && p.id) ? p.id : '?';   // degenerate ids render '?' on BOTH runtimes (a refuter catch: the coercions diverged)
    const tasks = p.tasks ?? [];
    if (tasks.length > 8) {
      warnings.push(`[${pidS}] ${tasks.length} tasks (>8) — context-loss risk, consider sub-phases`);
    }
    for (const t of tasks) {
      if (taskIds.has(t.id)) errors.push(`duplicate task ID: ${t.id}`);
      taskIds.add(t.id);
      taskMap[t.id] = t;
    }
    for (const g of [p.gate_entry, p.gate_exit]) {
      if (g && !gates[g]) errors.push(`[${pidS}] undefined gate: ${g}`);
    }
    if (p.gate_entry && !phases.some(q => q.gate_exit === p.gate_entry)) {
      errors.push(`[${pidS}] gate_entry ${p.gate_entry} is no phase's gate_exit — phase locked forever`);
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
    // Criteria SHAPE is lint's to own: every entry must be an object with a string cmd — the
    // runners eval cmd and every static reader walks these entries, so garbage here crashed
    // doctor/audit on both runtimes (a refuter catch). Loud, identical bytes across runtimes.
    ((gates[g] && typeof gates[g] === 'object' && !Array.isArray(gates[g]) ? gates[g].criteria : null) || []).forEach((c, i) => {
      if (!c || typeof c !== 'object' || Array.isArray(c) || typeof c.cmd !== 'string')
        errors.push(`[${g}] criteria entry ${i} must be an object with a string cmd (got ${JSON.stringify(c).slice(0, 120)})`);
    });
  }

  checkPlaceholders(dag, warnings);
  checkGateArtifacts(dag, warnings);
  checkConstraints(dag, errors);
  checkRegate(dag, errors);   // regate-guard
  checkDetach(dag, errors);   // detach-guard
  return { errors, warnings };
}

// "Non-blank" with ONE explicit whitespace set (ASCII " \t\n\r\f\v") — JS trim() and python strip()
// disagree on \ufeff / \x1c-\x1f / \x85, and the two lints must return identical errors.
const blankFree = (s) => /[^ \t\n\r\f\v]/.test(s);

// Plan-time constraints of a gate's adversarial review: gates.<G>.review.constraints =
// [{id P<n>, claim, subjects:[…], violation}]. Each is a falsifiable claim the refuter must answer.
// G<n> ids are reserved for the constraints authored at review time. Twin: lint.py _check_constraints.
function checkConstraints(dag, errors) {
  const gates = dag.gates ?? {};
  for (const g of Object.keys(gates)) {
    const gv = gates[g] || {};
    if (Object.prototype.hasOwnProperty.call(gv, 'constraints'))
      errors.push(`[${g}] constraints belong in review.constraints (the plan-time constraints of the gate's adversarial review)`);
    const rv = gv.review;
    // A review must be a NON-EMPTY object: node's truthiness and python's bool() disagree on {} / [],
    // so any other shape would make the runtimes disagree on whether the gate owes a review.
    if (rv !== undefined && rv !== null && (typeof rv !== 'object' || Array.isArray(rv) || !Object.keys(rv).length))
      errors.push(`[${g}] review must be a non-empty object ({prompt, profile?, constraints?})`);
    if (!rv || typeof rv !== 'object' || Array.isArray(rv) || !Object.prototype.hasOwnProperty.call(rv, 'constraints')) continue;
    const cs = rv.constraints;
    if (!Array.isArray(cs)) { errors.push(`[${g}] review.constraints must be a list of {id, claim, subjects, violation}`); continue; }
    for (const m of constraintErrors(cs, 'P')) errors.push(`[${g}] ${m}`);
  }
}

// A gate's regate record (written by `hb regate`, honored by every evaluation/acceptance path):
// {at?, reason, actor, prev_criteria, pending, rearm?}. A malformed record must ERROR on BOTH
// lints — a shape the runtimes read permissively would let a hand-mangled marker silently
// disarm the fail-closed perimeter. Twin: lint.py _check_regate (messages verbatim).
function checkRegate(dag, errors) {
  const gates = dag.gates ?? {};
  for (const g of Object.keys(gates)) {
    const r = (gates[g] || {}).regate;
    if (r === undefined) continue;
    if (r === null || typeof r !== 'object' || Array.isArray(r) || !Object.keys(r).length) {
      errors.push(`[${g}] regate must be a non-empty object ({at?, reason, actor, prev_criteria, pending, rearm?})`);
      continue;
    }
    if (typeof r.pending !== 'boolean') errors.push(`[${g}] regate.pending must be true or false`);
    if (typeof r.reason !== 'string' || !blankFree(r.reason)) errors.push(`[${g}] regate.reason must be a non-empty string (why the premises changed)`);
    if (typeof r.actor !== 'string' || !blankFree(r.actor)) errors.push(`[${g}] regate.actor must be a non-empty string (who declared the revision)`);
    if (!Array.isArray(r.prev_criteria)) errors.push(`[${g}] regate.prev_criteria must be a list (the criteria snapshot at declare time)`);
    if (r.at !== undefined && (typeof r.at !== 'string' || !blankFree(r.at))) errors.push(`[${g}] regate.at must be a non-empty string timestamp`);
    if (r.rearm !== undefined) {
      const w = r.rearm;
      const strOk = (v) => typeof v === 'string' && blankFree(v);
      if (w === null || typeof w !== 'object' || Array.isArray(w) || !strOk(w.actor) || !strOk(w.artifact) || !strOk(w.sha256))
        errors.push(`[${g}] regate.rearm must be an object with non-empty actor, artifact and sha256 strings`);
    }
  }
}

// A phase's detach record (written by `hb detach`, honored by changed()'s base and the report):
// {detached_from, detached_reason, detached_by, detached_at} together, gate_entry null while they
// stand, detached_from a defined gate that is some phase's gate_exit (a bare 'defined' restore
// would re-create the 'phase locked forever' resolver brick), and the phase id usable as an anchor
// file name. Gate ids matching ^_start$ or ^_detach_ are RESERVED (the anchors/ namespace — an
// acceptance anchor for such a gate would collide with the detach/start anchors).
// Twin: lint.py _check_detach (messages verbatim).
const DETACH_SAFE_ID = /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/;   // == hb.js SAFE_GATE_ID (duplicated: hb.js requires this module)
function checkDetach(dag, errors) {
  const gates = dag.gates ?? {};
  for (const g of Object.keys(gates)) {
    // exact equality + prefix, NOT a regex: python's $ matches before a trailing newline and JS's
    // does not, so the twin regexes diverged on a gate named "_start\n" (a refuter fuzz catch)
    if (g === '_start' || g.startsWith('_detach_')) errors.push(`[${g}] gate ids matching ^_start$ or ^_detach_ are reserved for the anchors namespace — rename the gate`);
  }
  const exits = new Set((dag.phases ?? []).map(p => p.gate_exit).filter(Boolean));
  for (const p of (dag.phases ?? [])) {
    const fields = ['detached_from', 'detached_reason', 'detached_by', 'detached_at'];
    const has = fields.filter(k => Object.prototype.hasOwnProperty.call(p, k));
    if (!has.length) continue;
    if (has.length < fields.length) { errors.push(`[${p.id}] detach fields are partial (${has.join(', ')}) — a detach records detached_from, detached_reason, detached_by and detached_at together`); continue; }
    if (p.gate_entry !== null && p.gate_entry !== undefined) errors.push(`[${p.id}] detach fields alongside a non-null gate_entry — a half-reattach; reattach properly or clear the fields`);
    if (typeof p.detached_from !== 'string' || !blankFree(p.detached_from) || !gates[p.detached_from] || !exits.has(p.detached_from)) errors.push(`[${p.id}] detached_from must name a defined gate that is some phase's gate_exit (got ${JSON.stringify(p.detached_from)})`);
    if (typeof p.detached_reason !== 'string' || !blankFree(p.detached_reason)) errors.push(`[${p.id}] detached_reason must be a non-empty string`);
    if (typeof p.detached_by !== 'string' || !blankFree(p.detached_by)) errors.push(`[${p.id}] detached_by must be a non-empty string`);
    if (typeof p.detached_at !== 'string' || !blankFree(p.detached_at)) errors.push(`[${p.id}] detached_at must be a non-empty string timestamp`);
    if (typeof p.id !== 'string' || !DETACH_SAFE_ID.test(p.id)) errors.push(`[${p.id}] a detached phase id must be usable as an anchor file name ([A-Za-z0-9_][A-Za-z0-9_.-]*)`);
  }
}

// Validate one constraint list; kind 'P' (plan-time, in dag.json) or 'G' (gate-time, recorded by
// `hb constraints --record`). Messages carry no gate prefix. Twin: lint.py constraint_errors.
const CONSTRAINT_ID_RULE = {
  P: 'id must be P<n> (plan-time; G<n> ids are reserved for gate-time constraints)',
  G: 'id must be G<n> (gate-time; P<n> ids belong to the plan)',
};
function constraintErrors(cs, kind) {
  const out = [], seen = new Set(), idRe = kind === 'G' ? /^G[0-9]+$/ : /^P[0-9]+$/;
  cs.forEach((c, i) => {
    const isObj = c !== null && typeof c === 'object' && !Array.isArray(c);
    const label = isObj && typeof c.id === 'string' && c.id ? c.id : `#${i + 1}`;
    if (!isObj) { out.push(`constraint ${label}: must be an object {id, claim, subjects, violation}`); return; }
    if (typeof c.id !== 'string' || !idRe.test(c.id)) out.push(`constraint ${label}: ${CONSTRAINT_ID_RULE[kind]}`);
    else if (seen.has(c.id)) out.push(`constraint ${c.id}: duplicate id in this gate`);
    else seen.add(c.id);
    for (const f of ['claim', 'violation'])
      if (typeof c[f] !== 'string' || !blankFree(c[f])) out.push(`constraint ${label}: ${f} must be a non-empty string`);
    if (!Array.isArray(c.subjects) || !c.subjects.length || c.subjects.some(x => typeof x !== 'string' || !blankFree(x)))
      out.push(`constraint ${label}: subjects must be a non-empty list of non-empty strings (the files/areas it covers)`);
  });
  return out;
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
      if (!c || typeof c !== 'object' || Array.isArray(c) || typeof c.cmd !== 'string') continue;   // hostile shapes are lint ERRORS (the criteria-shape rule), skipped here
      for (const p of extractPaths(c.cmd)) {
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
module.exports = { lint, extractPaths, constraintErrors };
