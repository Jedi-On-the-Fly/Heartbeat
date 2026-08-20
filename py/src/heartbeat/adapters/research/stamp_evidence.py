#!/usr/bin/env python3
"""stamp_evidence — record HONEST source hashes into an evidence map (Python port of stamp-evidence.js).

For each source id in evidence.sources, if <sourcesDir>/<id>.txt exists, set its `sha256` to the
sha256 of the stored file bytes. A one-time at-store-time step: the recorded sha is what later gives
`ground-check` its teeth (it re-derives and flags STALE on a later edit). node ≡ python (same map).
Node-free.

Usage: python3 -m heartbeat.adapters.research.stamp_evidence <evidence.json> <sourcesDir>
"""
import hashlib
import json
import os
import sys


def stamp_evidence(evidence, sources_dir):
    ev = evidence or {}
    sources = ev.get("sources") or {}
    for sid in sources:
        path = os.path.join(sources_dir, sid + ".txt")
        if os.path.exists(path):
            with open(path, "rb") as fh:
                sources[sid]["sha256"] = hashlib.sha256(fh.read()).hexdigest()
    return ev


def _main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: stamp_evidence <evidence.json> <sourcesDir>\n")
        return 2
    with open(argv[0], encoding="utf-8") as f:
        evidence = json.load(f)
    print(json.dumps(stamp_evidence(evidence, argv[1]), indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
