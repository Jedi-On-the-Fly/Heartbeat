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
   It emits `edges` (`[citer, cited]`, from relative `.md` links; external/anchor links ignored) and
   `tasks` (one authoring task per section, id = the section's basename).
2. **Dep-lint the authoring DAG with the UNCHANGED engine** — the very `deplint.js` the code adapter
   ships, no new engine:
   ```bash
   node plugin/adapters/code/deplint.js my-doc.dag.json codemap.json
   ```
   - **MISSING** — a task drafting a citing section with no `requires` on the cited one → add it.
   - **REDUNDANT** — an ordering with no citation → maybe over-constrained.
   - **COLLISION** — two tasks editing the same section → isolate or add an edge.
3. **Feed cited-section text to the writer (Seam 2)** via the generic `context_cmd` hook, so each
   task's worker sees the sections it cites before writing:
   ```bash
   export HB_EXEC_CONTEXT_CMD='node plugin/adapters/docs/docs-context.js my-doc/ codemap.json "$HB_TASK_ID"'
   ```
4. **Adjust the DAG yourself.** Findings are advice; the adapter never rewrites your DAG.

## Boundary (hold this)

`docs-map`/`docs-context` are **node-only, not core, not a parity surface**, and import nothing from
core. Only the provider is new — `deplint.js` and the context hook are reused unchanged. Gated
hermetically — proofs: `docs/howto/gate-examples/docs-deplint.sh`,
`docs/howto/gate-examples/docs-context.sh` (node-suite T90/T91).

Method detail and the contract: `plugin/adapters/docs/README.md`. Workflow guide:
`docs/howto/plan-a-docs-project-with-citations.md`.
