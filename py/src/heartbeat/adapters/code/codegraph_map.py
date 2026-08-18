#!/usr/bin/env python3
"""codegraph_map — CodeGraph provider (Python port; node ≡ python with codegraph-map.js).

Rows {nodes, edges} -> {edges:[[qnFrom, qnTo]]}, keeping only dependency-bearing edge types. The
live database read uses the stdlib `sqlite3` module (harness-first; no shell-out). Node-free.

Usage: python3 -m heartbeat.adapters.code.codegraph_map <rows.json>  |  <db-path> --db
"""
import json
import sys

DEP_TYPES = {"calls", "imports", "inheritance"}


def map_codegraph(rows):
    id2qn = {}
    for n in (rows.get("nodes") or []):
        id2qn[n["id"]] = n["qualified_name"]
    edges = []
    for e in (rows.get("edges") or []):
        if e["type"] not in DEP_TYPES:                       # drop non-dependency edges
            continue
        frm, to = id2qn.get(e["from_id"]), id2qn.get(e["to_id"])
        if frm is None or to is None:                        # skip edges to unknown nodes
            continue
        edges.append([frm, to])
    return {"edges": edges}


def read_codegraph_db(db_path):
    """HARNESS-FIRST: read a CodeGraph .codegraph/codegraph.db via the stdlib sqlite3 module (no
    shell-out — node uses the sqlite3 CLI; here it is native). NOT wired into the suite."""
    import sqlite3
    con = sqlite3.connect(db_path)
    try:
        nodes = [{"id": r[0], "qualified_name": r[1], "file": r[2], "kind": r[3]}
                 for r in con.execute("SELECT id, qualified_name, file, kind FROM nodes")]
        edges = [{"from_id": r[0], "to_id": r[1], "type": r[2]}
                 for r in con.execute("SELECT from_id, to_id, type FROM edges")]
    finally:
        con.close()
    return {"nodes": nodes, "edges": edges}


def _main(argv):
    if not argv:
        sys.stderr.write("usage: codegraph_map <rows.json>  |  codegraph_map <db> --db\n")
        return 2
    rows = read_codegraph_db(argv[0]) if (len(argv) >= 2 and argv[1] == "--db") \
        else json.load(open(argv[0]))
    print(json.dumps(map_codegraph(rows), separators=(",", ":"), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
