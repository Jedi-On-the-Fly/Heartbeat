#!/usr/bin/env python3
"""Seeded, deterministic generator of a HeartBeat case (dag.json + events.jsonl).

The parity fuzz oracle (tests/parity-fuzz.sh) uses this to explore the shared input space
with structurally-varied but WELL-FORMED cases instead of a handful of fixed fixtures. Two
implementations of one spec are each other's oracle, so any node<->python disagreement on a
generated case is a real bug.

Determinism is the whole point: output depends ONLY on the seed (a small local LCG; no
random, no time, no wall-clock ts), so the same seed always yields byte-identical output —
which is what makes the fuzzer a ratcheted, reproducible test. The input space is bounded to
WELL-FORMED DAGs (documented, not silently capped); malformed-input fuzzing is out of scope.

Usage:
  gen-parity-case.py <seed> <dir>   # write <dir>/.hb/dag.json + <dir>/.hb/events.jsonl
  gen-parity-case.py <seed> -       # print the same bundle to stdout (temp-dir-free)
"""
import json
import os
import sys


class Rng:
    """A tiny deterministic xorshift32. Seed-only; no global random state.

    An LCG's low bits are near-periodic, so `next() % n` (small n) barely varies — a real bug
    that made an earlier version emit only a handful of distinct cases. xorshift32 mixes all
    bits; we also scramble the seed into the state and draw small ints/booleans from the HIGH
    bits, so different seeds give well-distributed, non-correlated cases.
    """
    def __init__(self, seed):
        self.s = ((seed * 2654435761) + 2463534242) & 0xFFFFFFFF or 0x9E3779B9

    def next(self):
        x = self.s
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        self.s = x & 0xFFFFFFFF
        return self.s

    def rand(self, n):
        return (self.next() >> 13) % n if n > 0 else 0   # high bits: well-mixed

    def chance(self):
        return ((self.next() >> 16) & 1) == 0


def build_case(seed):
    """(seed) -> (dag, events). Pure and deterministic."""
    r = Rng(seed)
    n_phases = 1 + r.rand(4)                      # 1..4 phases
    phases, gates = [], {}
    for i in range(n_phases):
        gate = "G%d" % i
        n_tasks = 1 + r.rand(4)                   # 1..4 tasks/phase (<=8 by contract)
        tasks = []
        for j in range(n_tasks):
            tid = "P%dT%d" % (i, j)
            requires = ["P%dT%d" % (i, j - 1)] if j > 0 and r.chance() else []
            tasks.append({"id": tid, "requires": requires})
        phases.append({
            "id": "P%d" % i,
            "gate_entry": ("G%d" % (i - 1)) if i > 0 else None,
            "gate_exit": gate,
            "tasks": tasks,
        })
        g = {"criteria": [{"id": "c", "cmd": "true"}]}
        if r.chance():
            g["review"] = {"prompt": "refute P%d" % i}
            # plan-time constraints (CR0): absent, well-formed, or one of the malformed shapes
            # lint must reject identically in both runtimes (incl. the whitespace-set edge cases)
            k = r.rand(6)
            ok = {"id": "P1", "claim": "c", "subjects": ["s"], "violation": "v"}
            if k == 1:
                g["review"]["constraints"] = [ok, dict(ok, id="P2")]
            elif k == 2:
                g["review"]["constraints"] = [ok, ok]                          # duplicate id
            elif k == 3:
                g["review"]["constraints"] = [dict(ok, id="G1"), dict(ok, claim="\ufeff"), dict(ok, violation="\x85")]
            elif k == 4:
                g["review"]["constraints"] = [dict(ok, subjects=[]), None, "P3"]
            elif k == 5:
                g["review"]["constraints"] = {"id": "P1"}                   # not a list
        gates[gate] = g
    dag = {"phases": phases, "gates": gates}

    # A plausible event sequence: complete a prefix of phases (all tasks done, gate passed,
    # review passed when the gate is review-blocked), then vary the frontier with an in-flight
    # start and/or a failure. Every event is well-formed and matches real projection semantics.
    events = [{"event": "initialized"}]
    n_done = r.rand(n_phases + 1)                 # 0..n_phases fully-completed phases
    for i in range(n_done):
        ph = phases[i]
        for t in ph["tasks"]:
            events.append({"event": "task_done", "task": t["id"]})
        events.append({"event": "gate_passed", "gate": ph["gate_exit"]})
        if "review" in gates[ph["gate_exit"]]:
            events.append({"event": "review_passed", "gate": ph["gate_exit"]})
    if n_done < n_phases:                         # vary the frontier phase's STATE so the
        frontier = phases[n_done]                 # review-owed and gate-pending resolver/projection
        gate = frontier["gate_exit"]              # branches are actually differentially tested
        tasks = frontier["tasks"]
        mode = r.rand(3)
        if mode == 0:                             # in-flight: a task started and/or failed
            if r.chance():
                events.append({"event": "task_started", "task": tasks[0]["id"]})
            if r.chance():
                events.append({"event": "task_failed", "task": tasks[0]["id"]})
        elif mode == 1:                           # gate-pending: all tasks done, gate not run yet
            for t in tasks:
                events.append({"event": "task_done", "task": t["id"]})
        else:                                     # gate passed but review OWED (when review-blocked):
            for t in tasks:                       # all tasks done + gate_passed, but NO review_passed
                events.append({"event": "task_done", "task": t["id"]})
            events.append({"event": "gate_passed", "gate": gate})
    return dag, events


def render(dag, events):
    """A byte-stable text bundle (stdout mode) — dag then events, deterministic."""
    lines = [json.dumps(dag, indent=2, sort_keys=True), "---EVENTS---"]
    lines += [json.dumps(e, sort_keys=True) for e in events]
    return "\n".join(lines) + "\n"


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: gen-parity-case.py <seed> <dir|->\n")
        return 2
    seed = int(argv[1])
    target = argv[2]
    dag, events = build_case(seed)
    if target == "-":
        sys.stdout.write(render(dag, events))
        return 0
    hb = os.path.join(target, ".hb")
    os.makedirs(hb, exist_ok=True)
    with open(os.path.join(hb, "dag.json"), "w") as f:
        f.write(json.dumps(dag, indent=2, sort_keys=True) + "\n")
    with open(os.path.join(hb, "events.jsonl"), "w") as f:
        for e in events:
            f.write(json.dumps(e, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
