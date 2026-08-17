# heartbeat-code — a domain adapter (Seam 1: plan authoring)

The HeartBeat *method* (DAG + gates + tick) is domain-agnostic. This is the first **domain
adapter**: it makes plan authoring *code-aware* without pulling code-specific machinery into
core. It validates a `dag.json`'s `requires` edges against a real code dependency graph, so a
plan for a codebase gets correct **sparse** dependencies — the hardest authoring problem.

## Boundary (why this is an adapter, not a feature)

- Lives in `plugin/adapters/code/` — delivered by the plugin but **not scaffolded into any
  `.hb/`** (a fresh `bootstrap.sh` never copies it).
- **Not core, not a parity surface** — single-runtime Node, like `viz` / `bench` / `mcp-serve`.
  It imports nothing from HeartBeat core; the suites stay green without it.
- **Advisory** — it reports; it never rewrites your DAG. A wrong auto-edge is worse than none.

## The contract (`codemap.json`)

The adapter consumes a narrow contract, so its logic is provable against fixtures and any
provider can feed it (CodeGraph is the first — see `codegraph-map.js`):

```json
{
  "edges": [["symA", "symB"], ...],          // symA depends on symB (calls/imports/inherits)
  "tasks": { "TASKID": ["symA", "symC"], ... }  // the symbols each task creates/touches
}
```

## `deplint.js`

```bash
node plugin/adapters/code/deplint.js <dag.json> <codemap.json> [--strict]
```

Findings (uses the `requires` **transitive closure**, so a dependency already ordered
transitively is *not* re-flagged):

| Finding | Meaning | Fix |
|---|---|---|
| `MISSING` | A depends on B in code but A isn't ordered-after B | add `A requires B` |
| `REDUNDANT` | `A requires B` with no **direct** code dependency between their symbols | maybe over-constrained (or a non-code / transitive-code dep) |
| `COLLISION` | unordered tasks touch the same symbol | isolate (worktree) or add an edge |

Prints `HB-CODE-DEPLINT: missing=<n> redundant=<m> collision=<k>` plus a detail line per
finding. Exit 0 by default (advisory); with `--strict`, exit 1 iff `missing>0` or
`collision>0` (`REDUNDANT` never fails `--strict` — a logical, non-code dependency is legit).

Proof: [`docs/howto/gate-examples/code-deplint.sh`](../../../docs/howto/gate-examples/code-deplint.sh)
(node-suite T87). Method + workflow: the `code-aware-planning` skill and
[`plan-code-aware-dags.md`](../../../docs/howto/plan-code-aware-dags.md).
