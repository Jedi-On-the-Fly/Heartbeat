# Scope: the research / grounding adapter

**Status:** scope / design. Not built. This is the design for the missing *front half* of the
docs/research adapter — turning a research question into a **grounded** corpus before the existing
docs-authoring adapter orders and writes it.

A doc is a claim; a *research* doc is a claim about the world. HeartBeat already accepts a code change
only when it is backed by executable evidence and survives an adversarial attempt to refute it — this
adapter points that same lifecycle at **facts**: a research claim is accepted only when it is backed by
a real, stored source that actually supports it and survives a refuter trying to break the grounding.

## Why — the gap

The docs adapter (`plugin/adapters/docs/`) assumes the corpus already exists: it reads a folder of
`.md` sections, derives the citation graph (ordering) and the cited-section context. For *research*,
the hard, error-prone part is everything **before** the corpus:

1. **Sourcing** — search the web, fetch sources, decide what to write about.
2. **Grounding** — make sure every claim is actually supported by a real source, not hallucinated,
   misquoted, cherry-picked, or stale.

(1) is non-deterministic and already served by existing tools (the `deep-research` skill, `WebSearch`/
`WebFetch`, MCP search servers). (2) is exactly what HeartBeat's gates + adversarial review are for, and
nothing ships it today. **This adapter is (2): the verification harness around research, not a search
engine.**

## The core idea — grounding as an evidence lifecycle

Split every research claim into two verifications, mirroring HeartBeat's deterministic-gate + adversarial-
review model exactly:

- **Deterministic (the gate):** the claim cites a source, and a *verbatim excerpt* from that source is
  physically present in the **stored** copy of the source. This catches a hallucinated citation and a
  fabricated quote — offline, re-checkable, fast. It does NOT judge meaning.
- **Adversarial (the refutation):** a distinct-actor agent tries to break the grounding — does the
  excerpt genuinely *support* the paraphrased claim, or is it out of context? Is the source primary /
  authoritative, or circular? Is there a contradicting source that was ignored? Is it current?

The gate proves the quote is real; the refuter proves the quote means what you say. Neither alone is
enough — which is why HeartBeat needs both, and why research needs both.

## The determinism boundary (the key constraint)

HeartBeat gates must be deterministic (`hb-audit` flags network/time as `nondeterministic`). The web
fetch cannot gate. We reuse the established **harness-first** split (CodeGraph's live DB read, the
ollama runs):

| Phase | Deterministic? | Gated? | Artifact |
|---|---|---|---|
| **Fetch** (search + pull sources) | no (network, LLM) | **no** — on-demand | stored source text + sha256 |
| **Ground** (verify excerpt ⊆ stored source) | **yes** (offline string check) | **yes** | the evidence map |
| **Refute** (excerpt supports claim? in context?) | no (a mind) | via `review` block | a stored refutation artifact |

The fetch produces a **stored artifact** (`.hb/sources/<id>.txt` + a sha256); from there everything the
gate checks is offline and reproducible. This is identical in spirit to `real-codegraph-map.sh` (live,
on-demand) vs the gated pure mapping.

## The evidence-map contract

The research analog of the `codemap` — a narrow, provider-neutral contract any searcher can emit:

```json
{
  "sources": {
    "s1": { "url": "https://…", "title": "…", "sha256": "…", "fetched": "2026-08-20T…Z" }
  },
  "claims": {
    "c1": {
      "text": "The paraphrased claim as it will appear in the writeup.",
      "source": "s1",
      "excerpt": "the verbatim supporting quote copied from s1",
      "section": "background"
    }
  }
}
```

- The extracted plain text of each source is stored at `<project>/.hb/sources/<sourceId>.txt`; the
  `sha256` pins exactly what was fetched (provenance + rot detection).
- `claims[c].section` bridges to the docs adapter: a claim belongs to the section that makes it, so a
  section's Seam-2 context can carry its claims' sources + excerpts.
- A research writeup therefore has **two graphs**: the *citation* graph (section→section, from
  `docs-map`, gives ordering) and the *evidence* graph (claim→source, from this adapter, gives grounding).

## The grounding gate + the refutation

**Grounding verifier** (`ground-check`, a code-adapter-style provider, node ≡ python):

```
node plugin/adapters/research/ground-check.js <project>/evidence.json <project>/.hb/sources
```

For each claim it asserts, deterministically and offline:
- the claim names a `source` that exists in `sources`, and its stored text file is present;
- the `excerpt` (whitespace-normalized) is a substring of the stored source text (no fabricated quote);
- no claim is ungrounded (missing source/excerpt).

Advisory by default; `--strict` blocks a gate (like `deplint-accept`). Reports `UNGROUNDED`,
`FABRICATED-QUOTE` (excerpt not in source), `STALE` (sha mismatch on re-fetch). `hb doctor` treats a
deleted/edited source as **rot** (the grounding can no longer be reproduced) — the same rot machinery
that guards deleted gate files.

**Refutation** — a review-gated research phase spawns a distinct-actor agent whose falsification
checklist is *generated* (reusing `hb-audit --questions`, seeded with source-specific checks):
*does the excerpt support the claim or is it out of context? is the source primary? is there a
contradicting source? is it current?* The claim isn't accepted until the refuter fails (`hb review pass`
with the stored refutation artifact — the exact mechanism already shipped).

