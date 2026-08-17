# Plan code-aware DAGs

The hardest part of authoring a HeartBeat DAG for a codebase is getting the `requires` edges
**sparse but real**: too many and you lose parallelism, too few and parallel tasks collide on the
same files. HeartBeat's method is domain-agnostic, so it can't know your call graph — but a code
graph does. The `heartbeat-code` adapter closes that gap by validating a `dag.json`'s dependencies
against a real code dependency graph. It is **advisory**: it reports; you adjust the DAG.

This is a *domain adapter*, not a core feature: it lives in `plugin/adapters/code/`, is never
scaffolded into a project's `.hb/`, imports nothing from core, and is node-only (not a parity
surface). See the adapter's [contract and finding types](../../plugin/adapters/code/README.md).

## The contract

The adapter consumes a small, provider-neutral **codemap**:

```json
{ "edges": [["symA", "symB"]], "tasks": { "P0T1": ["symA"], "P0T2": ["symB"] } }
```

`edges` are `from depends on to` (calls / imports / inheritance); `tasks` maps each task to the
symbols it creates or touches. Any tool can produce it — CodeGraph is the first provider.

## The workflow

1. Index your repo with CodeGraph (produces a local `.codegraph/codegraph.db`).
2. Turn its graph rows into the codemap `edges` with the provider mapper:

   ```bash
   node plugin/adapters/code/codegraph-map.js codegraph-rows.json > codemap.json
   ```

   The mapper resolves each node id to its qualified name and keeps only dependency-bearing edge
   types, dropping structural ones. Reading a live `.codegraph/codegraph.db` directly is
   harness-first (needs CodeGraph and `sqlite3`); the pure row-to-codemap mapping is what the test
   suite gates.

3. Add the `tasks` mapping (which symbols each task touches). This is the fuzzy step — a best-effort
   helper matches task text to symbol names, but **confirm it yourself**.
4. Dep-lint your DAG:

   ```bash
   node plugin/adapters/code/deplint.js your.dag.json codemap.json
   ```

   It prints `MISSING` (a code dependency with no `requires` ordering), `REDUNDANT` (a `requires`
   with no direct code dependency), and `COLLISION` (unordered tasks sharing a symbol). Fix the DAG
   by hand — the adapter never rewrites it. Pair this with
   [writing sparse dependencies](write-sparse-dependencies.md).

## Proof

The engine and the provider mapping are each backed by a runnable proof, wired into the suite as
T87: [`gate-examples/code-deplint.sh`](gate-examples/code-deplint.sh) exercises MISSING / REDUNDANT
/ COLLISION, the transitive-closure rule, and advisory-vs-strict exit codes; and
[`gate-examples/code-map.sh`](gate-examples/code-map.sh) proves the CodeGraph mapping resolves
qualified names and filters non-dependency edges. Run them:

```bash
bash docs/howto/gate-examples/code-deplint.sh   # -> CODE-DEPLINT-OK
bash docs/howto/gate-examples/code-map.sh       # -> CODE-MAP-OK
```
