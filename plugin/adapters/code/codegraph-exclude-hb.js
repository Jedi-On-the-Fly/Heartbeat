#!/usr/bin/env node
/**
 * codegraph-exclude-hb.js — keep CodeGraph off HeartBeat's own scaffold.
 *
 * HeartBeat scaffolds a `.hb/` directory (orchestration code) inside a project; CodeGraph would index
 * it and pollute the graph the code adapter reads. This idempotently ensures the project's root
 * `codegraph.json` excludes `.hb/` (CodeGraph reads that file's `exclude` array), preserving any
 * existing config. Run it BEFORE `codegraph init`. The real indexing effect is proved harness-first by
 * tests/real-codegraph-exclude-hb.sh (skips without CodeGraph).
 *
 * Usage: node codegraph-exclude-hb.js [root]   (default root '.')
 */
'use strict';
const fs = require('fs');
const path = require('path');

function ensureHbExcluded(root) {
  const p = path.join(root || '.', 'codegraph.json');
  let cfg = {};
  if (fs.existsSync(p)) { try { cfg = JSON.parse(fs.readFileSync(p, 'utf8')) || {}; } catch (e) { cfg = {}; } }
  const ex = Array.isArray(cfg.exclude) ? cfg.exclude : [];
  if (!ex.includes('.hb/')) ex.push('.hb/');
  cfg.exclude = ex;
  fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + '\n');
  return cfg;
}

if (require.main === module) {
  ensureHbExcluded(process.argv[2] || '.');
}

module.exports = { ensureHbExcluded };
