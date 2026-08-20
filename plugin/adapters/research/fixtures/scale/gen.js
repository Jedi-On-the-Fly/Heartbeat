#!/usr/bin/env node
/**
 * gen.js — deterministic large-corpus generator for the research adapter's scale/parity proof.
 *
 * Writes <outDir>/evidence.json + <outDir>/sources/*.txt: 60 sources, 200 claims, 4 sections, unicode
 * (°C » é —), a synthetic line-wrap injected into every stored excerpt (so whitespace normalization is
 * exercised), and multi-claim-per-source. Ids are ZERO-PADDED (c_000.., s_00..) so node's Array.sort
 * and python's sorted() order them identically. Every 5th claim (i%5==0) is fabricated (its excerpt is
 * a NOTINSOURCE-<i> token never stored) → 40 fabricated / 160 grounded. No time, no randomness — the
 * bytes are identical every run. Sources are shaless (ground via excerpt; no STALE).
 *
 * Usage: node gen.js <outDir>
 */
'use strict';
const fs = require('fs');
const path = require('path');

const NS = 60, NC = 200;
const SECTIONS = ['background', 'method', 'results', 'discussion'];
const pad3 = (n) => String(n).padStart(3, '0');
const pad2 = (n) => String(n).padStart(2, '0');

function generate(outDir) {
  const srcDir = path.join(outDir, 'sources');
  fs.mkdirSync(srcDir, { recursive: true });

  const sources = {};
  const perSource = {};
  for (let k = 0; k < NS; k++) { const sid = 's_' + pad2(k); sources[sid] = { url: 'https://ex.org/' + sid, title: 'Source ' + pad2(k) }; perSource[sid] = []; }

  const claims = {};
  for (let i = 0; i < NC; i++) {
    const id = 'c_' + pad3(i);
    const sid = 's_' + pad2(i % NS);
    const section = SECTIONS[i % 4];
    let excerpt;
    if (i % 5 === 0) {
      excerpt = 'NOTINSOURCE-' + pad3(i) + ' fabricated quote ' + i;          // never stored → FABRICATED-QUOTE
    } else {
      excerpt = 'finding ' + pad3(i) + ' — measured ' + i + '°C effect » in cohort é';
      perSource[sid].push(excerpt.replace(' ', '\n'));                        // store with a line-wrap
    }
    claims[id] = { text: 'Claim ' + pad3(i) + ' in ' + section, source: sid, excerpt: excerpt, section: section };
  }

  for (let k = 0; k < NS; k++) {
    const sid = 's_' + pad2(k);
    const body = 'Source ' + pad2(k) + ' — notes at 20°C, cost 5 » é —\n' + perSource[sid].join('\n') + '\n';
    fs.writeFileSync(path.join(srcDir, sid + '.txt'), body);
  }
  fs.writeFileSync(path.join(outDir, 'evidence.json'), JSON.stringify({ sources, claims }, null, 2));
}

if (require.main === module) {
  const outDir = process.argv[2];
  if (!outDir) { console.error('usage: gen.js <outDir>'); process.exit(2); }
  generate(outDir);
}

module.exports = { generate };
