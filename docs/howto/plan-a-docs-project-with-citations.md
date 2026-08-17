# Plan a docs/research project with citation-aware dependencies

Writing a doc or paper is a DAG too: a section that cites another *builds on* it, so it should be
drafted after the one it cites — and two tasks editing the same section collide. The **docs adapter**
(the second [domain adapter](../adapters.md), after code) makes HeartBeat's plan authoring aware of
that citation graph, reusing the *same* engine the code adapter uses — only the provider is new.

## 1. Get the citation codemap

`docs-map.js` reads a folder of markdown sections and emits the codemap contract — `edges`
(`[citer, cited]`, from relative `.md` links) and `tasks` (one authoring task per section):

```bash
node plugin/adapters/docs/docs-map.js my-doc/ > codemap.json
```

External links (`http(s)`, `mailto:`), `#anchors`, and links outside the corpus are ignored; each
section maps to one task named after it.

## 2. Dep-lint your authoring DAG — with the UNCHANGED engine

The same `deplint.js` the code adapter ships validates the docs DAG. No new engine:

```bash
node plugin/adapters/code/deplint.js my-doc.dag.json codemap.json
```

It reports **MISSING** (a task drafting a citing section with no `requires` on the cited one),
**REDUNDANT** (an ordering with no citation), and **COLLISION** (two tasks editing one section). Fix
the DAG by hand — it's advisory, like [dep-linting code](plan-code-aware-dags.md).

## 3. Feed cited-section text to the writer (Seam 2)

`docs-context.js` renders the text of the sections a task directly cites — the "read these before
writing" block — through the generic `context_cmd` hook:

```bash
export HB_EXEC_CONTEXT_CMD='node plugin/adapters/docs/docs-context.js my-doc/ codemap.json "$HB_TASK_ID"'
```

## Proof

Both are backed by runnable proofs wired into the suite:
[`gate-examples/docs-deplint.sh`](gate-examples/docs-deplint.sh) (T90 — the citation graph maps to
the codemap and the unchanged engine catches a correctly-directed missing edge) and
[`gate-examples/docs-context.sh`](gate-examples/docs-context.sh) (T91 — the direct-cited section's
text is rendered, 2-hop and self excluded).

```bash
bash docs/howto/gate-examples/docs-deplint.sh   # -> DOCS-DEPLINT-OK
bash docs/howto/gate-examples/docs-context.sh    # -> DOCS-CONTEXT-OK
```

Driving a real local model with the injected cited text is a separate on-demand demo
(`tests/real-docs-context.sh`, run against a local ollama model) — not part of the gated suite.
