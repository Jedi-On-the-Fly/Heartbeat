# Domain adapters — how HeartBeat gets smart about a domain without stopping being general

HeartBeat's method — a DAG of phases and tasks, deterministic ticks, and behavioral gates — is
**domain-agnostic**. It knows nothing about code, and that is deliberate: the same machinery drives
a data pipeline, an infrastructure change, or a research write-up. Domain-specific intelligence
enters through **adapters** at two defined seams, never by teaching the core about a domain.

The concept ([heartbeat.md](heartbeat.md)) stays universal; adapters are the plug points.

## The two seams

1. **Plan authoring.** A plan is a DAG, and its `requires` edges must be *sparse but real*. The core
   can't know your real dependency structure — but a domain graph can. An adapter validates the DAG
   against that graph and flags missing / redundant / collision-prone edges. (You adjust the DAG;
   the adapter is advisory and never rewrites it.)
2. **Context assembly.** When Stage B does a task, an adapter can feed it the slice of the domain's
   knowledge that task needs, so the worker starts informed instead of rediscovering it. The
   executor exposes a generic `context_cmd` hook: whatever command you configure is run per task and
   its output is appended to the task context — the executor never inspects what it produces.

## The contract that makes it general

Both seams speak one small, provider-neutral shape — a **codemap**:

```json
{ "edges": [["A", "B"]], "tasks": { "TASK_ID": ["A", "C"] } }
```

`edges` are `A depends on B`; `tasks` maps each task to the units it touches. The ids are **opaque
strings** — the dep-lint engine and the context provider don't care whether they are functions,
tables, or clauses. So the engine generalizes for free; only the *provider* that produces the
codemap is domain-specific.

That means the same adapter shape fits non-code work:

| Domain | A provider builds `edges` from… |
|---|---|
| Data / analytics | table & column lineage (a dbt graph, SQL lineage) |
| Infrastructure | a Terraform/IaC resource dependency graph |
| Writing / research | a "cites / builds-on" graph between sections or claims — **shipped** (see below) |

**Two shipped domains today — code and docs/research** — proving the pattern with two genuinely
different providers over the *same* engine. Data/analytics and infrastructure are illustrations of
where it generalizes next, not shipped providers.

## The boundary (non-negotiable)

An adapter:

- lives under `plugin/adapters/` — delivered by the plugin but **never scaffolded into a project's
  `.hb/`**;
- is **not core** and **not a parity surface** — it imports nothing from core, and the test suites
  stay green whether or not it (or its backing tool) is installed;
- is **advisory / optional** — the DAG format, the gates, and the tick are unchanged.
- **ships a skill** — every adapter comes with its own Claude Code skill (`plugin/skills/<domain>-…`)
  that auto-triggers on that domain and runs the whole workflow, so usage has zero friction. This is
  enforced: `gate-examples/skill-integrity.sh` (T92) fails unless each adapter is declared by a skill
  naming real, wired proofs.

The one thing that *is* shared across runtimes is the generic `context_cmd` hook itself (it lives in
both executors and must behave identically) — so it carries a cross-runtime parity proof, while the
code-specific provider stays single-runtime. See [AGENTS.md](../AGENTS.md) and
[parity-notes.md](../planning/parity-notes.md).

## Code — the first domain

The `heartbeat-code` adapter ([README](../plugin/adapters/code/README.md)) uses
[CodeGraph](https://github.com/colbymchenry/codegraph) as its provider:

- **Seam 1** — `deplint.js` validates a DAG's `requires` against the call/dependency graph. Proof:
  [code-deplint.sh](howto/gate-examples/code-deplint.sh); `codegraph-map.js` turns CodeGraph's rows
  into the codemap, proof: [code-map.sh](howto/gate-examples/code-map.sh).
- **Seam 2** — `codegraph-context.js` renders a task's subgraph as context. Proof:
  [code-context.sh](howto/gate-examples/code-context.sh); the node ≡ python injection is proven by
  [context-inject-parity.sh](howto/gate-examples/context-inject-parity.sh).

**Honesty about maturity:** the pure engine, the row→codemap mapping, the context provider, and the
node ≡ python injection mechanism are gated hermetically (node-suite T87–T89). The **live CodeGraph
database read** and the **local-model end-to-end demo** (`tests/real-context.sh`, driven against a
local ollama model) are **harness-first / on-demand** — they need external tools and are
non-deterministic, so they are *not* part of the gated suite.

## Docs / research — the second domain

The `heartbeat-docs` adapter ([README](../plugin/adapters/docs/README.md)) is the proof that the
architecture generalizes: a completely different provider over the **unchanged** engine.

- **Seam 1** — `docs-map.js` parses a markdown corpus's **citation graph** (a section that links to
  another builds on it) into the same codemap — both `edges` and `tasks` (one authoring task per
  section). The **same `deplint.js`** then catches drafting a citing section before the one it cites.
  Proof: [docs-deplint.sh](howto/gate-examples/docs-deplint.sh) (T90); it also confirms `deplint.js`
  is byte-unchanged.
- **Seam 2** — `docs-context.js` renders the **text** of the sections a task directly cites, through
  the same generic context hook. Proof: [docs-context.sh](howto/gate-examples/docs-context.sh) (T91).

Only the provider is new — `deplint.js` and the `context_cmd` hook are reused as-is. The live
end-to-end demo (`tests/real-docs-context.sh`, ollama) is harness-first, like code's. Guide:
[plan a docs project with citations](howto/plan-a-docs-project-with-citations.md).

Guides: [build a domain adapter](howto/build-a-domain-adapter.md) ·
[feed code context to Stage B](howto/feed-code-context-to-stage-b.md) ·
[plan code-aware DAGs](howto/plan-code-aware-dags.md).
