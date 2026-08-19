# GATE_DC — code adapter discovery core (reachability, both runtimes, parity)

**Distinct actor:** reviewer agent (not the doer). **Verdict: SOUND.**

Refutation attempts, all failed:
- Semantics correct (not swapped): `dependents`=reverse reachability (change impact), `dependencies`=forward, `both`=union; entry always included; induced edges = codemap edges with both endpoints affected. Verified on a fresh a→b→c codemap.
- Cycles terminate (visited-set guard) — a↔b returns {a,b}.
- Deterministic sorted output → real byte-equality; node ≡ python on an independent diamond+cycle+disconnected codemap across all directions.
- Proof teeth: code-discover.sh goes RED on a swapped direction and on a leaked symbol; oracle is impl-independent (literal expected sets).
- Suites: node 315/0 (T98 in GROUPS-PASSED), parity OK, python 88.
