#!/usr/bin/env python3
"""codegraph_coverage — graph coverage / blind-spot report (Python twin; node ≡ python, T106).

For each task in the DAG, count the symbols the codemap resolves for it, and explicitly LIST the
GRAPH-BLIND tasks (zero resolved symbols — a not-yet-existing file or a dynamic/framework binding the
static graph can't model → read manually). Advisory. Byte-identical output to codegraph-coverage.js.

Usage: python3 -m heartbeat.adapters.code.codegraph_coverage <codemap.json> <dag.json>
"""
import json
import sys


def coverage(codemap, dag):
    task_syms = (codemap or {}).get("tasks") or {}
    ids = []
    for p in ((dag or {}).get("phases") or []):
        for t in (p.get("tasks") or []):
            ids.append(t["id"])
    ids.sort()
    lines = ["Graph coverage:"]
    blind = []
    for tid in ids:
        n = len(task_syms.get(tid) or [])
        lines.append(f"  {tid}: {n} symbol{'' if n == 1 else 's'}")
        if n == 0:
            blind.append(tid)
    blind.sort()
    lines.append(f"GRAPH-BLIND (read manually): {', '.join(blind)}" if blind else "GRAPH-BLIND: none")
    return "\n".join(lines)


def _main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: codegraph_coverage <codemap.json> <dag.json>\n")
        return 2
    with open(argv[0]) as f:
        codemap = json.load(f)
    with open(argv[1]) as f:
        dag = json.load(f)
    print(coverage(codemap, dag))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
