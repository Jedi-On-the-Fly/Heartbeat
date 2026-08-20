# Red-team a grounding corpus (prove the gate stays in its lane)

`ground-check` is a **deterministic gate**: it proves a claim's quote is really in its stored source. The
danger with any gate is that you start trusting it to do more than it does — here, to judge whether a
claim is *true*. It doesn't, and it mustn't pretend to. The way to keep that boundary honest is to
**red-team the corpus**: plant every failure mode, including ones the gate *cannot* catch, and assert it
catches exactly the mechanical ones and stays **silent** on the rest.

## The two kinds of failure

A claim can fail in two fundamentally different ways:

- **Mechanically** — the citation is fake, the quote isn't in the source, the source is gone, or the
  source was edited after you fetched it. These are *decidable offline*, and `ground-check` catches them:
  `FABRICATED-QUOTE`, `UNGROUNDED` (undeclared source / no excerpt), `MISSING-SOURCE`, `STALE`.
- **Semantically** — the quote is *real* but doesn't mean what the claim says: the paraphrase overreaches
  it, or it's a genuine quote lifted out of context from a non-primary source. These are **grounded** by
  every mechanical test, and no offline check can decide them. Judging them is the **adversarial
  review's** job.

A gate that tried to catch the second kind would be guessing at truth — exactly the confident-but-wrong
behaviour HeartBeat exists to distrust. So the design is deliberate: **the gate catches mechanical
fabrication and reports the semantic cases as `grounded`.**

## The red-team corpus

Build a fixture that plants one claim per failure mode, and — critically — at least one
**grounded-but-wrong** claim:

| Claim | Plant | Expected |
|---|---|---|
| `c_fab` | excerpt not in the source | `FABRICATED-QUOTE` |
| `c_nosrc` | cites an undeclared source | `UNGROUNDED` |
| `c_noex` | no excerpt at all | `UNGROUNDED` |
| `c_missing` | declared source, file never stored | `MISSING-SOURCE` |
| `c_stale` | recorded sha ≠ the file's bytes | `STALE` |
| `c_drift` | **real** excerpt, paraphrase overreaches it | **grounded** (gate silent) |
| `c_context` | **real** excerpt, non-primary source, out of context | **grounded** (gate silent) |

`c_stale`'s excerpt is deliberately still present in the file — so a pass here also proves the sha is
checked *before* the excerpt (an edit can't hide behind a quote that still matches).

## Close the semantic gap with a refuter

The two grounded-but-wrong claims are what the **distinct-actor review** exists for. Seed its questions
from the gate's own criteria:

```bash
node .hb/hb-audit.js .hb/dag.json --questions <gate>
```

and ask a refuter (a different actor than the writer): *is the excerpt in context? does it actually
support the paraphrase? is the source primary, or a blog stripping the caveats?* A refuter that reads the
red-team corpus should independently flag `c_drift` and `c_context` — the ones the gate passed. That is
the boundary demonstrated from both sides: the gate catches what's decidable, the review catches the
rest. It verifies **grounding, not truth**.

## Proof

The corpus and the boundary are backed by a runnable proof wired into the suite (T114):

```bash
bash docs/howto/gate-examples/ground-check-redteam.sh   # -> RED-TEAM-OK grounded=3 issues=5
```

It asserts every mechanical mode is classified correctly, that `c_drift` and `c_context` are **not**
flagged (the gate stays silent on truth), and that `ground-check` is node ≡ python on the red-team
corpus. Its teeth: it characterizes the real `ground-check`, so a regression that over- or under-flags —
or one that starts judging truth — turns it red. Related: [ground-research-claims.md](ground-research-claims.md).
