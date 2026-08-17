# GATE_C1 review — CodeGraph provider mapping + method/docs

Adversarial review of the shipped C1 work (refute-don't-confirm), distinct actor from the implementer.

## Round 1 — SOUND (no genuine defect found)
The reviewer ran every claim and tried hard to break it:
- **Mapping** — `mapCodegraph` resolves id→qualified_name and keeps only the calls/imports/inheritance
  allowlist. Mutation-tested BOTH ways: a pass-everything mutant fails the proof ("unexpected edge —
  filter failed?"); an over-filter mutant fails ("missing expected edge"). Skips edges to unknown
  node ids and nodes missing qualified_name without crashing. The fixture's non-dependency `contains`
  edge is genuinely absent from expected — the filter assertion is non-vacuous.
- **Proof** — fails before codegraph-map.js exists (spec-first); the node -e set-equality is
  order-insensitive and catches both a missing and an extra edge; `set -euo pipefail` + guarded
  exits are robust (marker can't print with a sub-check skipped).
- **Honesty** — `readCodegraphDb` appears nowhere in tests/ (live DB read genuinely harness-first,
  unproven in-repo); the "best-effort model of CodeGraph's schema (not vendored)" caveat is present
  and honest; no overclaim of a working live hookup in the how-to or skill.
- **resolveTaskSymbols** — advisory/fuzzy, unused by any gate; labeled as such in code, how-to, and
  skill. Accidental substring matches are acceptable given it's advisory and unwired.
- **Boundary** — codegraph-map.js imports only fs + child_process (no core, no relative `..`);
  the parity-notes entry is accurate (node-only, not a parity surface, not scaffolded).
- **Docs** — prose-check PROSE-OK (links resolve, node forms not fake `hb` commands); both referenced
  proofs exist and are wired (T87.1/T87.2); self-audit SELF-AUDIT-OK:60/47 (parity:ok).
- **Suite** — node 299 passed / 0 failed, all green.

Benign note (not a defect): the proof's set-equality is dedup-insensitive, but the consumer
(`deplint.js`) rebuilds its own edge set, so duplicate edges are inert downstream.

**VERDICT: SOUND**
