#!/usr/bin/env node
/**
 * stamp-evidence.js — record HONEST source hashes into an evidence map.
 *
 * For each source id in evidence.sources, if <sourcesDir>/<id>.txt exists, set its `sha256` to the
 * sha256 of the STORED file bytes. This is a ONE-TIME, at-store-time step: the recorded sha is what
 * later gives `ground-check` its teeth — it re-derives the sha and flags STALE if the source was
 * edited after stamping. Stamp records; ground-check verifies. Prints the stamped evidence JSON.
 * node ≡ python produce the same map. Imports nothing from core.
 *
 * Usage: node stamp-evidence.js <evidence.json> <sourcesDir>
 */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function stampEvidence(evidence, sourcesDir) {
  const ev = evidence || {};
  const sources = ev.sources || {};
  for (const id of Object.keys(sources)) {
    const file = path.join(sourcesDir, id + '.txt');
    if (fs.existsSync(file)) {
      sources[id].sha256 = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
    }
  }
  return ev;
}

if (require.main === module) {
  const [evPath, srcDir] = process.argv.slice(2);
  if (!evPath || !srcDir) { console.error('usage: stamp-evidence.js <evidence.json> <sourcesDir>'); process.exit(2); }
  const evidence = JSON.parse(fs.readFileSync(evPath, 'utf8'));
  console.log(JSON.stringify(stampEvidence(evidence, srcDir), null, 2));
}

module.exports = { stampEvidence };
