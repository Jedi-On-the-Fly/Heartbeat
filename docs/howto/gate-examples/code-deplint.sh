#!/usr/bin/env bash
# Proof: the heartbeat-code dep-lint engine validates a dag.json's `requires` edges against a
# codemap (symbol->symbol edges + task->symbols). It must:
#   (1) detect a likely-MISSING edge and name the right tasks in the suggestion
#   (2) detect a REDUNDANT (over-constraining) edge
#   (3) detect a parallel-COLLISION (unordered tasks sharing a symbol)
#   (4) report zero findings on a clean dag
#   (5) NOT flag a dependency that is already satisfied via the requires TRANSITIVE CLOSURE
#   (6) be advisory by default; under --strict go red on missing/collision, stay green on
#       clean/redundant/transitive
#   (7) stay OUT of the .hb scaffold (a freshly bootstrapped project has no adapter files)
# Prints CODE-DEPLINT-OK only when all hold. Fails before deplint.js exists (spec-first).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
DL="$ROOT/plugin/adapters/code/deplint.js"
FX="$ROOT/plugin/adapters/code/fixtures"
run(){ node "$DL" "$FX/$1.dag.json" "$FX/$1.codemap.json" ${2:-}; }   # $2 = optional --strict

# (1) missing: >=1 missing AND the suggestion has the right DIRECTION (TA should require TB)
mo="$(run missing)"
echo "$mo" | grep -qE 'missing=[1-9]'                 || { echo "FAIL: missing not detected"; exit 1; }
echo "$mo" | grep -q 'MISSING: TA should require TB'  || { echo "FAIL: missing suggestion wrong/backwards (want 'TA should require TB')"; exit 1; }

# (2) redundant  (3) collision
run redundant | grep -qE 'redundant=[1-9]'            || { echo "FAIL: redundant not detected"; exit 1; }
run collision | grep -qE 'collision=[1-9]'            || { echo "FAIL: collision not detected"; exit 1; }

# (4) clean: zero findings
run clean | grep -q 'missing=0 redundant=0 collision=0' || { echo "FAIL: clean dag reported findings"; exit 1; }

# (5) transitive: a transitively-satisfied dependency is NOT flagged missing
run transitive | grep -qE 'missing=0'                 || { echo "FAIL: transitive dep wrongly flagged missing"; exit 1; }

# (6) strict semantics
run missing   --strict && { echo "FAIL: --strict did not fail on missing";   exit 1; } || true
run collision --strict && { echo "FAIL: --strict did not fail on collision"; exit 1; } || true
run clean     --strict || { echo "FAIL: --strict wrongly failed on clean";     exit 1; }
run redundant --strict || { echo "FAIL: --strict wrongly failed on redundant"; exit 1; }
run transitive --strict || { echo "FAIL: --strict wrongly failed on transitive"; exit 1; }

# (7) boundary: a fresh .hb is really produced AND contains no adapter files (behavior, not
# existence — a failed bootstrap must not pass this check by producing nothing to grep)
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
HB_NO_GIT=1 bash "$ROOT/plugin/bootstrap.sh" "$tmp/p" >/dev/null 2>&1 </dev/null || { echo "FAIL: bootstrap errored"; exit 1; }
[ -f "$tmp/p/.hb/hb.js" ]                              || { echo "FAIL: bootstrap produced no .hb scaffold"; exit 1; }
if grep -rq 'adapters/code' "$tmp/p/.hb"; then echo "FAIL: adapter leaked into the .hb scaffold"; exit 1; fi

echo "CODE-DEPLINT-OK"
