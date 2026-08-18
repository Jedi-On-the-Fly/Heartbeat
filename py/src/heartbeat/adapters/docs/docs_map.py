#!/usr/bin/env python3
"""docs_map — docs/research provider (Python port; node ≡ python with docs-map.js).

Turns a markdown corpus's citation graph into the codemap: edges [citer, cited] from relative .md
links (external/anchor/outside-corpus/self excluded) + one authoring task per section. Inline links
only (same limitation as node). Node-free.

Usage: python3 -m heartbeat.adapters.docs.docs_map <corpusDir>
"""
import json
import os
import re
import sys

from .docs_context import js_trim   # exact-JS-.trim() so link-target trimming matches node byte-for-byte

_LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
_EXTERNAL = re.compile(r"(?i)^(https?:|mailto:|#)")


def citation_map(corpus_dir):
    files = [f for f in os.listdir(corpus_dir) if f.endswith(".md")]
    ids = {f[:-3] for f in files}
    edges, seen = [], set()
    for f in files:
        cid = f[:-3]
        with open(os.path.join(corpus_dir, f), encoding="utf-8") as fh:
            text = fh.read()
        for m in _LINK.finditer(text):
            target = js_trim(m.group(1))
            if _EXTERNAL.match(target):                      # external / anchor
                continue
            target = target.split("#")[0].split("?")[0]      # strip fragment/query
            if not target.endswith(".md"):
                continue
            tid = os.path.basename(target)[:-3]
            if tid not in ids or tid == cid:                 # outside corpus, or self-link
                continue
            key = cid + "|" + tid
            if key not in seen:
                seen.add(key)
                edges.append([cid, tid])
    tasks = {i: [i] for i in sorted(ids)}                    # one authoring task per section
    return {"edges": edges, "tasks": tasks}


def _main(argv):
    if not argv:
        sys.stderr.write("usage: docs_map <corpusDir>\n")
        return 2
    print(json.dumps(citation_map(argv[0]), separators=(",", ":"), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
