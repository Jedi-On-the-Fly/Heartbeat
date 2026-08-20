#!/usr/bin/env python3
"""ground_check — the research adapter's grounding verifier (Python twin; node ≡ python).

Given an evidence map ({sources:{id:{url,sha256,fetched}}, claims:{id:{text,source,excerpt,section}}})
and a directory of stored source texts, verify OFFLINE that every claim is GROUNDED: the cited source is
declared, its stored file exists and matches the recorded sha256 (STALE detection), and a
whitespace-normalized excerpt is a substring of the text (FABRICATED-QUOTE detection). The deterministic
GATE half of the research evidence lifecycle — proves the quote is REAL, not that it is TRUE. Byte-identical
output to plugin/adapters/research/ground-check.js.

Usage: python3 -m heartbeat.adapters.research.ground_check <evidence.json> <sourcesDir> [--strict]
"""
import hashlib
import json
import os
import re
import sys


def _norm(s):
    return re.sub(r"\s+", " ", s or "").strip()


def ground_check(evidence, sources_dir):
    sources = (evidence or {}).get("sources") or {}
    claims = (evidence or {}).get("claims") or {}
    issues = []
    grounded = 0
    for cid in sorted(claims.keys()):
        c = claims[cid] or {}
        sid = c.get("source")
        if not sid or sid not in sources:
            issues.append(f"UNGROUNDED: {cid} — source {sid or '(none)'} not in evidence.sources")
            continue
        f = os.path.join(sources_dir, sid + ".txt")
        if not os.path.exists(f):
            issues.append(f"MISSING-SOURCE: {cid} — stored source {sid}.txt not found")
            continue
        with open(f, "rb") as fh:
            data = fh.read()
        recorded = sources[sid].get("sha256")
        # sha BEFORE excerpt: an edited source must surface as STALE even if it still contains the excerpt.
        if recorded and hashlib.sha256(data).hexdigest() != recorded:
            issues.append(f"STALE: {cid} — source {sid} changed since fetch (sha mismatch)")
            continue
        excerpt = _norm(c.get("excerpt"))
        if not excerpt:
            issues.append(f"UNGROUNDED: {cid} — no excerpt")
            continue
        if excerpt not in _norm(data.decode("utf-8")):
            issues.append(f"FABRICATED-QUOTE: {cid} — excerpt not found in source {sid}")
            continue
        grounded += 1
    return {"grounded": grounded, "issues": issues}


def format_report(r):
    return "\n".join([f"HB-GROUND: grounded={r['grounded']} issues={len(r['issues'])}"] + r["issues"])


def _main(argv):
    strict = "--strict" in argv
    pos = [a for a in argv if not a.startswith("--")]
    if len(pos) < 2:
        sys.stderr.write("usage: ground_check <evidence.json> <sourcesDir> [--strict]\n")
        return 2
    with open(pos[0]) as fh:
        evidence = json.load(fh)
    r = ground_check(evidence, pos[1])
    print(format_report(r))
    return 1 if strict and r["issues"] else 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
