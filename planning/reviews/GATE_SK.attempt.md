# GATE_SK review — adapter skills + skill-integrity gate

Adversarial review of the shipped SK work, distinct actor from the implementer.

## Round 1 — UNSOUND (a real, active cross-adapter leak)
Most held (checker teeth a–d caught on the real tree; selftest guards the checker; 0-adapters not
vacuous; boundary clean — deplint/executors untouched; skills valid). One active defect:
- **Cross-adapter leakage.** The checker matched skill→adapter with an unanchored substring grep
  `adapters/$dom`. The docs skill legitimately references `plugin/adapters/code/deplint.js` (it
  reuses the engine), so it was credited to the **code** adapter. Demonstrated: stripping the code
  skill's proofs still printed SKILL-INTEGRITY-OK. Plus a substring leak (`adapters/codeXYZ`).

## Fix (proof/skills; gate not weakened)
- The checker now attributes a skill to an adapter by an **anchored `HB-ADAPTER: <domain>`
  declaration** (`[[:space:]]*<dom>([^A-Za-z0-9_-]|$)`), not a path mention. Added
  `<!-- HB-ADAPTER: code -->` / `<!-- HB-ADAPTER: docs -->` to the two skills.
- The `--selftest` gained isolation fixtures — good / goo (substring) / noskill / badproof (unwired) /
  leaked (path-mentioned but not declared) — each asserted by a distinct message.

## Round 2 — SOUND
Re-review re-proved: stripping the code skill's proofs now FAILS ('adapter code skill names no
proof' — docs skill no longer covers it); substring rejected; attribution is exactly 3 proofs→code,
2→docs (total 5, not the buggy 7); reverting the anchor makes --selftest fail on the leaked/goo case;
no new soundness hole (fence-blindness only ever over-attributes, can't mask; dual-declaration is
benign latitude); node 305/0.

**VERDICT: SOUND**
