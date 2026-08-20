# Ground research claims against stored sources

An AI writeup's most dangerous failure is a **confident, ungrounded claim** — a hallucinated citation, a
quote the source never contained, or a source silently edited after you read it. HeartBeat's answer is
the same as for code: a claim is provisional until it is backed by **evidence** and survives an attempt
to **refute** it. The `research` adapter's `ground-check` is the deterministic gate half.

## The evidence map

You describe your claims and their sources in an *evidence map*, and store each source's text on disk:

```json
{
  "sources": { "s1": { "url": "https://…", "sha256": "…", "fetched": "…" } },
  "claims":  { "c1": { "text": "the paraphrased claim",
                       "source": "s1", "excerpt": "the verbatim supporting quote", "section": "background" } }
}
```

The source text lives at `<sourcesDir>/s1.txt`; the `sha256` pins exactly what was fetched.

## The check

```bash
node plugin/adapters/research/ground-check.js evidence.json sources/
# node-free twin:  python3 -m heartbeat.adapters.research.ground_check evidence.json sources/
```

For each claim it prints `HB-GROUND: grounded=<n> issues=<m>` then, per problem:

- **FABRICATED-QUOTE** — the `excerpt` (whitespace-normalized, so a line-wrapped quote still matches) is
  **not** present in the stored source. This catches an invented quote.
- **UNGROUNDED** — the claim cites a source that isn't declared, or has no excerpt at all.
- **MISSING-SOURCE** — the stored source file is gone.
- **STALE** — the stored source's sha no longer matches the recorded one: it changed since you fetched
  it, so the grounding can't be trusted. (The sha is checked *before* the excerpt, so an edit can't hide
  behind a quote that still happens to be present.)

Advisory by default (exit 0 — surface the issues); pass `--strict` to make it **block** (exit 1 on any
issue), e.g. as a gate on a research phase.

## The determinism boundary (why this can gate)

Fetching sources is non-deterministic (the web, a model). HeartBeat gates must be deterministic. So the
split is deliberate: the **fetch is on-demand** and produces a **stored snapshot**; from that snapshot on,
`ground-check` is **offline and reproducible** — no network in the gate — which is exactly what lets it
be a HeartBeat gate. It's the same pattern as the code adapter's live-CodeGraph read (on-demand) versus
its gated pure logic.

## It verifies grounding, not truth

`ground-check` proves the quote is **real** — that the stored source *says* it. It does **not** judge
whether the quote is correct or whether it actually *supports* the paraphrased claim; a well-grounded
claim can still cite a wrong or out-of-context source. That semantic judgement is the **adversarial
review's** job: a distinct-actor refuter asks *is the excerpt in context? is the source primary? is a
contradicting source ignored?* — seeded by `node .hb/hb-audit.js .hb/dag.json --questions <gate>`. The
gate and the refuter together are the research evidence lifecycle.

## Proof

The mechanism is backed by a runnable proof wired into the suite (T110):

```bash
bash docs/howto/gate-examples/ground-check.sh   # -> GROUND-CHECK-OK
```

It builds a fixture with a grounded claim, a fabricated quote, an ungrounded claim, and a tampered
(STALE) source, and asserts `ground-check` classifies each correctly and that `--strict` blocks. The
verifier is node ≡ python (T111). Fuller design: [research-adapter-scope.md](../../planning/research-adapter-scope.md).
