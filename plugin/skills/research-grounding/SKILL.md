---
name: research-grounding
description: Verify that research/writeup claims are GROUNDED in stored sources — a verbatim excerpt is actually present in the fetched source (catching hallucinated citations and fabricated quotes) before the claims are used or written up. Use when you have gathered sources and a set of claims and want a deterministic, offline grounding check (the gate half of the research evidence lifecycle). NOT a web searcher and NOT a truth oracle — it checks grounding, not truth.
---

# Research-Grounding Skill (Claude Code)

<!-- HB-ADAPTER: research -->

The HeartBeat method accepts a code change only when it is backed by executable evidence and survives an
adversarial attempt to refute it. This adapter points that lifecycle at **facts**: a research claim is
provisional until it is **grounded** in a real, stored source — and (via the adversarial review) the
grounding survives a refuter. This skill is the **grounding gate**: the deterministic, offline half.

## When to use

- You have fetched sources and a set of claims (an *evidence map*) and want to catch **hallucinated
  citations**, **fabricated quotes**, **ungrounded** claims, and **stale** sources — before writing up.
- As the gate of a research phase, ahead of the `docs-authoring` adapter (ordering/context) and
  `gated-docs` (verifying the finished prose).

*Not* a web searcher (bring your own — the `deep-research` skill, `WebSearch`, an MCP server), and *not*
a judge of truth: it verifies that the stored source **says** the quote, not that the quote is **correct**.

## The evidence-map contract

```json
{
  "sources": { "s1": { "url": "https://…", "sha256": "…", "fetched": "…" } },
  "claims":  { "c1": { "text": "the paraphrased claim", "source": "s1",
                       "excerpt": "the verbatim supporting quote", "section": "background" } }
}
```

The extracted text of each source is stored at `<dir>/<source>.txt`; the `sha256` pins exactly what was
fetched. The **fetch is on-demand** (non-deterministic) — but from the stored snapshot on, the check is
**offline and reproducible**, which is what lets it gate.

## The method

1. **Ground-check the evidence map** (deterministic, no network):
   ```bash
   node plugin/adapters/research/ground-check.js evidence.json sources/
   # node-free twin:  python3 -m heartbeat.adapters.research.ground_check evidence.json sources/
   ```
   For each claim it reports `GROUNDED` or an issue — **FABRICATED-QUOTE** (excerpt not in the stored
   source), **UNGROUNDED** (undeclared source / no excerpt), **MISSING-SOURCE**, **STALE** (source edited
   since fetch, sha mismatch). Advisory by default; `--strict` blocks (exit 1 on any issue). Proof:
   [`gate-examples/ground-check.sh`](../../../docs/howto/gate-examples/ground-check.sh) (node-suite T110).
2. **Refute the grounding** (the adversarial half). The gate proves the quote is *real*; a distinct-actor
   refuter proves it *means what you say*: is the excerpt in context? is the source primary? is a
   contradicting source ignored? Seed it with `node .hb/hb-audit.js .hb/dag.json --questions <gate>`.
3. **Hand off** grounded claims to `docs-authoring` (order + write with the sources as context) and
   `gated-docs` (verify the finished prose).

## Boundary (hold this)

`ground-check` is a **parity surface** (node ≡ python — proof T111), **not core**, imports nothing from
core, and is **advisory**. It verifies **grounding, not truth**, and only ever reads the **stored**
snapshot (no live web in the gate). The web fetch that produces the evidence map is a separate,
on-demand step (see [research-adapter-scope.md](../../../planning/research-adapter-scope.md)).
