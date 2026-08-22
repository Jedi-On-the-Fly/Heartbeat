#!/usr/bin/env bash
# Proof (C1): hb-lint extractPaths must not treat shell constructs (sed 's/a/b/') or ABSOLUTE tool paths
# (/usr/bin/node) as produced artifacts — otherwise a completed phase whose gate uses them false-trips
# "no longer reproducible" → permanent gate_rot. A genuine relative artifact must still be detected.
# Prints ROT-LINT-PRECISION-OK. Fails today. Deterministic.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
node -e '
const {extractPaths}=require(process.argv[1]);
const has=(cmd,p)=>[...extractPaths(cmd)].includes(p);
const bad=[];
if ([...extractPaths("sed -i \"s/a/b/g\" f.txt")].some(p=>/^s\//.test(p)||p.includes("s/a/b"))) bad.push("sed pattern treated as a path");
if ([...extractPaths("/usr/bin/node --version")].some(p=>p.startsWith("/usr"))) bad.push("absolute path treated as a produced artifact");
if (!has("node tests/e2e/x.spec.js","tests/e2e/x.spec.js")) bad.push("genuine relative artifact NOT detected");
if (!has("docker build -f tests/frameworks/Dockerfile .","tests/frameworks/Dockerfile")) bad.push("EXTENSIONLESS artifact not tracked (over-narrowed)");
if (bad.length){console.error("FAIL: "+bad.join("; "));process.exit(1)}
' "$ROOT/plugin/templates/hb-lint.js" || exit 1
echo "ROT-LINT-PRECISION-OK"
