#!/usr/bin/env node
/**
 * research-context.js — research Seam-2 provider: render a section's GROUNDED claims for the writer.
 *
 * Given an (already ground-checked) evidence map ({ sources:{id:{url,…}}, claims:{id:{text,source,
 * excerpt,section}} }) and a section name, render the block of that section's claims — each with its
 * id + paraphrase, cited source + url, and the verbatim excerpt — that is fed to Stage B through the
 * generic context_cmd hook before it writes the section. Only that section's claims; deterministic;
 * node ≡ python BYTE-identical (parity surface). Imports nothing from core.
 *
 * Grounding is verified upstream by ground-check — this only renders. Usage:
 *   node research-context.js <evidence.json> <section>
 */
'use strict';
const fs = require('fs');

function researchContext(evidence, section) {
  const sources = (evidence || {}).sources || {};
  const claims = (evidence || {}).claims || {};
  const ids = Object.keys(claims).sort().filter((id) => (claims[id] || {}).section === section);
  const out = [`Grounded evidence for ${section}:`];
  if (!ids.length) { out.push('  (none)'); return out.join('\n'); }
  for (const id of ids) {
    const c = claims[id] || {};
    const src = sources[c.source] || {};
    out.push(`  - ${id}: ${c.text || ''}`);
    out.push(`    source ${c.source || '(none)'} ${src.url || ''}`);
    out.push(`    » ${c.excerpt || ''}`);
  }
  return out.join('\n');
}

if (require.main === module) {
  const [evPath, section] = process.argv.slice(2);
  if (!evPath || !section) { console.error('usage: research-context.js <evidence.json> <section>'); process.exit(2); }
  console.log(researchContext(JSON.parse(fs.readFileSync(evPath, 'utf8')), section));
}

module.exports = { researchContext };
