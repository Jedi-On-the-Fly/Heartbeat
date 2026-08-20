#!/usr/bin/env bash
# Proof (engine reuse): the domain-NEUTRAL discover engine works on the docs CITATION codemap —
# reverse reachability = which sections transitively BUILD ON (cite) a given one = change impact for
# docs. No new code: docs reuses plugin/adapters/code/codegraph-discover.js over the citation graph.
# Prints DOCS-DISCOVER-OK.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
CM="$ROOT/plugin/adapters/docs/fixtures/docs.codemap.json"

# edges mean 'citer depends on cited'. dependents of `method` = who transitively cites method.
out="$(node "$ROOT/plugin/adapters/code/codegraph-discover.js" "$CM" method --dependents)"
node -e '
  const aff=JSON.parse(process.argv[1]).affected;
  for (const s of ["method","results","intro"]) if(!aff.includes(s)){console.error("expected "+s+" to cite method (transitively)",aff);process.exit(1);}
  if(aff.includes("background")){console.error("background is cited BY method, not a citer — must not be a dependent",aff);process.exit(1);}
' "$out" || { echo "FAIL: reverse-citation change-impact wrong"; echo "$out"; exit 1; }

echo "DOCS-DISCOVER-OK"
