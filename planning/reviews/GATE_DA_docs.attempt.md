# GATE_DA — docs adapter, lessons applied (reference-style links, real-corpus harness, discover reuse)

**Distinct actor:** reviewer agent. **Verdict: SOUND.**

- Reference-style parsing correct on an adversarial corpus: full `[t][ref]` + collapsed `[t][]` +
  `[ref]: x.md` defs resolved; def-only files yield ZERO edges (not mis-read); dangling refs, self-links,
  external/http defs excluded; inline+ref to same target dedups. node ≡ python set-equal.
- No regression: docs-map-parity (T95), docs-deplint (T90), docs-context (T91) green; inline unchanged.
- real-docs-map harness: 278 edges over docs/howto/, node≡python; RED if docs-map returns empty.
- discover reuse: dependents(method) = {intro,method,results}, excludes background (correct change-impact).
- Skill de-staled: reflink note + discover step (runnable) + "not a parity surface" → "parity surface (T95)";
  no residual stale claim anywhere.
- Proof teeth: reverting to inline-only turns docs-map-reflinks.sh RED. node 327/0 (T107–T109), parity OK,
  python 92, self-audit 63/61, skill-integrity OK.
