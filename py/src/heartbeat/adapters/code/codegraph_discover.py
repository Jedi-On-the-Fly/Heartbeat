#!/usr/bin/env python3
"""codegraph_discover — discovery mode for the code adapter (Python twin; node ≡ python, T98).

Given a codemap ({edges:[[A,B]]}, A depends on B) and entry-point symbols, compute the transitively
reachable AFFECTED set in a direction, plus the induced subgraph — to scope a change before authoring
the DAG. Advisory (static edges only; never rewrites the DAG).

  dependents   = reverse reachability — who transitively depends on the entry = change impact
  dependencies = forward reachability — what the entry transitively needs
  both         = the union

Byte-identical output to plugin/adapters/code/codegraph-discover.js (deterministic sorted JSON).

Usage: python3 -m heartbeat.adapters.code.codegraph_discover <codemap.json> <e1,e2,...> [--dependents|--dependencies|--both]
"""
import json
import sys


def discover(codemap, entries, direction="both"):
    fwd, rev = {}, {}                                   # fwd: A->{B}, rev: B->{A}  (A depends on B)
    for e in (codemap.get("edges") or []):
        a, b = e[0], e[1]
        fwd.setdefault(a, set()).add(b)
        rev.setdefault(b, set()).add(a)

    def reach(adj, seeds):                              # transitive closure from seeds over adj
        seen = set(seeds)
        stack = list(seeds)
        while stack:
            n = stack.pop()
            for m in adj.get(n, ()):
                if m not in seen:
                    seen.add(m)
                    stack.append(m)
        return seen

    seeds = list(dict.fromkeys(entries))                # de-dupe, preserve order
    if direction == "dependents":
        affected = reach(rev, seeds)
    elif direction == "dependencies":
        affected = reach(fwd, seeds)
    else:                                               # both
        affected = reach(rev, seeds) | reach(fwd, seeds)

    edges = sorted([e[0], e[1]] for e in (codemap.get("edges") or [])
                   if e[0] in affected and e[1] in affected)
    return {
        "entry": sorted(seeds),
        "direction": direction,
        "affected": sorted(affected),
        "edges": edges,
    }


def _main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: codegraph_discover <codemap.json> <e1,e2,...> [--dependents|--dependencies|--both]\n")
        return 2
    map_path, entries_arg = argv[0], argv[1]
    flag = argv[2] if len(argv) >= 3 else "--both"
    direction = flag[2:] if flag.startswith("--") else flag
    if direction not in ("dependents", "dependencies", "both"):
        sys.stderr.write("bad direction: %s\n" % flag)
        return 2
    with open(map_path) as f:
        codemap = json.load(f)
    entries = [e for e in entries_arg.split(",") if e]
    print(json.dumps(discover(codemap, entries, direction), separators=(",", ":"), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
