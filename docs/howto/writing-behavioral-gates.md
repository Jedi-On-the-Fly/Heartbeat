# How to write behavioral gates

A gate is the deterministic check that decides whether a phase is *done*. It runs between
ticks, on settled state, with no model in the loop. It is the durable asset — the worker
and the framework are swappable, the gate is what still proves the work a year later. This
guide is about the one thing no tool can do for you: making a gate assert the *right*
behavior.

Every claim here is backed by a runnable proof under [`gate-examples/`](gate-examples/).
Each example ships a stub a lazy worker might emit, a *weak* gate that is fooled by it, and
a *behavioral* gate that rejects it — and [`run.sh`](gate-examples/run.sh) proves all three
hold. Read the prose, then run the proofs.

## The one test that matters

> A good gate **fails on a hollow artifact.**

Before trusting a gate, hand it the output a worker would produce if it *didn't* do the
work — an empty file, a stub that compiles, a `{"status":"ok"}` it wrote itself — and
confirm the gate **fails**. A gate that passes on the stub is not testing your work; it is
testing that a file exists or that nothing threw. This single refutation catches most weak
gates, and it needs no model: you write the stub by hand.

That is exactly what `run.sh` automates for every example: *weak gate passes on the stub*
(the hole), *behavioral gate fails on the stub* (rejects lazy work), *behavioral gate
passes on real output*.

## Two tiers of weakness

Not all weak gates are equal. Some are caught **structurally** by the auditor
([`hb-audit`](../../plugin/templates/hb-audit.js)) before you ever run — you should simply
run it and fix what it flags. Others are **semantic**: the gate is deterministic and looks
behavioral, but asserts the wrong thing. No static tool can catch those; they are the last
mile, and they are what this guide spends its time on.

| Tier | Caught by | Examples |
|---|---|---|
| Structural | `hb-audit` (static) | hollow / vacuous, existence, nondeterministic, side-effecting, off-phase, and `ungated` / `unguarded_phase` |
| Semantic | only you (refutation) | coverage-header-grep, imports-not-behavior — the gate *runs*, looks rigorous, asserts too little |

`ungated` (a gate with zero criteria) and `unguarded_phase` (a phase with no gate) have no
runnable example here because the auditor rejects them outright — there is no artifact to
fool. Run `hb-audit` and they cannot survive.

## The catalogue

### Structural — the auditor catches these; know them anyway

- **[hollow](gate-examples/hollow/)** — the gate asserts nothing (`true`, or a check that
  cannot fail). Passes on everything. Rewrite: assert the actual outcome
  (`grep -q "tests passed" build.log`).
- **[existence](gate-examples/existence/)** — `test -f config.json` instead of checking the
  contents. The file exists in the stub too. Rewrite: parse it and assert the value
  (`json.load(...)['port'] == 8080`).
- **[nondeterministic](gate-examples/nondeterministic/)** — the verdict depends on
  something other than the artifact (`$RANDOM`, the clock), so a phase can advance on a coin
  flip. Rewrite: depend only on the produced artifact, so the same output always gives the
  same verdict.
- **[side-effecting](gate-examples/side-effecting/)** — the gate *writes* its own evidence
  (`echo status=ok > result.txt; grep ok result.txt`) and grades its homework. Rewrite:
  read the artifact the worker produced; never create it.
- **[off-phase](gate-examples/off-phase/)** — this phase's gate checks a *prior* phase's
  file, so it passes before this phase's work is done. Rewrite: check the artifact this
  phase is responsible for.

### Semantic — only refutation catches these

- **[coverage-header-grep](gate-examples/coverage-header-grep/)** — a coverage gate greps a
  test suite's group *header* (`… | grep -q T7`). The header prints even when the group is
  red, and the pipe hides the suite's exit code, so the gate passes on a failing suite. This
  is the exact hole HeartBeat's own suite closed with a `GROUPS-PASSED:` marker. Rewrite:
  assert the group actually **passed** (`grep -q 'GROUPS-PASSED:.* T7 '`), or run just that
  test and check its real result.
- **[imports-not-behavior](gate-examples/imports-not-behavior/)** — the most insidious: the
  gate *runs* the code (`python3 -c "import greeting"`), so it is not a `test -f` and feels
  behavioral — but it asserts a property *weaker* than the behavior. Imports ≠ works;
  compiles ≠ correct; `/health` returns 200 ≠ the feature works. Rewrite: assert the
  behavior itself (`greet("Ada") == "Hello, Ada!"`). The static auditor cannot flag this —
  `import greeting` classifies as behavioral — which is why the fleet below exists.

## Refute your gates: the adversarial fleet

A gate's weakness is **latent** — it does not show up when the worker happens to do the
task correctly; it bites when the task is hard, the worker is weak, or a shortcut is
tempting. So "it passed in testing" is not evidence a gate is strong. To find the latent
holes, attack a candidate gate with a *diverse fleet of workers* and watch whether any
satisfies it without doing the real work.

[`discover.sh`](gate-examples/discover.sh) does this: it drives a task past a
plausibly-behavioral-but-weak gate with several backends (agent frameworks, or a spread of
local models — different workers fail differently), and reports any that game it. The
`imports-not-behavior` example was found this way. The honest outcome, and why a *null*
result is still the lesson, is in [discovery-notes.md](discovery-notes.md).

Two rules make the fleet trustworthy:

- **Separate a weak gate from a weak worker.** A worker that fails the task is not proof of
  a weak gate; an exploit is specifically *weak-gate passes, strong-gate fails*.
- **Reduce every finding to a deterministic fixture.** Live model runs are a discovery
  tool, not a gate. Once the fleet finds an exploit, pin it as a model-free example (as
  `imports-not-behavior` pins the import shortcut) so it is reproducible forever.

## Checklist

- The gate **fails on a hand-written hollow artifact**. (If not, it is not testing your
  work.)
- It asserts **behavior**, not existence or compilation — the strongest observable
  consequence of the work being done.
- It is **deterministic and read-only** — same artifact, same verdict; no writes, no
  `$RANDOM`, no clock, no network.
- It checks **this phase's** artifact.
- A coverage gate asserts the test **passed**, not that a name appears in the log.
- It runs **fast** (well under the gate timeout).
- `hb-audit` is clean, and a skeptic (or the fleet) **cannot refute** the phase.

## Enforced elsewhere — link, don't duplicate

This guide is the *why* and the worked examples. The rules are enforced in two places, and
those are the source of truth:

- The **auditor** ([`hb-audit`](../../plugin/templates/hb-audit.js)) — the structural rules
  above, run before any DAG executes.
- The **`/heartbeat plan` rules** ([`SKILL.md`](../../plugin/skills/heartbeat/SKILL.md)) —
  the behavioral-gate and coverage-gate rules applied when a plan is written.
- The **contributor invariants** ([`AGENTS.md`](../../AGENTS.md), rules 3 and 6) — gates
  must be behavioral; a review pass must cite evidence, not assert one.

## Run the proofs

```bash
bash docs/howto/gate-examples/run.sh            # prove every example (ALL-EXAMPLES-PROVEN:N)
bash docs/howto/gate-examples/run.sh --selftest # confirm the runner can reject a bad example
bash docs/howto/gate-examples/discover.sh --dry # the fleet method, deterministically, no model
```

## Honest limit

An auditor and a fleet raise the floor; they do not choose the assertion for you. A gate
can be deterministic, behavioral, and audit-clean while testing the wrong thing. Picking
the assertion that actually means "the work is done" is judgment — this guide sharpens it,
it does not replace it.
