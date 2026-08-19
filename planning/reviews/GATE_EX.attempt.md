# GATE_EX — keep CodeGraph off HeartBeat's .hb/ scaffold

**Distinct actor:** reviewer agent. **Verdict: SOUND.**

- Helper correct: idempotent (no dup), non-destructive (preserves include/other keys + a custom
  exclude entry), creates a missing file, recovers from malformed/empty gracefully.
- node ≡ python byte-identical on fresh + pre-seeded + malformed inputs.
- Real effect: real-codegraph-exclude-hb.sh + independent build both show .hb/ nodes nonzero→0 while
  src/ nodes unchanged (surgical); skips cleanly with codegraph off PATH.
- Proof teeth: breaking dedup / clobbering config / diverging indent each turns codegraph-exclude-hb.sh
  RED; harness correctly NOT in run-tests.sh, referenced from the helper header.
- Neutral: bootstrap.sh + base heartbeat SKILL untouched (code-adapter + code-aware-planning only).
- Suites: node 320/0 (T101+T102), parity OK, python 91, self-audit 63/61, skill-integrity OK (8 proofs).
- Nit fixed post-review: python header now also references the harness (symmetry with node).
