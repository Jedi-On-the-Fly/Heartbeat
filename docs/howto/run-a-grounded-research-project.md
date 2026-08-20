# Run a grounded research project end-to-end

A worked walk-through of the research adapter's full loop — **source → stamp → ground → refute →
write** — on a tiny two-claim example. It ties together the three deterministic bridges
([`stamp-evidence`](source-and-ground-research.md), [`ground-check`](ground-research-claims.md), and
[`research-context`](source-and-ground-research.md)) with the adversarial review, so you can see how a
writeup earns acceptance instead of asserting it. For the concept, see the
[research-grounding](../../plugin/skills/research-grounding/SKILL.md) skill.

## The scenario

You're writing a short "Background" section that makes two claims about water's phase transitions, and
you want each claim grounded in a real, stored source before a word of prose is written.

## 1. Source (on-demand)

Search — with the `deep-research` skill, `WebSearch`, or an MCP server — read a source, and drop its
extracted text into a file. Say you keep one page and save its text to `sources/s1.txt`:

```
At one atmosphere of pressure, water boils at 100 degrees Celsius
at sea level, and freezes at zero degrees Celsius.
```

Then write the evidence map — sources and claims — but leave the hashes unset (you haven't stamped yet):

```json
{
  "sources": { "s1": { "url": "https://example.org/thermo" } },
  "claims": {
    "c_boil":   { "text": "Water boils at 100°C at sea level.", "source": "s1",
                  "excerpt": "water boils at 100 degrees Celsius at sea level", "section": "background" },
    "c_freeze": { "text": "Water freezes at 0°C.",  "source": "s1",
                  "excerpt": "freezes at zero degrees Celsius", "section": "background" }
  }
}
```

Nothing here is trusted yet — the shas aren't filled in and no quote is verified. That's the point of the
next three steps.

## 2. Stamp the honest hashes

```bash
node plugin/adapters/research/stamp-evidence.js evidence.json sources/ > stamped.json
```

`stamp-evidence` recomputes `s1`'s sha256 from the **stored bytes** and writes it into `stamped.json`. An
agent can no longer fake a hash: the recorded sha is exactly what's on disk, and it's what lets the next
step detect a later edit.

## 3. Ground-check (the gate)

```bash
node plugin/adapters/research/ground-check.js stamped.json sources/ --strict
```

```
HB-GROUND: grounded=2 issues=0
```

Both excerpts are present in the stored source (whitespace-normalized, so the line-wrapped
"water boils at 100 degrees Celsius / at sea level" still matches) and the sha matches — so `--strict`
exits 0. Had you invented a quote, you'd get `FABRICATED-QUOTE`; had the source been edited after
stamping, `STALE`. This is the command you put on a research phase's gate.

## 4. Refute (the adversarial half)

Grounding proves the quote is *real*, not that it's *right*. A distinct-actor refuter now asks the
questions the gate can't — is the excerpt in context? is the source primary? is a contradicting source
ignored? Seed those questions from the gate itself:

```bash
node .hb/hb-audit.js .hb/dag.json --questions GATE_BACKGROUND
```

The reviewer records `hb review GATE_BACKGROUND pass --artifact <file>` only if it cannot refute the
grounding — the same acceptance bar HeartBeat uses for code.

## 5. Write

Now hand the writer exactly the evidence that grounds this section:

```bash
node plugin/adapters/research/research-context.js stamped.json background
```

```
Grounded evidence for background:
  - c_boil: Water boils at 100°C at sea level.
    source s1 https://example.org/thermo
    » water boils at 100 degrees Celsius at sea level
  - c_freeze: Water freezes at 0°C.
    source s1 https://example.org/thermo
    » freezes at zero degrees Celsius
```

Only the `background` claims appear — a `method`-section claim would never leak in — so the section is
written against exactly its own grounded evidence. From here `docs-authoring` handles ordering/context
and [gated-docs](../../plugin/skills/gated-docs/SKILL.md) verifies the finished prose.

## What you did and didn't prove

You proved the shas are honest, the quotes are really in the sources, and the writer saw only grounded
evidence — all reproducible offline. You did **not** prove the sources are correct or unbiased; that
stays the refuter's judgment. HeartBeat didn't fetch or fact-check for you — it made the sourcing you did
**hard to fake and easy to re-verify**.

Each bridge is backed by a wired proof: `ground-check.sh` (T110), `research-context.sh` (T112), and
`stamp-evidence.sh` (T113) under [`docs/howto/gate-examples/`](gate-examples/).
