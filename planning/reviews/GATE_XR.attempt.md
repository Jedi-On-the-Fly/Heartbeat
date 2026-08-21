# Refutation attempt — phase XR

**Claim under review (XR):** a new worked how-to `docs/howto/run-a-cross-model-research-review.md`
ties the cross-model distinct-actor refuter to the research adapter end-to-end (grounded writeup → a
DISTINCT model refutes, seeded by `hb-audit --questions` → distinct-actor provenance), composing
already-proven mechanisms, honest about limits, without duplicating `cross-model-verification.md`.

Refuter actor: adversarial reviewer (distinct from author). Evidence below is from reading the code
and running the suites, not assertion.

---

## What holds up (could not break)

- **Files, links, listing.** The how-to exists. All seven relative links resolve on disk:
  `cross-model-verification.md`, `run-a-grounded-research-project.md`, `ground-research-claims.md`,
  `add-refutation-to-a-sensitive-gate.md`, `choose-a-backend.md`, and the two gate-examples
  (`gate-examples/cross-model-refuter.sh`, `gate-examples/ground-check.sh`). It is listed in
  `docs/howto/howto-list.md:43` (tagged T73/T110).
- **Command signatures are real and correct.**
  - `plugin/adapters/research/stamp-evidence.js <evidence.json> <sourcesDir>` — matches (usage line 11,
    stdout JSON line 34).
  - `plugin/adapters/research/ground-check.js <stamped.json> <sourcesDir> [--strict]` — matches; `--strict`
    exits 1 iff issues (`ground-check.js:59,65`).
  - `plugin/templates/hb-audit.js --questions <gate>` — real (`hb-audit.js:130-131`,
    `reviewQuestions` exported line 142; Python parity `audit.py:60`, `cli.py:40,113-114`).
- **Executor config resolves as documented.** `HB_EXEC_BACKEND` / `HB_EXEC_MODEL` and the refute
  overrides both resolve: `HB_REFUTE_MODEL` env AND `.hb/executor.json` `refute_model` at
  `hb-exec.js:87` (`process.env.HB_REFUTE_MODEL || file.refute_model || null`); the model override
  reaches the refute dispatch via `refExtra.HB_EXEC_MODEL` (`hb-exec.js:342`). `node .hb/hb-exec.js run`
  is a real subcommand (`hb-exec.js:400,403`). The stored artifact path `.hb/reviews/<gate>.attempt.md`
  is correct (`HB_DIR/reviews/<gate>.attempt.md`, `hb-exec.js:365-368`), and provenance (`refuterId`,
  including `model=`) is written into it (line 368) — distinct-actor pass via `hbAs(refuterActor, ...)`
  (line 369).
