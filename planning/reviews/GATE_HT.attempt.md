# GATE_HT — build-a-domain-adapter how-to: engine-vs-provider split + lessons

**Distinct actor:** reviewer agent. **Verdict: SOUND.**

- Section 2 accurately names deplint + discover as domain-neutral codemap engines; honestly states
  coverage does NOT transfer (docs task→own section→1 symbol→no signal) and exclude-hb is CodeGraph-specific.
  Verified against codegraph-discover.js (edges-only), codegraph-coverage.js (task-symbol count), docs codemap shape.
- The discover command shown is runnable (single entry = valid one-element list).
- All six lessons map to real corrections (git: codegraph-map rename→denylist, RD 793e5b4, EX 156af80,
  node-only helper port, 453c10e "not a parity surface" fix). Concise, not padded.
- Integrity: prose-check clean (PROSE-OK), all links resolve incl. ../../tests/real-codegraph-map.sh;
  section numbering coherent 1..7. self-audit 63/61, node 327/0 (T93/T92/T109 green).
