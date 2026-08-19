# heartbeat-code — a domain adapter (plan authoring + context + discovery)

The HeartBeat *method* (DAG + gates + tick) is domain-agnostic. This is the first **domain
adapter**: it makes plan authoring *code-aware* without pulling code-specific machinery into
core. It validates a `dag.json`'s `requires` edges against a real code dependency graph, so a
plan for a codebase gets correct **sparse** dependencies — the hardest authoring problem.

## Boundary (why this is an adapter, not a feature)

- Lives in `plugin/adapters/code/` — delivered by the plugin but **not scaffolded into any
  `.hb/`** (a fresh `bootstrap.sh` never copies it).
- **Not core, but a parity surface** — shipped in **both runtimes** (node here, Python under
  `py/src/heartbeat/adapters/code/`) and cross-checked node ≡ python (T94). It imports nothing
  from HeartBeat core; the suites stay green without it.
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
(node-suite T87). `deplint` also **suppresses `REDUNDANT` for a task with no resolved symbols** (a
spec-first / not-yet-existing file — the graph has no basis to judge; T101). Method + workflow: the
`code-aware-planning` skill and [`plan-code-aware-dags.md`](../../../docs/howto/plan-code-aware-dags.md).

## Other providers

All node ≡ python (`python3 -m heartbeat.adapters.code.<module>`), advisory, none scaffolded into `.hb/`;
`deplint` / `code_context` / `code_discover` are also exposed over MCP:

- **`codegraph-context.js`** — Seam 2: render a task's subgraph (touched symbols + direct neighbors) as
  context for Stage B via the executor's `context_cmd` hook. Proof:
  [`code-context.sh`](../../../docs/howto/gate-examples/code-context.sh) (T88).
- **`codegraph-discover.js`** — discovery: from entry symbols, the transitively-affected set
  (`dependents` = change impact / `dependencies` / `both`) + induced subgraph, to scope a change before
  authoring the DAG. Proof: [`code-discover.sh`](../../../docs/howto/gate-examples/code-discover.sh) (T98).
- **`deplint-accept.js`** — plan-acceptance wrapper: resolves the codemap (`--codemap` →
  `<dir>/codemap.json` → provisional build from `.codegraph/codegraph.db` → skip) then runs deplint
  (advisory; `--strict` blocks). Proof:
  [`deplint-accept.sh`](../../../docs/howto/gate-examples/deplint-accept.sh) (T100).
- **`codegraph-exclude-hb.js`** — idempotently excludes `.hb/` from the project's `codegraph.json` so
  CodeGraph indexes the app, not the scaffold; run before `codegraph init`. Proof:
  [`codegraph-exclude-hb.sh`](../../../docs/howto/gate-examples/codegraph-exclude-hb.sh) (T102).

`codegraph-map.js` also exposes `resolveTaskSymbols` (fuzzy task→symbol; node ≡ python).
