#!/usr/bin/env node
/**
 * ground-check.js — the research adapter's grounding verifier (Seam: grounding).
 *
 * Given an evidence map ({ sources:{id:{url,sha256,fetched}}, claims:{id:{text,source,excerpt,section}} })
 * and a directory of stored source texts (<sourcesDir>/<id>.txt), verify OFFLINE that every claim is
 * GROUNDED: the cited source is declared, its stored file exists and still matches the recorded sha256
 * (STALE detection), and a whitespace-normalized `excerpt` is a substring of that text (so a
 * FABRICATED-QUOTE — a quote not in the source — is caught). This is the deterministic GATE half of the
 * evidence lifecycle for research: it proves the quote is REAL. Whether the quote *supports* the claim
 * (semantics) is the adversarial review's job. It verifies GROUNDING, not TRUTH.
 *
 * Advisory by default; --strict exits 1 iff there are issues. node ≡ python. Imports nothing from core.
 *
 * Usage: node ground-check.js <evidence.json> <sourcesDir> [--strict]
 */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const norm = (s) => (s || '').replace(/\s+/g, ' ').trim();

function groundCheck(evidence, sourcesDir) {
  const sources = (evidence || {}).sources || {};
  const claims = (evidence || {}).claims || {};
  const issues = [];
  let grounded = 0;
  for (const id of Object.keys(claims).sort()) {
    const c = claims[id] || {};
    const sid = c.source;
    if (!sid || !Object.prototype.hasOwnProperty.call(sources, sid)) {
      issues.push(`UNGROUNDED: ${id} — source ${sid || '(none)'} not in evidence.sources`); continue;
    }
    const file = path.join(sourcesDir, sid + '.txt');
    if (!fs.existsSync(file)) { issues.push(`MISSING-SOURCE: ${id} — stored source ${sid}.txt not found`); continue; }
    const bytes = fs.readFileSync(file);
    const recorded = sources[sid].sha256;
    // sha BEFORE excerpt: an edited source must surface as STALE even if it still contains the excerpt.
    if (recorded && crypto.createHash('sha256').update(bytes).digest('hex') !== recorded) {
      issues.push(`STALE: ${id} — source ${sid} changed since fetch (sha mismatch)`); continue;
    }
    const excerpt = norm(c.excerpt);
    if (!excerpt) { issues.push(`UNGROUNDED: ${id} — no excerpt`); continue; }
    if (!norm(bytes.toString('utf8')).includes(excerpt)) {
      issues.push(`FABRICATED-QUOTE: ${id} — excerpt not found in source ${sid}`); continue;
    }
    grounded++;
  }
  return { grounded, issues };
}

function formatReport(r) {
  return [`HB-GROUND: grounded=${r.grounded} issues=${r.issues.length}`, ...r.issues].join('\n');
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const strict = args.includes('--strict');
  const [evPath, srcDir] = args.filter((a) => !a.startsWith('--'));
  if (!evPath || !srcDir) { console.error('usage: ground-check.js <evidence.json> <sourcesDir> [--strict]'); process.exit(2); }
  const evidence = JSON.parse(fs.readFileSync(evPath, 'utf8'));
  const r = groundCheck(evidence, srcDir);
  console.log(formatReport(r));
  process.exit(strict && r.issues.length ? 1 : 0);
}

module.exports = { groundCheck, formatReport };
