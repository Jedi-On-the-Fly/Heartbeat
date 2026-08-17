# GATE_DC review — docs adapter Seam 2 (context) + docs

Adversarial review of the shipped DC work, distinct actor from the implementer.

## Round 1 — SOUND (no holes)
Tried to break it on six axes; all held:
- **Provider**: docs-context renders only DIRECT-cited sections' text — 2-hop (background) and the
  task's own body excluded; multi-cite (intro→background+method) renders both; cites-nothing and
  missing-file degrade gracefully. Mutation refutation: forcing it to dump the whole corpus makes the
  proof FAIL ("2-hop section leaked").
- **Proof integrity**: set -euo pipefail + explicit exits; fails before docs-context.js exists;
  DOCS-CONTEXT-OK can't print with a sub-check skipped.
- **Honesty (rule 7)**: adapters.md presents docs as a shipped second domain without claiming the
  ollama demo is gated; the how-to passes prose-check, links resolve, uses node forms (no fake `hb`);
  real-docs-context.sh confirmed NOT in the suite.
- **Boundary**: docs-context.js imports only fs/path; deplint.js UNCHANGED; the context hook
  (executor.py/hb-exec.js) UNCHANGED — docs Seam 2 reuses them, doesn't edit them.
- **Consistency**: parity-notes accurately marks the docs adapter node-only / not-a-parity-surface,
  reusing the unchanged engine + hook.
- **Suites**: node 303/0 (incl T90/T91), python 77, parity OK.

Non-blocking note: the adapter how-tos aren't individually wired into a prose-check group, but the
whole-corpus sweep (T79) + self-audit cover them, and it matches the sibling adapter-how-to
convention — not a regression.

**VERDICT: SOUND**
