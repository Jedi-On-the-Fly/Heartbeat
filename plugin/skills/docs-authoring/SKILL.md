---
name: docs-authoring
description: Plan a multi-section documentation or research WRITING project as a HeartBeat DAG with citation-aware task dependencies and cited-section context. Use when structuring a doc/paper/report whose sections cite each other and you want the authoring order and per-task context derived from the citation graph. The docs domain adapter over the general method — not for one-off doc edits, and not a change to core.
---

# Docs-Authoring Skill (Claude Code)

<!-- HB-ADAPTER: docs -->

The HeartBeat method (DAG + gates + tick) is domain-agnostic. This skill applies the **docs domain
adapter** — `heartbeat-docs` (`plugin/adapters/docs/`) — so that when the work is **writing**, a
section's `requires` ordering and its context come from the real **citation graph** (a section that
links to another builds on it). It reuses the *same* engine the code adapter ships — only the
provider is different. It is **advisory**: it reports; you decide.

## When to use

- Planning a multi-section doc/paper/report as a DAG (one authoring task per section).
- Auditing an existing authoring DAG whose section ordering you suspect is wrong.

*Not* for a single doc edit or unstructured prose — this is for a **cited, multi-section** project.

## The method

1. **Get the citation codemap** from your markdown corpus:
   ```bash
   node plugin/adapters/docs/docs-map.js my-doc/ > codemap.json
   ```
   It emits `edges` (`[citer, cited]`, from relative `.md` links — both inline `[text](x.md)` **and
   reference-style** `[text][ref]` / collapsed `[text][]` with `[ref]: x.md` definitions;
   external/anchor links ignored) and `tasks` (one authoring task per section, id = the section's basename).
2. **Dep-lint the authoring DAG with the UNCHANGED engine** — the very `deplint.js` the code adapter
   ships, no new engine:
   ```bash
   node plugin/adapters/code/deplint.js my-doc.dag.json codemap.json
   ```
   - **MISSING** — a task drafting a citing section with no `requires` on the cited one → add it.
   - **REDUNDANT** — an ordering with no citation → maybe over-constrained.
   - **COLLISION** — two tasks editing the same section → isolate or add an edge.
3. **Scope a revision — change impact.** Before rewriting a section, see which sections *build on* it
   (reverse citations), reusing the domain-neutral **`discover`** engine over the citation codemap:
   ```bash
   node plugin/adapters/code/codegraph-discover.js codemap.json <section> --dependents
   ```
   `dependents` = the sections that transitively cite `<section>` — the ones a change ripples into. It
   is the *same* engine the code adapter uses for code change-impact; it operates on the codemap, so
   docs reuse it unchanged.
4. **Feed cited-section text to the writer (Seam 2)** via the generic `context_cmd` hook, so each
   task's worker sees the sections it cites before writing:
   ```bash
   export HB_EXEC_CONTEXT_CMD='node plugin/adapters/docs/docs-context.js my-doc/ codemap.json "$HB_TASK_ID"'
   # — or node-free (Python package / a framework backend), same output (node ≡ python):
   export HB_EXEC_CONTEXT_CMD='python3 -m heartbeat.adapters.docs.docs_context my-doc/ codemap.json "$HB_TASK_ID"'
   # get the codemap node-free too:  python3 -m heartbeat.adapters.docs.docs_map my-doc/ > codemap.json
   ```
5. **Adjust the DAG yourself.** Findings are advice; the adapter never rewrites your DAG.

## Boundary (hold this)

`docs-map`/`docs-context` are a **parity surface** (node ≡ python — proof T95), **not core**, and
import nothing from core. Only the provider is new — `deplint.js`, the context hook, and the
`discover` change-impact engine are reused unchanged. Gated hermetically — proofs:
`docs/howto/gate-examples/docs-deplint.sh`, `docs/howto/gate-examples/docs-context.sh` (node-suite
T90/T91), reference-style links `docs-map-reflinks.sh` (T107).

Method detail and the contract: `plugin/adapters/docs/README.md`. Workflow guide:
`docs/howto/plan-a-docs-project-with-citations.md`.
