# GATE_PA review — code adapter ported to Python (parity surface)

Adversarial review of the shipped PA work, distinct actor from the implementer.

## Round 1 — SOUND (no defects)
The reviewer ran node vs python on every fixture plus five hand-built adversarial inputs and found
zero divergences:
- **deplint** byte-identical on all 6 fixtures (incl. `multi`: 2 MISSING + 2 COLLISION, emit order
  pinned) and on reversed task order, multi-target MISSING, multi-symbol COLLISION (join order),
  redundant+missing mix, empty-DAG, falsy inputs. Task iteration order matches (JS Object.keys ≡
  Python dict insertion order). --strict exit codes identical (redundant does NOT trip strict).
- **codegraph_map** in fact byte-identical (stronger than the set-equal proof): duplicate edges,
  unknown ids, type filtering, and the JS `== null` vs Python `is None` edge (empty qn / id 0) all
  resolve identically. The DB read uses the stdlib sqlite3 MODULE (no shell-out).
- **codegraph_context** byte-identical incl. dedup order (`dict.fromkeys` ≡ `[...new Set()]`).
- Proofs are load-bearing: mutating each Python module (a message, a later em-dash line, a dropped
  edge type, a changed label) makes the corresponding proof FAIL — they compare FULL stdout, not the
  marker line.
- Boundary clean: only json/sys/sqlite3; no core imports, no subprocess/os.system.
- Suites: node 309/0 (T94.1-3), py test_adapters_code 4/4.

**VERDICT: SOUND**
