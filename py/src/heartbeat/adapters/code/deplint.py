#!/usr/bin/env python3
"""deplint — code dep-lint engine (Python port; node ≡ python with plugin/adapters/code/deplint.js).

Validates a HeartBeat dag.json's `requires` edges against a codemap (edges: A depends on B; tasks:
task -> symbols). Reports MISSING / REDUNDANT / COLLISION using the requires transitive closure.
Advisory by default; --strict exits 1 iff missing>0 or collision>0. Output is BYTE-IDENTICAL to the
node engine. Stdlib-only; imports nothing from core; node-free (part of the adapters parity surface).

Usage: python3 -m heartbeat.adapters.code.deplint <dag.json> <codemap.json> [--strict]
"""
import json
import sys


def _load_reqs(dag):
    reqs = {}
    for p in dag.get("phases") or []:
        for t in p.get("tasks") or []:
            reqs[t["id"]] = t.get("requires") or []
    return reqs


def _closure(reqs):
    after = {}
    for a in reqs:
        seen, stack = set(), list(reqs.get(a) or [])
        while stack:
            b = stack.pop()
            if b in seen:
                continue
            seen.add(b)
            for c in (reqs.get(b) or []):
                stack.append(c)
        after[a] = seen
    return after


def deplint(dag, codemap):
    reqs = _load_reqs(dag)
    after = _closure(reqs)
    task_syms = codemap.get("tasks") or {}
    edge_set = {f"{e[0]} {e[1]}" for e in (codemap.get("edges") or [])}

    def depends_between(a, b):
        for x in (task_syms.get(a) or []):
            for y in (task_syms.get(b) or []):
                if f"{x} {y}" in edge_set:
                    return [x, y]
        return None

    tasks = list(reqs)
    missing, redundant, collision = [], [], []
    for a in tasks:
        for b in tasks:
            if a == b or b in after[a]:
                continue
            via = depends_between(a, b)
            if via:
                missing.append({"from": a, "to": b, "via": via})
    for a in tasks:
        for b in (reqs.get(a) or []):
            if not depends_between(a, b) and not depends_between(b, a):
                redundant.append({"from": a, "to": b})
    for i in range(len(tasks)):
        for j in range(i + 1, len(tasks)):
            a, b = tasks[i], tasks[j]
            if b in after[a] or a in after[b]:
                continue
            shared = [s for s in (task_syms.get(a) or []) if s in (task_syms.get(b) or [])]
            if shared:
                collision.append({"a": a, "b": b, "shared": shared})
    return {"missing": missing, "redundant": redundant, "collision": collision}


def format_report(r):
    """Render the findings as the report string (shared with deplint_accept — never drift)."""
    lines = ["HB-CODE-DEPLINT: missing=%d redundant=%d collision=%d"
             % (len(r["missing"]), len(r["redundant"]), len(r["collision"]))]
    for m in r["missing"]:
        lines.append("MISSING: %s should require %s  (%s -> %s)" % (m["from"], m["to"], m["via"][0], m["via"][1]))
    for m in r["redundant"]:
        lines.append("REDUNDANT: %s requires %s but no direct code dependency between their symbols"
                     % (m["from"], m["to"]))
    for c in r["collision"]:
        lines.append("COLLISION: %s and %s share %s (unordered — isolate or add a requires edge)"
                     % (c["a"], c["b"], ",".join(c["shared"])))
    return "\n".join(lines)


def _main(argv):
    strict = "--strict" in argv
    pos = [a for a in argv if not a.startswith("--")]
    if len(pos) < 2:
        sys.stderr.write("usage: deplint <dag.json> <codemap.json> [--strict]\n")
        return 2
    with open(pos[0]) as f:
        dag = json.load(f)
    with open(pos[1]) as f:
        codemap = json.load(f)
    r = deplint(dag, codemap)
    print(format_report(r))
    return 1 if strict and (r["missing"] or r["collision"]) else 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
