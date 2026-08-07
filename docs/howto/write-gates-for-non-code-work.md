# Write gates for non-code work

Gates are not only for code. A phase can produce a document, a dataset, a config, a
migration — and the same discipline applies: assert the deliverable actually carries its
*content*, not that a file appeared. The failure mode is identical to `test -f`, just
dressed up: gating a report on a heading that exists, or a dataset on the file being
non-empty.

## The move

Ask: *what would a lazy worker hand in that still passes a weak check?* A report with the
right headings but `TODO` bodies. A CSV that is a header and no rows. A config that parses
but has the placeholder value. Then write the gate that **rejects that stub**.

- **Documents** — extract the section that must carry the decision and assert it has real
  content (non-empty, no `TODO`/placeholder). Not "the file mentions Recommendation."
  → [non-code-doc](gate-examples/non-code-doc/)
- **Datasets** — parse it and assert the *shape*: the expected columns/keys, a non-zero row
  count, values that satisfy the invariant (an email has an `@`, a total reconciles). Not
  "the file is non-empty." → [non-code-data](gate-examples/non-code-data/)
- **Migrations / transforms** — assert the outcome reconciles: row counts match, no orphans,
  a spot-checked record round-trips. Not "the script exited 0."

## Keep it behavioral

The same rules hold: [deterministic and fast](write-fast-deterministic-gates.md), read-only,
this-phase's artifact. Parsing a document or dataset in the gate is fine as long as it is
bounded and local. When the judgement is genuinely subjective (is the prose *good*?), that
is a job for [refutation](add-refutation-to-a-sensitive-gate.md) — a second actor argues the
deliverable isn't done — not for a deterministic string match pretending to measure quality.

## Proof

Both examples are proven by the shared runner (a weak gate is fooled by the stub; the
behavioral gate rejects the stub and accepts real content):

```bash
bash docs/howto/gate-examples/run.sh   # non-code-doc and non-code-data among ALL-EXAMPLES-PROVEN
```
