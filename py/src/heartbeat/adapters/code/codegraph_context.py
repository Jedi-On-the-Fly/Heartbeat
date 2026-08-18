#!/usr/bin/env python3
"""codegraph_context — Seam-2 provider (Python port; BYTE-IDENTICAL to codegraph-context.js).

Render a task's direct-neighbor subgraph as context text for Stage B. Node-free.
Usage: python3 -m heartbeat.adapters.code.codegraph_context <codemap.json> <TASKID>
"""
import json
import sys


def context_for(codemap, task_id):
    edges = codemap.get("edges") or []
    touched = (codemap.get("tasks") or {}).get(task_id) or []
    out = ["Code context for task %s — the symbols it touches and their direct neighbors:" % task_id]
    if not touched:
        out.append("  (no symbols mapped to this task)")
        return "\n".join(out)
    for sym in touched:
        deps = list(dict.fromkeys(e[1] for e in edges if e[0] == sym))    # sym depends on these
        users = list(dict.fromkeys(e[0] for e in edges if e[1] == sym))   # these use sym
        out.append("  %s" % sym)
        if deps:
            out.append("    depends on: %s" % ", ".join(deps))
        if users:
            out.append("    used by:    %s" % ", ".join(users))
    return "\n".join(out)


def _main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: codegraph_context <codemap.json> <TASKID>\n")
        return 2
    with open(argv[0]) as f:
        codemap = json.load(f)
    print(context_for(codemap, argv[1]))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
