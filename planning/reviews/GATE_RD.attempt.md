# GATE_RD — deplint: no REDUNDANT for tasks with no resolved symbols

**Distinct actor:** reviewer agent. **Verdict: SOUND.**

- Suppression rule is exactly "skip iff either side empty": empty-from/empty-to/both-empty suppressed;
  both-with-symbols+no-edge still REDUNDANT; both+edge not redundant. No over/under-fire.
- MISSING and COLLISION untouched (combined codemap: missing=1, redundant=0, collision=1).
- No regression: T87 code-deplint.sh green (its REDUNDANT fixture has real symbols both sides).
- Parity byte-identical node ≡ python on the fixture + 7 constructed cases.
- Proof teeth: mutating over-fire or under-fire turns deplint-redundant-empty.sh RED; reverted.
- Suites: node 319/0 (T87+T101 in GROUPS-PASSED), parity OK, python 91.
