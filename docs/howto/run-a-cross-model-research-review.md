# Run a cross-model research review (a different model refutes your grounding)

The research adapter's deterministic gate (`ground-check`) is **mechanical**: it proves every quote is
really in a stored source and the source hasn't changed. It says nothing about whether the quote is *in
context*, *from a primary source*, or actually *supports* the paraphrase. That judgment is the
adversarial review's job — which means the review is where the research loop's **semantic** verification
actually lives, and it's only as good as the reviewer. This guide wires that review to a **different
model** than the one that wrote the claims, because a model is poor at spotting its own blind spots.

It composes two things you already have: the [grounded research loop](run-a-grounded-research-project.md)
and [cross-model verification](cross-model-verification.md). Read those first; this joins them.

## The loop

```
source → stamp → ground   (deterministic, mechanical — the doer)
        → refute          (semantic — a DISTINCT model, seeded by hb-audit --questions)
        → write
```

### 1. Doer: build the grounded evidence, mechanically verified

Exactly the [grounded loop](run-a-grounded-research-project.md): search, store each source's text, then

```bash
node .hb/hb-audit.js .hb/dag.json --questions GATE_BACKGROUND   # (used in step 2)
node plugin/adapters/research/stamp-evidence.js evidence.json sources/ > stamped.json
node plugin/adapters/research/ground-check.js stamped.json sources/ --strict
```

`--strict` is the gate: a fabricated quote or an edited source blocks here. What survives is *grounded*,
not *true*.

### 2. Refuter: a different model attacks the grounding

Put a `review` block on the research phase's gate (see
[add-refutation-to-a-sensitive-gate.md](add-refutation-to-a-sensitive-gate.md)), then drive the project
with the executor configured so the **refute** call runs on a distinct model:

```bash
# doer writes with one local model; a different local model refutes
HB_EXEC_BACKEND=ollama HB_EXEC_MODEL=llama3.1:8b \
  HB_REFUTE_MODEL=qwen2.5:7b-instruct \
  node .hb/hb-exec.js run
```

or pin it per project in `.hb/executor.json`:

```json
{ "backend": "ollama", "model": "llama3.1:8b", "refute_model": "qwen2.5:7b-instruct" }
```

On `review_pending`, the executor dispatches the refute call on the distinct refute model with the
gate's authored `review.prompt`. To make that prompt attack the *right* weaknesses, seed it from the
gate's own criteria: the `hb-audit --questions` you ran in step 1 derives the falsification questions —
for grounding claims exactly the semantic ones the gate can't decide (*is the excerpt in context? is the
source primary? is a contradicting source ignored?*) — and you fold them into the gate's `review.prompt`
when you author it (the executor passes that prompt through; it does not call `--questions` itself). The
refuter runs under a **distinct actor**, and the stored review artifact (`.hb/reviews/<gate>.attempt.md`)
records *which* model produced it — so a pass is traceable to the model that couldn't break the
grounding. With no `HB_REFUTE_*` set, the doer refutes itself (today's default) — which is the weak case
this guide exists to fix.

### 3. Write

Only claims that are both grounded and survive the cross-model refutation feed the writer via
`research-context` (see the [grounded loop](run-a-grounded-research-project.md)).

## What this does and doesn't buy you

- **Does:** move the semantic check off the author and onto a model with *different* failure modes, seeded
  by questions derived from the gate — not left to prompt luck.
- **Doesn't:** guarantee truth. Grounding is mechanical; the refutation is *a* judgment, not *the* answer.
  Whether a second model actually catches more is a property of the models you pick, not something the
  harness benchmarks for you — pick a refuter that fails differently from your doer. See the honest scope
  note in [cross-model-verification.md](cross-model-verification.md) and the backend menu in
  [choose-a-backend.md](choose-a-backend.md).

## Proofs

The two mechanisms this guide joins are each backed by a wired proof:

```bash
bash docs/howto/gate-examples/cross-model-refuter.sh   # -> CROSS-MODEL-REFUTER-OK  (T73: distinct backend/model refutes, provenance)
bash docs/howto/gate-examples/ground-check.sh          # -> GROUND-CHECK-OK         (T110: mechanical grounding)
```

What they prove is the **routing, distinctness, provenance, and mechanical grounding** — deterministically,
with no model. The *value* of a distinct model catching more is inherent to model diversity, as noted above.
