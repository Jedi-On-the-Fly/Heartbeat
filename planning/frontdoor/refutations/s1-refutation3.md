# GATE_S1 refutation, round 3

Setup: `unset HB_DIR PROJECT_DIR GATE; export HB_NO_GIT=1 STUCK_TICKS=999`. Mutation copies in /tmp/claude-1000/r3x.8V6UsZ (m_*; rsync of the repo without .hb). Repo tree untouched.
Baseline copy: `bash tests/dag-shape.sh lint` -> SHAPE-LINT-OK (94 derived mutations, 100 existing dags vs the a500587 oracle); parity.sh PARITY OK.

## G1 mutation results (re-introduce the wrong implementation, run the copy's `bash tests/dag-shape.sh lint`)
- a1 node audit cmd -> String(c.cmd||''): RED, k7 [a list cmd carrying a control byte beside a behavioral one] (node errors:1 control_char, py errors:0).
- a2 node audit desc -> String(c.desc||''): RED, k7 [a list desc carrying a control byte].
- b1 python audit control_char -> str(c.get(k) or ''): GREEN, but equivalent: str(list) is repr, which escapes control bytes, so no raw \x1e/\x1f survives (same verdict as the correct code).
- b2 python audit task text -> (title or ''): RED, k7 [an object task title] (node warn gate_offphase, py none).
- b5 python lint task text -> (title or ''): RED, same case.
- b3 NODE audit task text -> (t.title || ''): GREEN. b4 NODE lint checkGateArtifacts -> (t.title || ''): GREEN.
  Cause: k7's object title coerces to '[object Object]' on node, which carries no file name, so node coercion is invisible; only python's str() of a dict leaks the text. A LIST title ["out.txt"] exposes it:
  fixture = k7 base with tasks[0].title=["out.txt"], gate cmd `grep -q ok "$PROJECT_DIR/out.txt"`:
  m_b3: node audit `{"findings":[],...}` vs py audit gate_offphase warn; m_b4: node lint warnings:[] vs py lint warns 'gate references out.txt ...'. Real code: both warn identically.
  So the node-side no-coercion fix for task titles/descriptions is correct in the shipped code but NOT pinned (the spec's own example is "an array becomes its joined text").

## G2 mutation results
- c1 node checkDetach back to JSON.stringify: RED k7 [detached_from=5.0 on a valid-id phase] (node 5 vs py a number).
- c2 python back to json.dumps: RED same case (got 5.0 vs a number).
- c3 node shown() renders numbers via String(): RED. c4 python _shown renders floats via repr: RED.
- d1 node shown() renders non-finite numbers via JSON.stringify (-> 'null'): GREEN. The k7 loop covers 5.0, -0.0, 12345678901234567890, [1.0], {"a":1}, "G9" for detached_from; the 1e400 text case is pinned only for the criteria-entry line, not the detach line (G2 asked for the float AND the 1e400 case).
- Direct probe, detached_from = 5.0, -0.0, 12345678901234567890, 1e400, -1e400, [1.0], {"a":5.0}, true, null, 1E2, 0.1e1 as raw text: identical sorted errors and exit on both ('got a number' / 'a list' / 'an object' / 'a boolean' / 'null'). Strings (e-acute, emoji, \u0001, \u007f,  , \u0085, ﻿, ￿, ﷐, \u0000, quotes, backslash): identical. Lone surrogates: both 'dag.json unreadable: not valid JSON'.

## Final hunt (P1-P4)
Differential fuzz: every path in the k7 base dag set to None, 5, 5.5, true, [], ["x\x1e","out.txt"], {"a":"out.txt"}, "", "x\x1ey"; lint and audit --json on both runtimes: 828 runs, 0 differences in exit / sorted lint lists / audit findings, 0 crashes. k3 now 100 dags, python agrees. grep of the diff shows no leftover String()/str()/JSON.stringify of a dag value.

## One line per id
P1: NOT-REPRODUCED — derived mutations + 828-run field/type fuzz identical on both runtimes (exit and bytes), no traceback.
P2: NOT-REPRODUCED — k3 green over 100 dags vs the a500587 oracle; parity.sh green.
P3: NOT-REPRODUCED — derivation count 94 in baseline, no hand-coded list found; not re-mutated this round.
P4: NOT-REPRODUCED — audit findings identical across the 828-run fuzz; parity green.
G1: NOT-REPRODUCED — shipped behaviour correct (a1/a2/b2/b5 red; fuzz identical); but node-side task-text coercion mutants b3 and b4 stay GREEN because k7's object title never exposes node coercion (needs a list title).
G2: NOT-REPRODUCED — behaviour byte-identical for every value probed; c1-c4 red; mutant d1 (node special-cases non-finite numbers in the detach line) stays GREEN, so the 1e400 detach case is not pinned.

REFUTED

HOLES:
1. Pin gap (G1): k7 "an object task title" cannot detect node re-coercing task title/description. Mutants b3 (hb-audit.js taskText) and b4 (hb-lint.js checkGateArtifacts) pass `bash tests/dag-shape.sh lint`. Fix: add k7 with a LIST title/description such as ["out.txt"].
2. Pin gap (G2): no k7 case for detached_from = 1e400 on a valid-id phase; mutant d1 stays green. Fix: write 1e400 as raw text into detached_from and compare lint outputs, as the criteria-entry case does.
