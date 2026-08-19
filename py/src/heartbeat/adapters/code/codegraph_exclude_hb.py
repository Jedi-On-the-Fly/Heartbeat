#!/usr/bin/env python3
"""codegraph_exclude_hb — keep CodeGraph off HeartBeat's `.hb/` scaffold (Python twin; node ≡ python).

Idempotently ensures a project's root codegraph.json excludes `.hb/` (CodeGraph reads its `exclude`
array), preserving any existing config. Run before `codegraph init`. Byte-identical output to
plugin/adapters/code/codegraph-exclude-hb.js. Real indexing effect proved harness-first by
tests/real-codegraph-exclude-hb.sh (skips without CodeGraph).

Usage: python3 -m heartbeat.adapters.code.codegraph_exclude_hb [root]   (default root '.')
"""
import json
import os
import sys


def ensure_hb_excluded(root="."):
    p = os.path.join(root or ".", "codegraph.json")
    cfg = {}
    if os.path.exists(p):
        try:
            with open(p) as f:
                cfg = json.load(f) or {}
        except Exception:
            cfg = {}
    ex = cfg.get("exclude")
    if not isinstance(ex, list):
        ex = []
    if ".hb/" not in ex:
        ex.append(".hb/")
    cfg["exclude"] = ex
    with open(p, "w") as f:
        f.write(json.dumps(cfg, indent=2) + "\n")
    return cfg


if __name__ == "__main__":
    ensure_hb_excluded(sys.argv[1] if len(sys.argv) > 1 else ".")