## What's reused vs what's new

**Reused (most of it already exists):**
- **Fetching** — the `deep-research` skill / `WebSearch` + `WebFetch` / an MCP search server. We
  orchestrate a searcher; we do not build one.
- **Evidence provenance** — the `gate_passed` event already records `{commit, criteria, runtime}` and
  `hb evidence` reads it; grounding provenance (source, sha, fetch date) is the same pattern.
- **Falsification questions** — `hb-audit --questions <gate>` already generates "how could this FALSELY
  pass?"; extend with source-lens checks to seed the refuter.
- **Adversarial review** — the refutation *is* the existing distinct-actor `review` block + artifact.
- **Ordering + context** — the `docs-authoring` adapter (`docs-map` + `docs-context` + `discover`).
- **Prose verification** — the `gated-docs` skill verifies the finished prose's *how-it-behaves* claims.

**New (the real work):**
- The **evidence-map contract** + a **grounding provider** (fetch→store→emit `evidence.json`, on-demand).
- The **grounding verifier** `ground-check` (deterministic, offline, node ≡ python) + its `doctor` rot hook.
- The **claim→section bridge** so grounded sources flow into docs-authoring's Seam-2 context.
- The **research skill** that runs the whole loop (search → ground → refute → hand off).

## Composition — the three-stage research pipeline

Each stage is a HeartBeat phase; a claim/section is provisional until all three agree:

1. **Source & ground** (this adapter) — search, store sources, emit `evidence.json`; gate =
   `ground-check` (every claim's quote is real); refute = a skeptic attacks the grounding.
2. **Order & write** (`docs-authoring`) — `docs-map` gives the section order; each section is authored
   with its cited sections + grounded excerpts as context; `discover` gives change-impact on revision.
3. **Verify the prose** (`gated-docs`) — the finished sections' claims are backed by runnable proofs /
   prose-integrity and refuted before they ship.

## Proof strategy (how the adapter itself is gated, spec-first)

- **Grounding verifier**: fixtures — an `evidence.json` + `.hb/sources/` where one claim is grounded,
  one has a fabricated quote (excerpt NOT in source), one is ungrounded. Gate: `ground-check` reports
  exactly those; node ≡ python byte-identical. (Deterministic, no network.)
- **Rot**: delete/edit a stored source → `doctor` flags it.
- **Fetch path**: harness-first (`real-research-fetch.sh`) — skips cleanly without network/searcher;
  proves the provider stores a source + sha and emits a valid evidence map. Never gates the suite.
- **Refutation seeding**: `hb-audit --questions` emits source-lens questions for a research gate.

## Sequencing (phases, when built)

1. **GR — grounding core**: evidence-map contract + `ground-check` verifier (node ≡ python) + fixtures +
   gated proof + `doctor` rot hook. Deterministic; no network.
2. **SB — the sourcing bridge**: on-demand provider that drives a searcher → stores sources → emits
   `evidence.json`; harness-first proof; the claim→section bridge into docs-context.
3. **RS — the research skill + refutation**: the skill that runs search→ground→refute→hand-off, with
   generated falsification questions; a worked end-to-end example.

## Non-goals

- **Not a search engine / not a truth oracle.** It verifies *grounding* ("the stored source says X"),
  not *truth* ("X is true in the world"). A well-grounded claim can still cite a wrong source — that's
  the refuter's and the human's job, and the doc must say so.
- **Not real-time web gating.** The gate checks stored snapshots, never the live web.
- **Not a citation-format tool.** It's about evidence, not reference styling.

## Risks & open questions

- **Excerpt matching brittleness** — whitespace/smart-quotes/HTML entities differ between fetch and
  quote. Needs normalization (the `js_trim` discipline: node ≡ python, byte-exact) and probably a
  normalized-substring match, not raw. Open: how lenient before it stops catching fabrication.
- **Paraphrase vs quote** — the claim paraphrases; the *excerpt* must be verbatim. The gate checks the
  excerpt is real; only the refuter checks the paraphrase is faithful. Keep that division sharp.
- **Source drift** — a URL's content changes after fetch; the stored text + sha is the source of truth,
  and a re-fetch mismatch is a `STALE` finding, not a silent pass.
- **Searcher coupling** — keep the evidence-map contract provider-neutral so the searcher (deep-research
  skill, MCP, manual) is swappable, exactly as CodeGraph is one of many possible codemap providers.
- **Scope creep** — resist building extraction/summarization into core; those are model-driven and
  belong in the on-demand provider, with the deterministic gate checking only the mechanical fact.

## Reference

Composes with: [adapters.md](../docs/adapters.md) · [docs adapter](../plugin/adapters/docs/README.md) ·
[build-a-domain-adapter.md](../docs/howto/build-a-domain-adapter.md) (§7 hard-won lessons apply directly:
prove against the real fetch, denylist > allowlist on source forms, absence ≠ negative, exclude noise).
Reuses: gate evidence provenance (`hb evidence`), `hb-audit --questions`, the `review` block, and
`gated-docs`.
