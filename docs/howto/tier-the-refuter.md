# Tier the refuter (economy without weakening the adversary)

Refutation is where HeartBeat spends its most expensive tokens — and by default an
interactive host spawns every refuter on the session's model, usually the strongest one you
have. That is often the wrong default *in both directions*: a gate-checklist review (an
explicit brief — run this, grep that, report what broke) is exactly the job a cheaper model
does well, while reading a *plan* critically is where the strong model earns its keep. The
refuter profile is where that economy is declared, once, per lens.

## Do it

Bind a model to the profile a gate's review selects:

```bash
cat .hb/refuters/correctness.json
# { "persona": "…", "questions": ["…"], "model": "sonnet" }
```

That one field routes **both** refute surfaces:

- **Automated** (`hb exec run`): the executor dispatches the refute on the profile's
  model/provider — the cross-model path (T147).
- **Interactive** (a host spawning a refuter agent): read the machine-readable binding and
  pass it to your agent-spawning tool —
  ```bash
  hb refute-prompt <GATE> --json     # → {"prompt": …, "model": "sonnet", "provider": null, "panel": null, "refute_if": null}
  ```
  Spawn the refuter on `.model`; inherit the session model only when it is `null`. Then
  **record what reviewed** with the verdict:
  ```bash
  hb review <GATE> pass --artifact <findings-file> --model sonnet
  hb review <GATE> fail "<holes>" --model sonnet
  ```

## Hosts other than Claude Code (Codex, OpenCode, anything driving over MCP)

The `--json` binding is host-neutral data; whether an *interactive* host can act on it
depends on whether its agent-spawning tool takes a model parameter. Where it can't, use the
path that works on every host because HeartBeat controls it itself: the **automated exec
refute**. The executor's dispatch exports the resolved profile model as `HB_EXEC_MODEL`
for the refute call, and the `codex` / `opencode` backends pass it straight through as
`-m <model>` — so

```bash
HB_REFUTE_BACKEND=codex hb exec run --dir <project>     # refutes run on codex, doer unchanged
```

routes reviews to a different CLI agent *and* honors the profile's model, with the verdict
auto-stamped. That is also the strongest form of tiering: a different **vendor**, not just
a smaller sibling — capability diversity and economy in one move.

## Route by review kind, not by price alone

- **Plan refutation** (`hb audit --agent`, or refuting a DAG before it runs) is critical
  design reading — keep it on the strong model.
- **Gate-checklist reviews** (post-build `review_pending` on a phase gate) carry an explicit
  falsification brief composed from the gate's own criteria — a focused, cheaper model with a
  different failure profile is often *more* adversarial per token. Bind it on the
  `correctness`/`security` profile and leave `default` unbound for the gates that warrant
  the strong model.

## Verify the routing took effect — observe, don't guess

The review event records the model (`null` when unknown — honest, never fabricated), and
`hb report` breaks refuter impact down per model — a `· <model>: caught N, cleared M` line
under each gate's lens (nulls bucket under `(none)`; the same breakdown is in
`hb report --json` under `refuters.gates[].models`). After a few reviews, the log answers
the only question that matters: *is the cheaper refuter catching anything?* Catches are
counted from truth (a `review_failed` is a real catch); misses are invisible by definition.

## Honest limit

Four limits, all load-bearing:

1. **Cheaper is not automatically differently-failing.** Cross-model refutation earns its
   keep when the refuter *fails differently* from the doer
   ([cross-model-verification.md](cross-model-verification.md)); a smaller model can be a
   subset-failing one — cheaper *and* blinder.
2. **Watch the per-model impact report before trusting a downgrade.** If the cheap lens
   stops catching, that is not evidence the work got better.
3. **Never downgrade to make a pass cheaper to obtain.** A refuter chosen because it finds
   less is the auto-weaken move by another name.
4. **The model field has a trust boundary — it is a self-report on the interactive and MCP
   paths.** Only the exec auto-stamp is config-derived from the resolved profile; an
   interactive `--model` is the recording actor's claim. Treat per-model impact from
   interactive runs as bookkeeping, not evidence. (Token counts are not recorded at all,
   for the same reason: HeartBeat cannot observe them.)

Deliberately deferred, so the limit is loud: interactive **panel fan-out** (`--json` emits
`panel` and `refute_if` so a host *can* aggregate, but nothing instructs N spawns yet) and
**`audit --agent` model routing** (plan refutation stays on the strong model by convention;
its spend is outside the impact report).

This guide pairs with [spend-the-model-only-on-work.md](spend-the-model-only-on-work.md):
that one is about *when* a model runs; this one is about *which*.

## Proof

Both mechanisms are wired into the suite and were refuted before shipping:

```bash
bash docs/howto/gate-examples/refuter-model-routing.sh      # -> REFUTER-MODEL-ROUTING-OK  (T163: --json binding, one-compose byte pins, spawn+record instructions)
bash docs/howto/gate-examples/refuter-model-provenance.sh   # -> REFUTER-PROVENANCE-OK    (T164: model recorded — flag/null/auto-stamp/MCP — per-model impact node ≡ python)
```

Their build history is the argument in miniature: both phases' gate reviews ran on a
profile-bound cheap model, which caught two real defects (a flag-order parse divergence and
a provenance-fabrication hole) that were fixed at the root and pinned red-first. The
impact trail is honest about its own bootstrap: the *first review cycle* predates the
`--model` flag, so its catch and clearing pass sit in the `(none)` bucket — the ordering
debt, visible in the log — while every later verdict is stamped. That unstamped first entry is the feature's own argument for why
the field exists.
