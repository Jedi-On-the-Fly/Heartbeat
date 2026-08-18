# GATE_SD review — codify "ship a skill" in the adapter recipe

Adversarial review of the shipped SD docs, distinct actor from the implementer.

## Round 1 — SOUND
Every claim checked against reality:
- build-a-domain-adapter.md §5 "Ship a skill" is a real numbered step (not a mention), accurately
  describing the T92 enforcement (each adapter declared by a skill naming real, WIRED proofs) and the
  HB-ADAPTER marker + narrow-trigger requirements — and honestly does NOT claim T92 enforces trigger
  narrowness (it doesn't).
- adapters.md adds "ships a skill" as a boundary property without overclaiming.
- prose-check PROSE-OK on both; corpus sweep + self-audit SELF-AUDIT-OK:63/52 (parity:ok); all cited
  commands run (SKILL-INTEGRITY-OK, --selftest teeth, T92 wired+green, §4 proofs green); all links
  resolve.

## Non-blocking findings (pre-existing, do not falsify any SD claim)
1. docs/adapters.md lives under docs/ (not docs/howto/), so the T79 sweep / self-audit — which glob
   docs/howto — don't guard its prose; it could rot silently. Predates GATE_SD (added in AD).
   Follow-up: wire adapters.md into a prose-check assertion.
2. Pre-existing flaky test T55.2 (recovery: doctor drift+rot, real CLI) — ~1 in 4 runs; exists on
   main, unrelated to adapters/skills. The adapter/doc-integrity groups (T79/T81/T87–T92) passed every
   run. Worth fixing separately.

**VERDICT: SOUND**
