# GATE_GR — research adapter grounding core (ground-check)

**Distinct actor:** reviewer agent. **Verdict: SOUND.**

- Classification correct on an independent 6-case map: grounded (line-wrapped excerpt), FABRICATED-QUOTE,
  UNGROUNDED (undeclared source / empty excerpt), MISSING-SOURCE, STALE. grounded=N correct.
- Critical ordering: an edited source (sha≠recorded) that STILL contains the excerpt reports STALE, not
  GROUNDED (sha-before-excerpt) — verified.
- Normalization can't be gamed: a genuinely fabricated quote is caught; whitespace-dirty excerpt still
  matches; sha over raw BYTES, excerpt over normalized decoded text.
- node ≡ python byte-identical (em-dash, sorted issues) on fixture + own map.
- --strict blocks iff issues; advisory exits 0; boundary: stdlib only, no core imports, no network.
- Honest: skill + how-to state it verifies GROUNDING not TRUTH, fetch is on-demand.
- T92: research adapter now declared (skill-integrity 3 adapters, 10 proofs); RED without the skill.
- Proof teeth: mark-all-grounded and remove-STALE both turn ground-check.sh RED.
- Suites: node 329/0 (T110/T111/T92/T93), python 94, parity OK, self-audit 64/62, prose ALL-PROSE-OK:71.
