# Build a domain adapter

HeartBeat's method is domain-agnostic; a **domain adapter** makes it smart about *your* domain
without changing the core. This guide shows how to build one, using the shipped code adapter as the
worked example. The full concept is in [adapters.md](../adapters.md).

An adapter plugs into one or both **seams**: plan authoring (validate a DAG's `requires` against a
real dependency graph) and context assembly (feed Stage B the knowledge a task needs). Both speak
one small contract, so the same engine works for any domain.

## 1. Emit the codemap contract

Whatever your domain, your provider produces a **codemap**:

```json
{ "edges": [["A", "B"]], "tasks": { "TASK_ID": ["A", "C"] } }
```

`edges` mean `A depends on B`; `tasks` maps each task to the units it touches. The ids are opaque
strings — functions, tables, Terraform resources, document sections, whatever your domain's
"depends-on" graph connects. Write a small script that reads your domain's real graph and prints
this shape. The code adapter's provider (`plugin/adapters/code/codegraph-map.js`) does exactly this
for CodeGraph's rows.

## 2. Reuse the engines

You do **not** write new validation or context logic — you feed the existing ones:

- Plan authoring: `node plugin/adapters/code/deplint.js <dag.json> <codemap.json>` reports missing /
  redundant / collision-prone edges. It is domain-neutral; your codemap is all it needs.
- Context assembly: point the executor's generic `context_cmd` hook at a provider that renders the
  relevant slice of your graph (see [feed code context to Stage B](feed-code-context-to-stage-b.md)).

## 3. Ship it in both runtimes (a parity surface)

An adapter is a **parity surface**: implement the provider in **both** runtimes — node under
`plugin/adapters/<domain>/` and Python under `py/src/heartbeat/adapters/<domain>/` — and cross-check
them node ≡ python (byte-equal for deterministic outputs like the dep-lint findings and the context
text; set-equal for the maps, where order can differ). That keeps the capability **native to the
Python/framework path** (a `context_cmd='python3 -m heartbeat.adapters.<domain>…'` runs with **zero
Node** — proof [`gate-examples/adapters-nodefree.sh`](gate-examples/adapters-nodefree.sh)), not just
the node plugin. The code/docs adapters are the template (parity proofs T94/T95). One deliberate
divergence is allowed: an implementation detail that produces the *same output* (e.g. node shells to
the `sqlite3` CLI, Python uses the stdlib `sqlite3` module) — record it in
[parity-notes.md](../../planning/parity-notes.md).

## 4. Respect the boundary

Keep the adapter honest:

- Put it under `plugin/adapters/` (+ `py/src/heartbeat/adapters/`) — it must **not** be scaffolded
  into a project's `.hb/`.
- Import nothing from core; the test suites must stay green without your adapter installed.
- Keep it advisory — report, never rewrite the user's DAG.

## 5. Gate it like everything else

An adapter is a claim, so back it with a runnable proof. The code adapter's proofs are the template:
[`gate-examples/code-deplint.sh`](gate-examples/code-deplint.sh) exercises the dep-lint engine over
fixtures, and [`gate-examples/code-map.sh`](gate-examples/code-map.sh) proves the provider mapping.
Write your provider's proof spec-first (it must fail before the provider exists), wire it into
`tests/run-tests.sh`, and refute it before it ships.

```bash
bash docs/howto/gate-examples/code-deplint.sh   # -> CODE-DEPLINT-OK
bash docs/howto/gate-examples/code-map.sh        # -> CODE-MAP-OK
```

## 6. Ship a skill

An adapter isn't done until it's **frictionless**: every adapter must **ship a skill** under
`plugin/skills/<domain>-…/` so a user never touches the raw `node plugin/adapters/…` commands — the
skill auto-triggers on that domain and runs the whole workflow (map → dep-lint → context). Give it a
**narrow** trigger description (so it fires on the right domain, not every task), declare which
adapter it's for with an `HB-ADAPTER: <domain>` marker, and have it **name its proofs** by path.

This is enforced, not optional: [`gate-examples/skill-integrity.sh`](gate-examples/skill-integrity.sh)
(node-suite T92) fails unless every `plugin/adapters/<domain>/` is declared by a skill that names
real, **wired** proofs. So a new domain that forgets its skill turns the suite red.

```bash
bash docs/howto/gate-examples/skill-integrity.sh   # -> SKILL-INTEGRITY-OK
```
