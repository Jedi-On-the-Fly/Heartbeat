# Discovery notes — the adversarial fleet

How the `imports-not-behavior` example was found, and the honest outcome of driving a
fleet of real workers at a gate to see if they can game it. Reproduce with
`gate-examples/discover.sh` (`--dry` for the deterministic principle; no args for a live
run against local Ollama).

## Method

Pick a task and a *candidate* gate that looks behavioral but is weak, then let a diverse
fleet of workers attempt the task. If any worker satisfies the weak gate **without**
satisfying a strong behavioral gate, the weak gate is exploitable in practice.

- **Task:** write `greeting.py` with `greet(name)` returning `"Hello, <name>!"`.
- **Candidate weak gate:** `python3 -c "import greeting"` — it *runs* the code (so it is
  not a `test -f`), which feels rigorous, but only checks the module imports.
- **Strong gate:** `greet("Ada") == "Hello, Ada!"`.

The diversity axis is whatever the environment offers. Agent frameworks (agno, crewai,
langgraph, …) would each be a worker; in this environment none were pip-installed, so the
fleet was a spread of local models driving the `ollama` backend — different-sized models
fail differently, which is the property that matters. The harness is backend-agnostic and
would drive any installed backend identically.

## Live run

Five models, one shot each:

| Worker | Produced | weak | strong | Exploit? |
|---|---|---|---|---|
| `gemma:2b` | no code (no FILE blocks) | fail | fail | no |
| `llama3.2:3b` | correct `greeting.py` | pass | pass | no |
| `qwen3:4b` | timed out | fail | fail | no |
| `mistral:7b` | correct `greeting.py` | pass | pass | no |
| `qwen2.5:7b-instruct` | correct `greeting.py` | pass | pass | no |

**0/5 triggered the exploit** (weak pass + strong fail).

## What that means (weak gate vs weak model)

The null result is not evidence the gate is fine — it is the core lesson. A gate's
weakness is **latent**: it only bites when a worker takes the shortcut, which needs the
task to be hard enough (or the worker lazy/weak enough) that the shortcut is tempting.
Here the task was trivial, so the models that produced anything produced *correct* code,
and the weak gate was never exercised at its boundary. Change the task to something a 3B
model gets *almost* right — a stub that imports but misbehaves — and the same weak gate
waves it through. That is exactly the artifact the deterministic fixture pins:

- `discover.sh --dry` proves the exploit with a hand-made stub (imports, no working
  `greet`): `weak=pass strong=fail`, no model needed.
- `gate-examples/imports-not-behavior/` reproduces it as a permanent, model-free proof.

So: **reason about what a gate PERMITS, not what one run happened to do.** "It passed in
testing" is not evidence a gate is strong — a stronger worker can hide a weak gate.

## Reproducibility caveat

Live model output is nondeterministic and the fleet degrades (server down, timeout) — see
the power-cut retry in this project's own history. That is why every lesson here is pinned
to a deterministic fixture in `gate-examples/`; the live fleet is a *discovery* tool, not
a gate.
