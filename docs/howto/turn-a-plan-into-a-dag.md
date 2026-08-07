# Turn a plan into a HeartBeat DAG

**Outcome:** a prose plan (a TODO, a spec) becomes a `dag.json` that HeartBeat can run and
verify. The key shift:

> Your DAG is not a transcript of how the model should think. It is the **contract describing
> what must become true.**

## The transformation

| Prose | DAG element |
|---|---|
| A milestone that must be reached | a **phase** (`id`, `gate_exit`) |
| A unit of non-deterministic work | a **task** (`id`, `title`, sparse `requires`) |
| "How do I know this milestone is done?" | the phase's **gate** — behavioral `criteria` |
| "This can't start until that's done" | a `requires` edge (only real dependencies) |

Rules that keep it runnable and portable:

- **Spec-first.** Each phase's first task should author its gate's test, before the
  implementation tasks — so the definition of done exists before the work.
- **Gates assert behavior, not existence.** `grep -q ok result.txt`, not `test -f result.txt`
  — the second passes on a placeholder. See [writing-behavioral-gates.md](writing-behavioral-gates.md).
- **Keep `requires` sparse** so independent work can run in parallel; ≤ 8 tasks per phase.
- **Name no model.** The DAG says *what must be true*, not *who does it* — that's what keeps it
  [worker-portable](swap-workers-without-changing-the-dag.md).

## Validate before you run

```bash
hb lint  .hb/dag.json     # structure: unique ids, no cycles, valid requires
hb audit .hb/dag.json     # gate quality: rejects hollow / existence-only gates
```

`lint` + `audit` clean is the bar. The most common mistake is a **prompt-shaped DAG** — a
gate like `test -f output` that passes whether or not the work is real. The auditor rejects it
(`hollow_gate`) before you spend a token.

## Prove it worked

[`gate-examples/dag-authoring-check.sh`](gate-examples/dag-authoring-check.sh) shows a
worked-example DAG that lints, audits, **and runs to completion** under a real worker — and a
hollow-gate version that the auditor rejects → `DAG-AUTHORING-OK`.

## Next

- Size the pieces well: a task is one bounded unit of non-deterministic work; a phase is one
  meaningful verified milestone.
- Harden the gates: [10 rules for a good gate](writing-gates-10-rules.md).
