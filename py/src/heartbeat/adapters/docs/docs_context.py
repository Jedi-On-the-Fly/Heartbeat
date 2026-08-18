#!/usr/bin/env python3
"""docs_context — docs Seam-2 provider (Python port; BYTE-IDENTICAL to docs-context.js).

Render the TEXT of the sections a task directly cites — the "read these before writing" block.
Node-free.

Usage: python3 -m heartbeat.adapters.docs.docs_context <corpusDir> <codemap.json> <taskId>
"""
import json
import os
import sys

# Exactly the char set JS String.prototype.trim removes (WhiteSpace + LineTerminator) — so `js_trim`
# matches node's `.trim()` BYTE-for-byte, incl. a UTF-8 BOM (U+FEFF, which JS strips but Python
# str.strip() keeps) and excluding NEL (U+0085, which Python strips but JS keeps).
_JS_WS = ("\t\x0b\x0c \xa0﻿\n\r "
          "           "
          "  　  ")


def js_trim(s):
    return s.strip(_JS_WS)


def cited_context(corpus_dir, codemap, task_id):
    edges = codemap.get("edges") or []
    sections = (codemap.get("tasks") or {}).get(task_id) or []
    cited = []
    for s in sections:
        for e in edges:
            if e[0] == s and e[1] not in cited:
                cited.append(e[1])
    out = ["Context for task %s — read the sections it directly cites before writing:" % task_id]
    if not cited:
        out.append("  (this task cites nothing)")
        return "\n".join(out)
    for c in cited:
        try:
            with open(os.path.join(corpus_dir, c + ".md"), encoding="utf-8") as fh:
                text = js_trim(fh.read())
        except OSError:
            text = "(section text unavailable)"
        out.append("\n--- %s ---\n%s" % (c, text))
    return "\n".join(out)


def _main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: docs_context <corpusDir> <codemap.json> <taskId>\n")
        return 2
    with open(argv[1]) as f:
        codemap = json.load(f)
    print(cited_context(argv[0], codemap, argv[2]))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