- **Honest about limits — no overclaim on model efficacy.** The guide explicitly does NOT claim the
  harness proves a second model catches more: "Whether a second model actually catches more is a
  property of the models you pick, not something the harness benchmarks for you" (lines 71-73, echoed
  in Proofs 85-86). It correctly states grounding is mechanical and grounding≠truth ("What survives is
  *grounded*, not *true*", line 32; "grounding is mechanical", line 70). It correctly states the weak
  default: "With no `HB_REFUTE_*` set, the doer refutes itself (today's default)" (lines 58-59) — which
  matches the fallback at `hb-exec.js:71-73,87` and the T73 backward-compat control.
- **Not a duplicate.** It adds the research-loop worked example (source→stamp→ground→refute→write) that
  `cross-model-verification.md` does not contain; it cross-links that guide and the grounded-loop guide
  rather than restating them (lines 10-11, 73). `cross-model-verification.md` is config-reference; this
  is the research-loop application. Distinct.
- **Proofs run and print their markers.**
  `bash docs/howto/gate-examples/cross-model-refuter.sh` → `CROSS-MODEL-REFUTER-OK` (exit 0).
  `bash docs/howto/gate-examples/ground-check.sh` → `GROUND-CHECK-OK` (exit 0). Both match the guide.
- **Gates green.** `prose-check.sh run-a-cross-model-research-review.md` → `ALL-PROSE-OK:1`. Full node
  suite `bash tests/run-tests.sh` → **334 passed, 0 failed**, incl. T93 (whole-docs prose), T81
  (self-audit), T92 (skill-integrity), T73, T110. Python: 96 passed. Parity: `PARITY OK — node ≡ python`.

## The hole (why this is REFUTED, not rubber-stamped)

**The guide misattributes the `--questions` seeding to the automated executor — a claim the code does
not implement.** Step 2, lines 53-55:

> "On `review_pending`, the executor seeds the refuter with the falsification questions
> `hb-audit --questions` derives from the gate's own criteria…"

This is false as written. The executor's `review_pending` handler dispatches the refute with
`prompt: rv.prompt || \`Refute that ${gate} is truly complete.\`` (`hb-exec.js:348-350`), where
`rv.prompt` is the DAG-authored review block's own prompt. It never calls `reviewQuestions` /
`hb-audit --questions`, never reads its output, and never injects it into the refute payload. A global
search confirms `reviewQuestions`/`review_questions` is reachable **only** via the `--questions` CLI
flag (`hb-audit.js:130-131`, `cli.py:113-114`) — no runtime executor path invokes it. Nothing
pre-populates `review.prompt` from questions either (no template DAG carries it; `dag.schema.json` only
declares the field).

The `--questions` seed is a **PROTOCOL instruction to whoever authors/drives the review**, not an
executor action: `protocol.py:11` `review_pending` reads "seed it with `hb audit --questions <gate>`."
The guide's own step 1 correctly runs `hb-audit.js --questions GATE_BACKGROUND` as a **manual** step
("used in step 2") — then step 2's prose contradicts that by handing the same action to "the executor"
automatically. So the guide is internally inconsistent and, in the one mechanism it is specifically
about, describes automated behavior that does not exist.

This is not a nitpick: the phase claim itself is "…seeded by hb-audit --questions…" as an end-to-end
tie. The tie is real only if a human/agent seeds the DAG's `review.prompt` from the questions; the
executor does not do it. The sibling `cross-model-verification.md` (the proven guide) makes **no**
such seeding claim — the new guide introduced an unbacked one. The fix is a one-clause correction
(attribute the seeding to the review author per the protocol, or state the doer must put the
`--questions` output into the gate's `review.prompt`), not a structural rewrite — but as written the
guide asserts behavior the code contradicts, which fails AGENTS.md rule 7 ("A doc is a claim").

## Note (not part of the verdict)

Untracked in tree at review time (pre-existing, not mine): `docs/howto/run-a-cross-model-research-review.md`,
` M docs/howto/howto-list.md`, `planning/pre-push-and-cross-model.dag.json`. I left the tree as I found
it (only this attempt file added).

VERDICT: REFUTED

---

# Re-review — phase XR (2026-08-21)

The single hole from the first pass (step 2 misattributing the `--questions` seeding to the
automated executor) was the reason for REFUTED. Re-reading the corrected step 2
("### 2. Refuter", `run-a-cross-model-research-review.md:34-62`) against the code:

## The hole is fixed

- **Executor dispatch is now stated correctly.** The doc says: "the executor dispatches the
  refute call on the distinct refute model with the gate's authored `review.prompt`" (lines 53-54).
  This matches `hb-exec.js:348-350`: `dispatch(c.refuteCmd, 'refute', { ..., prompt: rv.prompt || \`Refute that ${gate} is truly complete.\`, ... })`, where `rv = ((dag.gates||{})[gate]||{}).review` (line 339) — i.e. the DAG-authored prompt, verbatim.
- **The `--questions` seeding is now attributed to the AUTHOR, not the executor.** Lines 54-58:
  "the `hb-audit --questions` you ran in step 1 derives the falsification questions … **and you fold
  them into the gate's `review.prompt` when you author it (the executor passes that prompt through;
  it does not call `--questions` itself)**." This is now literally true and matches the code:
  - `grep questions plugin/templates/hb-exec.js` → **NONE**. No runtime executor path invokes
    `reviewQuestions`/`--questions` or injects its output into the refute payload.
  - `reviewQuestions`/`review_questions` is reachable **only** via the `--questions` CLI flag
    (`hb-audit.js:130-131`, `cli.py:113-114`) — a human/agent action.
  - The seeding is a PROTOCOL instruction to whoever drives review_pending
    (`protocol.py:11`: "seed it with `hb audit --questions <gate>`"), exactly as the doc now says.
- **The self-contradiction is gone.** Step 1 runs `--questions` as a manual step ("used in step 2");
  step 2 now consistently keeps it a manual/authoring action folded into `review.prompt`, rather
  than handing the same action to "the executor" automatically. No remaining false attribution.

## Everything previously confirmed is still intact

- Real command signatures (stamp-evidence, ground-check `--strict`, `hb-audit --questions`) unchanged.
- `HB_REFUTE_MODEL` env / `.hb/executor.json` `refute_model` resolution: `hb-exec.js:87`
  (`process.env.HB_REFUTE_MODEL || file.refute_model || null`); reaches dispatch via
  `refExtra.HB_EXEC_MODEL` (line 342).
- Provenance path `.hb/reviews/<gate>.attempt.md` with `refuterId` (incl. `model=`) written in
  (lines 365-368); distinct-actor pass via `hbAs(refuterActor, ...)` (line 369).
- Honest-about-limits scope note intact (lines 69-77); not a duplicate of `cross-model-verification.md`.
- All 6 relative links + 2 gate-examples resolve on disk; listed in `howto-list.md:43` (T73/T110).
- Both proofs run: `cross-model-refuter.sh` → `CROSS-MODEL-REFUTER-OK` (exit 0);
  `ground-check.sh` → `GROUND-CHECK-OK` (exit 0).
- Prose gate: `prose-check.sh docs/howto/run-a-cross-model-research-review.md` → `PROSE-OK` / `ALL-PROSE-OK:1`.
- Node suite: `bash tests/run-tests.sh` → **334 passed, 0 failed**.

With the sole defect corrected and no new false claim introduced, I cannot break the phase claim.

VERDICT: COULD NOT REFUTE
