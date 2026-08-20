#!/usr/bin/env python3
"""research_context — research Seam-2 provider (Python port; BYTE-IDENTICAL to research-context.js).

Render a section's GROUNDED claims (id + text + cited source url + verbatim excerpt) as the context
block fed to the writer. Only that section's claims. Grounding is verified upstream by ground-check —
this only renders. Node-free.

Usage: python3 -m heartbeat.adapters.research.research_context <evidence.json> <section>
"""
import json
import sys


def research_context(evidence, section):
    sources = (evidence or {}).get("sources") or {}
    claims = (evidence or {}).get("claims") or {}
    ids = [i for i in sorted(claims.keys()) if (claims[i] or {}).get("section") == section]
    out = ["Grounded evidence for %s:" % section]
    if not ids:
        out.append("  (none)")
        return "\n".join(out)
    for i in ids:
        c = claims[i] or {}
        src = sources.get(c.get("source")) or {}
        out.append("  - %s: %s" % (i, c.get("text") or ""))
        out.append("    source %s %s" % (c.get("source") or "(none)", src.get("url") or ""))
        out.append("    » %s" % (c.get("excerpt") or ""))
    return "\n".join(out)


def _main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: research_context <evidence.json> <section>\n")
        return 2
    with open(argv[0], encoding="utf-8") as f:
        evidence = json.load(f)
    print(research_context(evidence, argv[1]))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
