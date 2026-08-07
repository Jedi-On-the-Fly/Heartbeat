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
