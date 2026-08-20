# Source and ground research: the on-demand fetch → stamp → ground → context flow

[Grounding a claim](ground-research-claims.md) proves a quote is real *once you already have an
evidence map*. This guide is the step before and the step after: how the map gets **sourced** (an
on-demand fetch you drive), how its hashes are made **honest** (`stamp-evidence`), and how a section's
grounded evidence is handed to the **writer** (`research-context`). Together with `ground-check` these
are the research adapter's deterministic bridges.

## The determinism boundary (read this first)

Fetching from the web is **non-deterministic** — the network, a search model, a page that changes
tomorrow. HeartBeat gates must be deterministic. So the **fetch is on-demand and lives outside the
gate**; everything downstream of the stored snapshot is deterministic and *does* gate. The split:

| Step | Who / how | Gated? |
|---|---|---|
| **Fetch** — find sources, extract their text | an agent (WebSearch / the deep-research skill), on-demand | **No** — non-deterministic, by design |
| **Stamp** — record honest sha256 of each stored source | `stamp-evidence` | Yes — deterministic |
| **Ground** — verify every excerpt against its stored source | `ground-check --strict` | Yes — the gate |
| **Context** — render a section's grounded evidence for the writer | `research-context` | Yes — deterministic |

This is the same pattern as the code adapter's live-CodeGraph read (on-demand) versus its gated pure
logic: the non-deterministic input produces a **stored artifact**, and the artifact is what gates.

## 1. Source (on-demand)

An agent searches — using Claude Code's `WebSearch`, or a deep-research skill — and for each source it
keeps, **drops the extracted text into a file** and notes the url. You end up with:

```
sources/s1.txt          # the verbatim text you read
evidence.json           # sources + claims, but the sha256s are not filled in yet
```

Nothing here is gated: this is the human/agent judgment step. The point of the rest of the flow is that
*no downstream step trusts this one* — the shas and the quotes are all re-verified from the stored files.

## 2. Stamp (make the hashes honest)

An agent could write any `sha256` it likes into `evidence.json`. `stamp-evidence` removes that trust: it
recomputes each source's hash **from the stored file bytes** and stamps it in.

```bash
node plugin/adapters/research/stamp-evidence.js evidence.json sources/ > stamped.json
# node-free twin:  python3 -m heartbeat.adapters.research.stamp_evidence evidence.json sources/
```

Stamping is a **one-time, at-store-time** step. The recorded sha is what later gives `ground-check` its
teeth: on every check it re-derives the hash and flags **STALE** if the source was edited after you
stamped it. Stamp *records*; ground-check *verifies* — never re-stamp at check time, or a later edit
could never be caught.

## 3. Ground (the gate)

```bash
node plugin/adapters/research/ground-check.js stamped.json sources/ --strict
```

`--strict` exits non-zero on any issue, so this is what you put on a research phase's gate. It proves
every excerpt is present in its source and every source still matches its stamped hash. Details and the
full issue taxonomy: [ground-research-claims.md](ground-research-claims.md).

## 4. Context (feed the writer)

Once the map is grounded, `research-context` renders one section's evidence — each claim's paraphrase,
cited source url, and verbatim excerpt — as the block handed to the writer through the generic Seam-2
`context_cmd` hook:

```bash
node plugin/adapters/research/research-context.js stamped.json background
# node-free twin:  python3 -m heartbeat.adapters.research.research_context stamped.json background
```

It renders **only that section's** claims (a `method` claim never leaks into the `background` block), so
each section is written against exactly the evidence that grounds it. This hands off to the
[docs-authoring](feed-code-context-to-stage-b.md) flow for ordering and to
[gated-docs](../../plugin/skills/gated-docs/SKILL.md) for prose integrity.

## It verifies grounding, not truth

None of this makes a claim *true*. `stamp-evidence` proves the hash is honest; `ground-check` proves the
quote is really in the source; `research-context` shows the writer that evidence. Whether the source is
correct, primary, or quoted in context is the **adversarial review's** job — a distinct-actor refuter
seeded by `node .hb/hb-audit.js .hb/dag.json --questions <gate>`. HeartBeat does not fetch for you and
does not fact-check; it makes the sourcing you did **reproducible and hard to fake**.

## Proof

Both bridges are backed by runnable proofs wired into the suite (T112/T113):

```bash
bash docs/howto/gate-examples/research-context.sh   # -> RESEARCH-CONTEXT-OK
bash docs/howto/gate-examples/stamp-evidence.sh     # -> STAMP-EVIDENCE-OK
```

`research-context.sh` asserts a section renders its own claims (with excerpts) and **not** another
section's, node ≡ python byte-identical. `stamp-evidence.sh` asserts the stamped sha is the real hash so
`ground-check` then reports GROUNDED, and that a later edit is caught as STALE — node ≡ python produce
the same map. Fuller design: [research-adapter-scope.md](../../planning/research-adapter-scope.md).
