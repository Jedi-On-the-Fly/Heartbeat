---
name: code-aware-planning
description: Make HeartBeat plan authoring code-aware — validate a dag.json's `requires` edges against a real code dependency graph (via CodeGraph) so a plan for a codebase gets correct sparse dependencies. Use when turning a plan into a DAG for a code project, or auditing an existing dag.json's dependencies. A domain adapter over the general method, not a change to core.
---

# Code-Aware Planning Skill (Claude Code)

<!-- HB-ADAPTER: code -->

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
3. **Discover the affected set first (discovery-first).** Before finalizing tasks, start from the
   feature's entry-point symbols and trace the graph to scope the change:
   `node plugin/adapters/code/codegraph-discover.js <codemap.json> <entry1,entry2,…> [--dependents|--dependencies|--both]`
   (node-free twin: `python3 -m heartbeat.adapters.code.codegraph_discover …`). `dependents` = who
   transitively depends on the entry (**change impact** — surfaces indirect consumers, e.g. hidden
   authorization callers); `dependencies` = what it needs; `both` = the neighborhood. Map the affected
   symbols to tasks — the graph *informs* the decomposition; you still carve the tasks. Honest limit:
   the graph models resolved static edges only — dynamic/framework bindings (Alpine methods, template
   bindings) and not-yet-existing symbols still need reading code. Proof:
   `docs/howto/gate-examples/code-discover.sh`.
4. **Dep-lint the DAG**: run `deplint.js <dag.json> <codemap.json>`. It reports:
   - **MISSING** — a code dependency crosses two tasks with no `requires` ordering → add the edge.
   - **REDUNDANT** — a `requires` with no direct code dependency → maybe over-constrained.
   - **COLLISION** — unordered tasks touching the same symbol → isolate (worktree) or add an edge.
5. **Adjust the DAG yourself.** Treat every finding as advice — a wrong auto-edge is worse than a
   missing one. The adapter never rewrites the DAG.

## Feed code context to Stage B (Seam 2)

The same adapter also makes *execution* cheaper. Wire `codegraph-context.js` as the executor's
generic **`context_cmd`** hook so each task's worker (Stage B) receives the subgraph it needs — the
symbols the task touches plus their direct neighbors — instead of rediscovering them:

```bash
export HB_EXEC_CONTEXT_CMD='node plugin/adapters/code/codegraph-context.js codemap.json "$HB_TASK_ID"'
# — or node-free (Python package / a framework backend like Agno), same output (node ≡ python):
export HB_EXEC_CONTEXT_CMD='python3 -m heartbeat.adapters.code.codegraph_context codemap.json "$HB_TASK_ID"'
# dep-lint node-free too:  python3 -m heartbeat.adapters.code.deplint your.dag.json codemap.json
```

The executor runs it per task and appends its output to the task context (byte-identical node ≡
python); the executor itself stays code-agnostic. Proof:
`docs/howto/gate-examples/code-context.sh`.

## Boundary (hold this)

`deplint`/`codegraph-map`/`codegraph-context`/`codegraph-discover` are a **parity surface** (node ≡
python — proofs T94/T98), **not core**, and import nothing from HeartBeat core. The live CodeGraph
database read is harness-first (unproven without CodeGraph installed); the mapping, engine, context,
and discovery providers are gated hermetically — proofs: `docs/howto/gate-examples/code-deplint.sh`,
`docs/howto/gate-examples/code-map.sh`, `docs/howto/gate-examples/code-context.sh`,
`docs/howto/gate-examples/code-discover.sh` (node-suite T87/T88/T98).

Method detail and the contract: `plugin/adapters/code/README.md`. Workflow guide:
`docs/howto/plan-code-aware-dags.md`.
