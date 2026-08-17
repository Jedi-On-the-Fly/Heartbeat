# heartbeat-docs — the second domain adapter (docs / research)

Proof that the [adapter architecture](../../../docs/adapters.md) generalizes beyond code: this
adapter reads a markdown **citation graph** into the *same* codemap contract, so the **unchanged**
code-adapter engine (`../code/deplint.js`) and the generic context hook work on it — **only the
provider here is new.**

## Mapping (Seam 1)

`docs-map.js <corpusDir>` scans a folder of `.md` files and emits the full codemap:

```json
{ "edges": [["method", "background"]], "tasks": { "method": ["method"] } }
```

- **Unit** = a section = a `.md` file (id is its basename).
- **edge** `[citer, cited]` — a section that links to another *builds on* it (depends on it). Only
  relative links to another `.md` in the corpus count; `http(s)`, `mailto:`, `#anchors`, and links
  outside the corpus are ignored.
- **tasks** — one authoring task per section (`{ sectionId: [sectionId] }`), the docs convention that
  makes the whole codemap **provider-produced**, not hand-authored. (A project that uses different
  task ids supplies its own `tasks` map; the engine only needs task→unit.)

Then the unchanged engine validates a docs authoring DAG — MISSING = drafting a citing section
before the one it cites, COLLISION = two tasks editing the same section:

```bash
node plugin/adapters/code/deplint.js your-docs.dag.json <(node plugin/adapters/docs/docs-map.js corpus)
```

## Limitations

The parser matches **inline** markdown links only (`[text](file.md)`); reference-style links
(`[text][ref]`) are not followed, and links inside fenced code blocks are not distinguished from
real ones. Fine for the demonstrator corpus; a production parser would strip code fences and resolve
reference definitions.

## Boundary

Node-only, **not scaffolded into any `.hb/`**, **not core**, **not a parity surface**; imports
nothing from core. Proof: [docs-deplint.sh](../../../docs/howto/gate-examples/docs-deplint.sh) (T90).
