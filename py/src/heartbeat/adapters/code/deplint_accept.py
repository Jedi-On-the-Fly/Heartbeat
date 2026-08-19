#!/usr/bin/env python3
"""deplint_accept — plan-acceptance wrapper for code dep-lint (Python twin; node ≡ python).

Auto-surfaces dep-lint at plan acceptance: resolves a codemap from the project, then delegates to the
real deplint (same report). Resolution: --codemap > <dir>/codemap.json > <dir>/.codegraph/codegraph.db
(provisional: CodeGraph edges + fuzzy task→symbol, harness-first) > SKIP. Advisory by default;
--strict exits 1 iff missing or collision. Byte-identical output to deplint-accept.js.

Usage: python3 -m heartbeat.adapters.code.deplint_accept --dir <proj> --dag <dag.json> [--codemap <f>] [--strict]
"""
import json
import os
import sys

from heartbeat.adapters.code.deplint import deplint, format_report


def _arg(argv, name):
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else None


def resolve_codemap(dir_, dag, explicit=None):
    """Return a codemap dict + provisional note, or None to signal SKIP."""
    if explicit:
        with open(explicit) as f:
            return {"codemap": json.load(f), "note": None}
    if dir_:
        cm = os.path.join(dir_, "codemap.json")
        if os.path.exists(cm):
            with open(cm) as f:
                return {"codemap": json.load(f), "note": None}
        db = os.path.join(dir_, ".codegraph", "codegraph.db")
        if os.path.exists(db):
            from heartbeat.adapters.code.codegraph_map import read_codegraph_db, map_codegraph, resolve_task_symbols
            rows = read_codegraph_db(db)
            codemap = {"edges": map_codegraph(rows)["edges"], "tasks": resolve_task_symbols(dag, rows["nodes"])}
            return {"codemap": codemap, "note": "NOTE: provisional codemap (CodeGraph edges + fuzzy task→symbol) — confirm"}
    return None


def accept(dir_, dag, explicit=None, strict=False):
    """(text, code) — no printing; the report/skip string is byte-identical to the node wrapper."""
    resolved = resolve_codemap(dir_, dag, explicit)
    if resolved is None:
        return ("DEPLINT-ACCEPT-SKIP: no codemap or CodeGraph index in %s (deplint skipped)" % dir_, 0)
    r = deplint(dag, resolved["codemap"])
    report = format_report(r)
    text = "%s\n%s" % (resolved["note"], report) if resolved["note"] else report
    code = 1 if strict and (r["missing"] or r["collision"]) else 0
    return (text, code)


def _main(argv):
    dir_ = _arg(argv, "--dir")
    dag_path = _arg(argv, "--dag")
    explicit = _arg(argv, "--codemap")
    strict = "--strict" in argv
    if not dag_path:
        sys.stderr.write("usage: deplint_accept --dir <proj> --dag <dag.json> [--codemap <f>] [--strict]\n")
        return 2
    with open(dag_path) as f:
        dag = json.load(f)
    text, code = accept(dir_, dag, explicit, strict)
    print(text)
    return code


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
