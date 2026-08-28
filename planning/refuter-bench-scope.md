# Scope: refuter calibration harness (`hb refuter-bench`)

**One line.** Make a refuter's *value* measurable — accept a refuter the way HeartBeat accepts a review
pass: with **cited evidence** (catch-rate / false-alarm vs the `default` baseline over seeded
known-buggy / known-clean fixtures), not by assertion. Harness-first: build the measurement, defer the
authoring skill.

## Why

Authoring a refuter is trivial and already documented ([write-a-refuter-profile.md](../docs/howto/write-a-refuter-profile.md),
[tune-refuter-sensitivity.md](../docs/howto/tune-refuter-sensitivity.md)). The one thing those can't
give you is the un-gateable part HeartBeat itself flags as *"Test Whether Your Refuter Adds Value — not
available yet (needs a live model)."* This scope turns that from prose into a repeatable, on-demand
**measurement**, applying HeartBeat's own "refute the claim" ethos recursively to refuters.

## The split (same pattern as the rest of HeartBeat)

- **Scorer — deterministic.** `(expected[], actual[]) → {catch, false_alarm, n_bug, n_clean, Δ vs
  baseline}`. Fixed verdicts in → numbers out; suite-gated with STUB verdicts, node ≡ python parity,
  `--selftest` teeth.
- **`hb refuter-bench` — deterministic under a stub.** Run a refuter over the fixtures, dispatch each
  refute (reusing the shared compose + refute dispatch), score. With a stub backend the whole path is
  deterministic → suite-gated; a refuter that misses a planted bug scores catch < 1.
- **Live calibration — on-demand.** `tests/refuter-calibrate.sh <name>` drives a REAL local model
  (Ollama, no API key), gated behind availability like `real-backend.sh`; **never** in the suite. Its
  plumbing (fixture + report schema) is checkable deterministically (`--check`); the model call is not.

## Phases

- **CB — scorer + fixtures.** The deterministic core: the confusion-matrix scorer (both runtimes) and
  seeded known-buggy / known-clean fixture phases with declared expected verdicts.
- **RB — `hb refuter-bench` command.** End-to-end over the fixtures via a stub backend, scored,
  node ≡ python identical report, unknown refuter errors.
- **CD — on-demand live tier + the how-to.** The local-Ollama runner (never gates) and
  `measure-refuter-value.md`, flipping the roadmap row via gated-docs.

## Non-goals

- Not a suite gate on refuter quality (that needs a live model — stays on-demand).
- Not the `/refuters` authoring skill (deferred until authoring proves frequent; the how-tos cover it).
- Not absolute thresholds — value is **baseline-relative** (Δ vs `default`), because model output drifts.

## Acceptance

`hb-lint` clean · `hb-audit` clean (0 hollow) · plan-refuted SOUND — before any build.
