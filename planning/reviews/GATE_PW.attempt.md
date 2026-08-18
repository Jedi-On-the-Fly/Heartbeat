# GATE_PW review — node-free availability + flip the parity-notes stance

Adversarial review of the shipped PW work, distinct actor from the implementer.

## Round 1 — SOUND (no holes)
- **Node-free proof honest & teethed:** adapters-nodefree.sh builds a synthetic bindir with only
  python3/bash (node deliberately omitted), runs via `env -i PATH=$bin`, and hard-fails if
  `command -v node` succeeds. Verified: passes clean; tampering to link node fails at step 0
  ("would be vacuous"); breaking a python adapter fails the run. Genuinely exercises the python
  adapters + a python context_cmd through executor.assemble_context with node off PATH.
- **Ollama demo** (real-docs-context-py.sh) on-demand (not in run-tests.sh), python provider, skips
  without ollama; ran green here (ollama up). Honestly labeled not-gated.
- **Flip honest:** parity-notes now says "the adapters ARE a parity surface — node ≡ python"
  (T94/T95); both "not a parity surface" adapter lines deleted (0 remaining). adapters.md agrees;
  skills/how-tos show working python invocations (spot-run confirmed). No overclaim.
- **Self-audit / referenced-proof integrity:** keep-the-runtimes-in-parity.md names all six proofs
  by body reference, so self-audit enforces existence+wiring; SELF-AUDIT-OK:63/58 (parity:ok). All
  six wired (T94.1-3, T95.1-2, T96.1).
- **Prose:** T93 all 70 docs green; no broken links / fake hb commands.
- **Suites:** node 312/0, python 85, parity OK.

**VERDICT: SOUND**
