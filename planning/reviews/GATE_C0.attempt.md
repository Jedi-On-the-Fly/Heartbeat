# GATE_C0 review — heartbeat-code dep-lint engine (Seam 1)

Adversarial review of the shipped C0 work (refute-don't-confirm), distinct actor from the implementer.

## Round 1 — UNSOUND (engine logic sound; proof-rigor + doc-honesty holes)
Verified by mutation that the engine is correct: transitive-requires closure is right and
cycle-safe, MISSING direction correct (`A should require B` when A's symbol depends on B's),
REDUNDANT either-direction, COLLISION unordered-only, strict exit codes correct (red on
missing/collision, green on clean/redundant/transitive), no core imports, not scaffolded, graceful
on malformed input. Three defects found:
- **D1** — the proof asserted the MISSING line merely *contained* TA and TB, so a reversed
  suggestion ("TB should require TA") would still pass (direction regression uncaught).
- **D2** — the boundary sub-check passed vacuously: a bootstrap that produced no `.hb` left nothing
  to grep, so the leak check passed (existence, not behavior — AGENTS rule 3).
- **D3** — README/engine text said REDUNDANT = "no code dependency", but the engine checks only
  DIRECT symbol edges; a transitively-code-dependent `requires` was falsely flagged (overclaim).

## Fixes (strengthen proof / correct doc — gate not weakened)
- D1 → the proof now asserts the exact `MISSING: TA should require TB`. Teeth re-verified: reversing
  the suggestion in deplint.js makes the proof FAIL with "wrong/backwards"; restored → passes.
- D2 → the proof now asserts bootstrap exit 0 AND `.hb/hb.js` exists before the leak grep.
- D3 → both README row and the engine's REDUNDANT detail text now say "no **direct** code dependency
  between their symbols" (and the README Fix column notes a transitive-code dep as a cause).

## Round 2 — SOUND
Re-review ran the mutation tests: D1 caught, D2's vacuous case now fails, D3 doc matches behavior,
no new defect (set -euo pipefail interactions checked), node suite 298 passed / 0 failed, T87 green.

**VERDICT: SOUND**
