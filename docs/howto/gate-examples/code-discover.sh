#!/usr/bin/env bash
# Proof: the code adapter's DISCOVERY mode computes transitive reachability over a codemap
# ({edges:[[A,B]]} = A depends on B) in three directions:
#   dependents   = reverse reachability (who transitively depends on the entry) = CHANGE IMPACT
#   dependencies = forward reachability (what the entry transitively needs)
#   both         = the union
# The entry is always included; cycles terminate; unrelated components are excluded; and the emitted
# `edges` are the induced subgraph among the affected set. Expected sets are enumerated LITERALLY here
# (an oracle independent of the implementation). Prints CODE-DISCOVER-OK. Fails before the provider exists.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
DISC="$ROOT/plugin/adapters/code/codegraph-discover.js"
FX="$ROOT/plugin/adapters/code/fixtures/discover-codemap.json"

# assert_run <direction> <entry> <expected-affected csv> <expected-edges "a|b,c|d">
assert_run() {
  local dir="$1" entry="$2" expA="$3" expE="$4"
  local out; out="$(node "$DISC" "$FX" "$entry" "--$dir")"
  node -e '
    const out=JSON.parse(process.argv[1]);
    const dir=process.argv[2], entry=process.argv[3];
    const expA=process.argv[4].split(",").filter(Boolean).sort();
    const expE=process.argv[5].split(",").filter(Boolean).sort();
    const gotA=(out.affected||[]).slice().sort();
    const gotE=(out.edges||[]).map(e=>e[0]+"|"+e[1]).sort();
    const eq=(x,y)=>x.length===y.length&&x.every((v,i)=>v===y[i]);
    if(!(out.affected||[]).includes(entry)){console.error(`FAIL[${dir} ${entry}]: entry not in affected`);process.exit(1);}
    if(!eq(gotA,expA)){console.error(`FAIL[${dir} ${entry}]: affected ${JSON.stringify(gotA)} != ${JSON.stringify(expA)}`);process.exit(1);}
    if(!eq(gotE,expE)){console.error(`FAIL[${dir} ${entry}]: edges ${JSON.stringify(gotE)} != ${JSON.stringify(expE)}`);process.exit(1);}
  ' "$out" "$dir" "$entry" "$expA" "$expE"
}

# From the fixture (A depends on B): main->service->repo->db, api->service, service->auth,
# util->helper, and a<->b (cycle).
# dependents of repo = who transitively depends on repo (change impact): service, main, api (+repo).
assert_run dependents   repo "api,main,repo,service" "api|service,main|service,service|repo"
# dependencies of repo = what repo needs: db (+repo). NOT main/api/service/auth.
assert_run dependencies repo "db,repo" "repo|db"
# both = union.
assert_run both         repo "api,db,main,repo,service" "api|service,main|service,repo|db,service|repo"
# cycle: dependents of a terminates and yields {a,b} (b->a; a via the cycle/entry).
assert_run dependents   a "a,b" "a|b,b|a"

echo "CODE-DISCOVER-OK"
