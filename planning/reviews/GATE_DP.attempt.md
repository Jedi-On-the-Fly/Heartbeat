# GATE_DP review — docs citation-graph adapter (second domain, Seam 1)

Adversarial review of the shipped DP work, distinct actor from the implementer.

## Round 1 — UNSOUND (core claim sound; two shipped-artifact defects)
Verified sound: `deplint.js` UNCHANGED (git diff empty) yet generalizes — on the docs codemap it
emits correctly-directed missing (`method should require background`) on the unordered plan and
missing=0 on the ordered one; docs-map excludes http/mailto/#/outside-corpus/self links, emits the
tasks map, and the fixture equals real output; proof fails-before-provider-exists; direction is
asserted two ways. Two defects in the phase's shipped artifacts:
- **README overclaim (AGENTS rule 7):** it documented a Seam-2 (`docs-context.js`, `docs-context.sh`
  T91) that doesn't exist until phase DC — a false current-state claim.
- **Dead sub-check:** `docs-deplint.sh`'s `grep example.com` guard could never fire (no `.md`,
  already dropped by the `.md` filter), so the http filter wasn't actually load-bearing.
Latent (fixture avoids; flagged): the link regex is inline-only and code-fence-naive.

## Fix (code/proof/doc; gate not weakened)
- Stripped the Seam-2 section + T91 reference from the docs README; added an accurate **Limitations**
  note (inline-links-only, code-fence-naive).
- Made the http filter load-bearing: the fixture's external link is now
  `https://example.com/results.md` (a remote URL whose basename collides with the corpus id
  `results`), and the proof asserts no phantom `[method,results]` edge. Teeth re-verified: commenting
  out the http filter makes the proof FAIL; restored → DOCS-DEPLINT-OK.

## Round 2 — SOUND
Re-review confirmed both defects closed (teeth on the http filter; README references gone,
Limitations accurate), no regression (docs-map still emits exactly the 4 edges + tasks; fixture ==
real output; deplint.js UNCHANGED), no new hole, node suite 302 passed / 0 failed.

**VERDICT: SOUND**
