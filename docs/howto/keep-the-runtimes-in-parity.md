# Keep the two runtimes in parity

HeartBeat ships twice — a node+bash plugin and a pure-Python port — and they must behave
identically on the shared surfaces. Parity is a **contract**
([AGENTS.md](../../AGENTS.md) rule 2), enforced by `tests/parity.sh`. This is how to keep it,
and how to make sure the enforcer itself actually works.

## What must agree

The pure functions, on the same input: `lint` (errors), `audit` (findings + counts), the
`state` projection, `resolve` / `ready` / `report` / `diagnose`, and the `PROTOCOL` reason
**keys**. Action *text* is deliberately runtime-specific (node references `node .hb/hb.js`
and `bash .hb/gate.sh`; python references the `hb` console) — so parity compares reason keys,
not messages. The full contract and every intentional divergence live in
[parity-notes.md](../../planning/parity-notes.md).

Beyond the pure functions, a few **behavioral** surfaces must also match (they wrap the pure
functions, so they get their own cross-runtime checks): the **tick's `data.reason`** (both ticks
wake for the same reason on the same state, incl. `review_stuck` — T82), the **gate-runner
verdict** (pass/fail/hollow-floor/timeout — T83), **doctor / rot detection** (T84), and the
**backends registry** (same canonical set — T85). Each is proven by a `gate-examples/*-parity.sh`
script driving both runtimes.

## The rule when you change shared logic

Change one side's shared logic → mirror it on the other in the same change, and keep
`tests/parity.sh` green. A **new** shared surface adds a parity case — otherwise the
contract silently stops covering it.

```bash
bash tests/parity.sh          # node ≡ python across every covered surface
```

## Prove the alarm actually fires

A parity test that is only ever seen to *pass* proves nothing — you need to know it would
**fail** if the runtimes diverged. `tests/parity.sh` takes an `HB_PY_SRC` override (default
`py/src`, behavior unchanged) precisely so a self-test can substitute a *mutated* copy of the
Python runtime and confirm the harness catches the divergence — on the right surface.

[`gate-examples/parity-selftest.sh`](gate-examples/parity-selftest.sh) does exactly that:
baseline parity is green, then it injects a phantom `lint` error into a throwaway copy of the
Python runtime, runs the real `parity.sh` against it, and asserts the run fails **and** flags
`✗ lint`. Run it:

```bash
bash docs/howto/gate-examples/parity-selftest.sh   # -> PARITY-SELFTEST-CAUGHT
```

If you add a surface to the parity contract, this is the pattern to prove the new case has
teeth: perturb one side, confirm the alarm goes off.

## Parity as a differential-testing oracle

Fixed fixtures only cover the inputs you thought of. But two implementations of one spec are
each other's **oracle**: you don't need a known-correct answer — you only need them to
*agree*, so any disagreement on *any* input is a real bug. `tests/parity-fuzz.sh` exploits
that. A seeded, deterministic generator (`tests/gen-parity-case.py`) emits many
structurally-varied, well-formed cases (dag + event log), and the fuzzer runs each through
both runtimes on every shared surface, asserting node ≡ python:

```bash
bash tests/parity-fuzz.sh 12     # -> FUZZ-PARITY-OK:12  (node ≡ python across 12 generated cases)
```

The generator depends **only on its seed** (no time, no randomness), so the run is
reproducible and ratcheted — the same seed always produces the same case, and a divergence
prints the seed so it replays. This is not hypothetical: the first fuzz run caught a real
`report` rounding divergence (`5/8` → node `Math.round` = 63, Python `int()` = 62) that every
fixed fixture had missed because they used clean ratios.

The oracle has the same teeth requirement as the harness itself — a fuzzer only ever seen to
pass proves nothing. `--selftest` runs two passes in one invocation: it must be legitimately
green on the real runtime (`SELFTEST-CLEAN-OK`) *and* then catch an injected divergence on a
mutant runtime (`SELFTEST-CAUGHT:<surface>`). Requiring both means an unconditional "pass"
can't satisfy it.

```bash
bash tests/parity-fuzz.sh --selftest   # -> SELFTEST-CLEAN-OK + SELFTEST-CAUGHT:lint
```

Ratcheted as node-suite **T75**. The input space is bounded to well-formed DAGs by design
(malformed-input fuzzing is out of scope); widen the generator when you widen the contract.
