---
name: code-aware-planning
description: Make HeartBeat plan authoring code-aware — validate a dag.json's `requires` edges against a real code dependency graph (via CodeGraph) so a plan for a codebase gets correct sparse dependencies. Use when turning a plan into a DAG for a code project, or auditing an existing dag.json's dependencies. A domain adapter over the general method, not a change to core.
---

# Code-Aware Planning Skill (Claude Code)

The HeartBeat method (DAG + gates + tick) is domain-agnostic. This skill applies the **first
domain adapter** — `heartbeat-code` (`plugin/adapters/code/`) — so that when the work is **code**,
the plan's `requires` edges are checked against the real call/dependency graph instead of guessed.
It is **advisory**: it reports; you decide. It changes nothing in core and is never scaffolded
into a project's `.hb/`.

## When to use

- During `/heartbeat plan` for a codebase — after drafting the DAG, before you run it.
- Auditing an existing `dag.json` whose dependencies you suspect are over- or under-constrained.

## The method

1. **Index the repo with CodeGraph** (the provider) so a code graph exists locally.
2. **Produce a codemap** — the narrow contract the adapter consumes:
   `{ "edges": [[symA, symB], …], "tasks": { "TASKID": [sym, …] } }` (symA depends on symB;
   each task maps to the symbols it touches). `codegraph-map.js` turns CodeGraph's rows into the
   `edges`; the `tasks` mapping is yours (best-effort — the fuzzy step; confirm it).
3. **Dep-lint the DAG**: run `deplint.js <dag.json> <codemap.json>`. It reports:
   - **MISSING** — a code dependency crosses two tasks with no `requires` ordering → add the edge.
   - **REDUNDANT** — a `requires` with no direct code dependency → maybe over-constrained.
   - **COLLISION** — unordered tasks touching the same symbol → isolate (worktree) or add an edge.
4. **Adjust the DAG yourself.** Treat every finding as advice — a wrong auto-edge is worse than a
   missing one. The adapter never rewrites the DAG.

## Boundary (hold this)

`deplint`/`codegraph-map` are **node-only, not core, not a parity surface**, and import nothing
from HeartBeat core. The live CodeGraph database read is harness-first (unproven without CodeGraph
installed); the pure mapping and the dep-lint engine are gated hermetically (node-suite T87).

Method detail and the contract: `plugin/adapters/code/README.md`. Workflow guide:
`docs/howto/plan-code-aware-dags.md`.
