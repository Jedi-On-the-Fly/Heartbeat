# GATE_AD review — adapter architecture doc + gated how-tos

Adversarial review of the shipped AD docs (a doc is a claim), distinct actor from the author.

## Round 1 — SOUND (no holes)
The reviewer tried to break every concrete claim in docs/adapters.md and the two how-tos, and
cross-checked each against the actual code/tests:
- **No overclaim**: adapters.md frames data-lineage/IaC/research as the pattern generalizing, NOT
  shipped providers (only the code adapter exists); the live CodeGraph DB read and the ollama e2e are
  presented as harness-first / on-demand and are verified absent from the gated suite.
- Every concrete claim checks out against reality: "both executors inject identically" (T89),
  "not scaffolded into .hb" (bootstrap has no adapters ref), "imports nothing from core" (only
  fs/child_process), "gated by T87–T89" (wired; suite 301/0).
- **Commands** all real and correct (ran the four proofs + the codegraph-context invocation +
  deplint --strict).
- **Links** all resolve (prose-check ALL-PROSE-OK on all three docs, incl. adapters.md's ../AGENTS.md,
  ../planning/parity-notes.md, ../plugin/adapters/code/README.md, howto/*).
- **Referenced proofs** exist AND are wired (self-audit SELF-AUDIT-OK:62/49, parity:ok).
- **Consistency** with parity-notes: the two-seam model, the codemap contract, and the boundary
  (node-only provider vs the one shared context-hook parity surface) all match.

No new inaccuracy, dead link, fake command, or thinness found. The docs are not more confident than
the code warrants.

**VERDICT: SOUND**
