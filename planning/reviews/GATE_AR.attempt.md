# GATE_AR — adapter docs refresh (both-runtimes / parity reality)

**Phase:** AR (v1_25-finalize) — refresh `build-a-domain-adapter.md`, `README.md` blurb, `dev-plugin.md`
for the parity/both-runtimes reality; keep the whole corpus prose-clean + self-audit green.

**Distinct actor:** reviewer agent (not the doer).

## First pass — UNSOUND
The three top-level docs were refreshed correctly, but the adapters' OWN docs still asserted the
opposite of the new reality:
- `plugin/adapters/code/README.md:12` — "Not core, not a parity surface — single-runtime Node."
- `plugin/adapters/docs/README.md:40` — "Node-only, … not a parity surface."
- `plugin/adapters/code/codegraph-context.js:8`, `docs/docs-context.js:7`, `docs/docs-map.js:10` — "Node-only, imports nothing from core."
- `planning/parity-notes.md:143` — "the code-context provider … is the node-only adapter above" (contradicting :117 two paragraphs up).

## Fix
Rewrote all six to state the adapters ARE a parity surface (shipped in both runtimes, node ≡ python,
T94/T95), preserving the boundary (not scaffolded, imports nothing from core). Surgical — only the
stale claim lines touched. The remaining "node-only" strings (`import` command, drift detection,
git-log divergence in the rest of the assembled context) are legitimate and unrelated to the adapters.

## Second pass — SOUND
- `grep -rniE 'not a parity surface|single-runtime' plugin/adapters` → no output.
- GATE_AR criteria: ara/arb/arc PASS; ard self-audit `SELF-AUDIT-OK:63/59 (parity:ok) — node ≡ python`.
- Node suite `313 passed, 0 failed`. Top-level docs, adapter docs, `adapters.md`, `parity-notes.md:117` all agree.

**Verdict: SOUND (could not refute).**
