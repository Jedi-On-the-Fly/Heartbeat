# Swap workers without changing the DAG

HeartBeat's central bet: the **gate is the contract**, the worker is an implementation
detail. The same `dag.json` should run to the same verified outcome whether the work is done
by headless Claude, a local Ollama model, an Agno/CrewAI agent, or a plain script — because
the gate checks *reality*, not who produced it. This is how to rely on that, and how to prove
your DAG hasn't secretly coupled itself to one worker.

## Do it

A backend is selected independently of the DAG (`HB_EXEC_BACKEND` / `.hb/executor.json`, or
`HB_EXEC_CMD` for a raw script). Nothing in `dag.json` names a model. To run the same project
under a different worker, change only the backend — see [dev-python.md](../dev-python.md) for
the backend list and config.

```bash
HB_EXEC_BACKEND=ollama hb exec run --dir myproject     # local model
HB_EXEC_CMD="./my-worker.sh" hb exec run --dir myproject   # any script
```

## The failure mode: hidden worker coupling

A DAG stops being portable the moment a gate asserts something only one worker happens to
produce — a specific log phrase, a filename a particular framework writes, an exact wording.
Then "it passed" means "that worker passed," not "the work is done." The fix is the same as
every gate lesson: assert the **behavior** ([writing-behavioral-gates.md](writing-behavioral-gates.md)),
not an artifact of how one worker phrased it.

## Proof

[`gate-examples/portability-selftest.sh`](gate-examples/portability-selftest.sh) runs the
**same DAG** through two different deterministic backends and asserts both complete the phase
(identical outcome — and genuinely *completed*, not vacuously both-blocked). Then it runs a
deliberately worker-**coupled** gate (one that greps a marker only backend A writes) under
both and asserts the outcomes **diverge** — demonstrating that hidden coupling is detectable
(and that the executor doesn't leak backend identity into the result). Run it:

```bash
bash docs/howto/gate-examples/portability-selftest.sh   # -> PORTABILITY-OK
```

To check your own DAG for coupling, run it under two backends and compare completed phases;
if they differ, a gate is keying on the worker, not the work.
