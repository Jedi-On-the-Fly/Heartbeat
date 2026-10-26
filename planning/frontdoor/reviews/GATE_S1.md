# GATE_S1 refutation, cycle 4

Mutation copy: /tmp/tmp.RgZtt4PbBb (full repo copy incl. .git and the three planning/refuter-*/.hb/dag.json; top-level .hb excluded).
Baseline in the copy: `bash tests/dag-shape.sh lint` -> SHAPE-LINT-OK (94 derived structure mutations, 100 existing dags against the a500587 oracle).

## G1 mutation
Re-introduced `_parse_int = int(s)` in py/src/heartbeat/lint.py. Copy's `bash tests/dag-shape.sh lint` went RED:
  FAIL: k7 [giant int in _meta]: verdicts differ (node=0 py=1):   x dag.json unreadable: not valid JSON
Restored -> green.
Fuzz (real node + python lint/audit, literals of 400/3000/3999/4000/4001/4400 digits, negative): at gate_entry, gate_exit, phase id, detached_from, task id, requires[], cmd, criteria entry, description, gate desc, parked, criterion id, requires-as-scalar: lint output+exit identical, audit JSON (normalized) identical. Also _meta -9..9 at 4000/4001/4300/4301/5000/400000 digits, long float, long int with exponent: identical. python no-arg CLI (HB_DIR) lint/audit: agrees. mcp_server uses the same read_dag_file. parity-notes.md line ~487 names the decision.

## G2 mutations
- py `if not g` instead of membership: RED (`questions [an empty gate object]: outputs differ`, node prints checklist, py "no gate 'G3'").
- node `if (!g)`: stays green, and correctly so: JS {} is truthy, so this is not a regression (the old bug was python-side).
- node desc guard dropped (`${g.desc || gate}`): RED (PHASE CLAIM: "" for list desc).
- py desc guard dropped (`g.get("desc") or gate`): RED (py PHASE CLAIM "{'a': 1}" vs node).
Fuzz: 15 gate values ({} , desc [] {} 5 false null "" unicode, criteria [] null {} garbage entries, [] null "s") x 6 gate names (G, __proto__, constructor, toString, hasOwnProperty, 0): checklist bytes and exit identical on both. Missing gate names identical.

## Final hunt
- (a) derivation is real: removing the annotation at schema line 198 (parked) drops cases 94 -> 88; annotating tasks[].description adds cases (94 -> 100) which the hand-written lint does not judge, so the test would redden. 
- (g,h,i) `--selftest lint` -> SHAPE-SELFTEST-LINT-OK; tests/parity.sh PARITY OK; replan REPLAN-OK; horizon HORIZON-OK; pytest 187 passed.
- Side nit (not STRUCTURE, not in G1/G2): `audit f.json --questions ''` — node now exits 2 with Usage (new in this wave: pre-wave node printed "no gate ''" rc 0), python's argparse treats '' as falsy and runs the plain audit (exit 1 on a dag with a gate named "0", output differs). An empty gate id is schema-impossible (minLength), CLI-argument edge only; recorded, not blocking.

## Answers
P1: NOT-REPRODUCED — 94 derived mutations + unreadable classes green in copy; giant-int / hostile-gate fuzz identical bytes, no tracebacks.
P2: NOT-REPRODUCED — k3 oracle (100 dags vs a500587) green in copy; replan/horizon/pytest/parity green.
P3: NOT-REPRODUCED — annotation removal shrinks cases 94->88, addition grows 94->100; mutations come from the schema.
P4: NOT-REPRODUCED — dag_shape normalized-identical in all fuzz (one finding each, text lines same), selftest strips green for the right reason, parity OK.
G1: NOT-REPRODUCED — mutation `int(s)` reddens k7 giant-int; 400..400000-digit literals in every probed position agree on both runtimes.
G2: NOT-REPRODUCED — the three wrong implementations (py falsy gate, either desc guard dropped) each redden the suite; fuzz agrees.

CLEAR
HOLES: none
