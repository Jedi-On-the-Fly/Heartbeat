# Cross-model verification (a different model refutes)

HeartBeat's adversarial review already runs the refuter under a **different actor** than the doer
([add-refutation-to-a-sensitive-gate.md](add-refutation-to-a-sensitive-gate.md)). This lets you go
one step further: run the refuter on a **different model** too. A model is good at producing reasons
its own work is done — it shares its own blind spots. A *different* model, asked to refute, doesn't.

Because `execute` and `refute` are separate backend methods, the refuter is just a second backend
call — so you can point it at another model, provider, or command. It's opt-in: every setting falls
back to the doer's, so leaving it unset changes nothing.

## Configure it

Set any of these (env, or the `refute_*` keys in `.hb/executor.json`); the executor uses them only
for the `refute` call:

| Setting | Effect |
|---|---|
| `HB_REFUTE_BACKEND` | the refuter's backend (e.g. doer `codex`, refuter `claude-code`) |
| `HB_REFUTE_MODEL` | the refuter's model (same backend, different model — e.g. doer `ollama/llama3.1:8b`, refuter `ollama/qwen2.5:7b-instruct`) |
| `HB_REFUTE_PROVIDER` | the refuter's provider |
| `HB_REFUTE_CMD` | a raw refuter command (the script wire) |

```bash
# doer = codex; refuter = a different vendor
HB_EXEC_BACKEND=codex  HB_REFUTE_BACKEND=claude-code  hb exec run --dir <project>

# same backend, two local models
HB_EXEC_BACKEND=ollama HB_EXEC_MODEL=llama3.1:8b \
  HB_REFUTE_MODEL=qwen2.5:7b-instruct           hb exec run --dir <project>
```

`hb exec config` prints the resolved refuter settings (both runtimes).

## What it keeps

- **Distinct actor.** The review pass is still recorded under a refuter identity distinct from the
  doer, so the self-review guard holds ([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md)) — a
  model can't pass its own homework even if it's the same backend.
- **Provenance.** The stored refutation artifact (`.hb/reviews/<gate>.attempt.md`) records *which*
  refuter produced it, so a pass is traceable to the model that couldn't break it.
- **Backward compatible.** With none of the `HB_REFUTE_*` set, the refuter is the doer — exactly
  today's behavior.

## Proof, and an honest scope note

[`gate-examples/cross-model-refuter.sh`](gate-examples/cross-model-refuter.sh) proves the mechanism
deterministically (a doer stub + a *distinct* refuter stub, no model): the refuter — not the doer —
produces the stored review, under a distinct actor, with provenance and the model override reaching
the refute call; and without a distinct refuter, the doer refutes (backward compat). Both runtimes.

What that proves is the **routing, distinctness, and provenance**. Whether a second model actually
*catches more* is inherent to model diversity — real, but a property of the models you pick, not
something this harness benchmarks for you. Pick a refuter that fails differently from your doer.

The economic complement — binding a *cheaper* model per refuter profile, routing by review kind,
and reading the per-model impact before trusting a downgrade — is
[tier-the-refuter.md](tier-the-refuter.md).

See [choose-a-backend.md](choose-a-backend.md) for the backend menu.
