# Proof contract for gate examples

Every `<name>/example.sh` demonstrates **one** gate weakness as a runnable proof.
`run.sh` executes each example in an isolated temp dir and marks it `PROVEN` only
when the demonstration holds. Two modes:

## Discriminating mode

The example defines four shell functions:

| Function | Meaning |
|---|---|
| `setup_stub` | write the artifact a lazy worker might emit (does *not* do the real work) |
| `setup_real` | write a correct artifact |
| `weak_gate` | the tempting weak gate — exit 0 = pass |
| `strong_gate` | the behavioral gate — exit 0 = pass |

Proven iff all three hold:

1. `weak_gate` **passes** on the stub — the hole: the weak gate is fooled.
2. `strong_gate` **fails** on the stub — the behavioral gate rejects lazy work.
3. `strong_gate` **passes** on real output — it accepts correct work.

Use this when the weakness is *discriminating power* (the gate can't tell the stub
from real work): hollow, existence, coverage-header-grep.

The artifact need not be code. A **non-code deliverable** — a document, a dataset, a
config — uses the same triple: the stub is the placeholder or wrong-shape version a lazy
worker emits (a `TODO` section, a header-only CSV), and the behavioral gate asserts the
deliverable actually carries its content (a real recommendation, rows that parse to the
right schema).

## Property mode

Some weaknesses aren't about stub-vs-real; they're a property of the gate itself
(flakiness, side effects, testing the wrong phase). The example defines a single
`prove` function that runs its own assertions and returns 0 iff the weakness — and
its behavioral fix — are demonstrated. Use this for nondeterministic, side-effecting,
off-phase.

## Rules

- No network, no model, no clock/RANDOM dependence in the *proof outcome* — running
  `run.sh` twice must give the same result (a nondeterminism demo may sample `$RANDOM`
  internally, but its `prove` verdict must be deterministic).
- Each check runs in its own `mktemp` dir; clean up nothing by hand — `run.sh` does it.
- `run.sh --selftest` injects a hollow example and must report `SELFTEST-CAUGHT`,
  proving the runner can actually reject a bad example.
