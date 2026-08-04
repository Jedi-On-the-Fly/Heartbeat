# HeartBeat — the pure-Python port

A second implementation of the same idea, in pure Python, so it installs with `pip` and
runs anywhere Python does — no node, no bash. Sharing it alongside the original in case
the packaging is more convenient for you.

If you haven't read [the concept](heartbeat.md) yet, start there: the tick, the
deterministic gaps, gates, and refute-don't-confirm. This note is only about the port —
what it is and how the pieces map — not the idea itself, which is unchanged.

![Pure-Python architecture](heartbeat-py-arch.png)

## What it is

One package, `heartbeat`, with a single console entry point, `hb`. The core is
stdlib-only. The same two stages, the same event-sourced state, the same DAG — just
Python modules instead of a mix of bash and node:

| Concept | Module |
|---|---|
| Stage A — the tick | `tick.py` (priority checks → `{ wakeAgent, reason, action }`) |
| Eligibility / next work | `resolver.py`, `lint.py` |
| Behavioral gates | `gate.py` (runs the gate's shell commands, `--check` re-verifies) |
| Event-sourced state | `state.py` (append to `events.jsonl` → project `state.json`) |
| Integrity + root cause | `doctor.py` (rot detection, `hb diagnose`) |
| The driver (Stage B) | `executor.py` (serial or worktree-parallel, escalate-only) |
| Pluggable workers | `backends/` (ollama · agno · crewai · claude, or a subprocess) |
| Scaffolding + CLI | `scaffold.py` (`hb init`), `cli.py`, `report.py` |

Nothing is remembered; it's computed. The state is a projection of the log, exactly as
before. The tick is still cheap, deterministic, and reserves the model for the one thing
only it can do.

## Same model, two runtimes

The `dag.json` format and the tick protocol are identical to the node+bash plugin, so a
project written for one runs under the other. Pick by what fits:

- **node+bash plugin** — the mature one, with the `/heartbeat` Claude Code skill and its
  UX. Best when you're working inside Claude Code.
- **this port** — `pip install`, one `hb` binary, and Stage A/gates/state all in Python.
  Best when you want to run a DAG on a plain machine, in CI, or embed it in a Python app.

They share the DAG and the invariants; they don't share code. Each has its own test suite.

## Using it

```bash
pip install ./py                 # core (stdlib only)
pip install "./py[agno]"         # add the Agno backend
pip install "./py[crewai]"       # add the CrewAI backend

hb init  <project-dir>           # scaffold .hb/
hb lint  --dir <project-dir>     # validate the DAG
hb tick  --dir <project-dir>     # one Stage-A tick
hb exec  run --dir <project-dir> # drive the loop with a backend
hb exec  run --parallel 4 --dir <project-dir>   # worktree-isolated fan-out
```

State is mutated only through the CLI (`hb start|done|fail|review|rebuild`), never by
hand. The full command list lives in [`py/README.md`](../py/README.md).

## Backends

Stage B is swappable. Choose with `.hb/executor.json` `{"backend": …}` or
`HB_EXEC_BACKEND`:

- `ollama` — local models, no API key, stdlib only.
- `agno` / `crewai` — set `HB_EXEC_PROVIDER=ollama` to drive them with local models, or
  `anthropic` with `ANTHROPIC_API_KEY`.
- `claude-code` — headless `claude -p`.
- `script` — any command, via `HB_EXEC_CMD`.

A backend is two functions: `execute(payload) → {ok, summary}` and
`refute(payload) → {refuted, findings}`. The driver mediates every state transition, runs
the gate itself, and — by policy — escalates instead of auto-fixing when a gate blocks. A
less-trusted worker stays safe because nothing believes it until the gate passes.

## What "zero node/bash" means

Honestly: HeartBeat's own tooling is pure Python — the tick, resolver, gates, state, and
executor. Gate `cmd`s, though, are user-authored shell one-liners; that's the DAG
contract, and they still run through the system shell. The upside is that your gates can
now be Python too. The live proof below does exactly that: the gate is
`python3 -c "import greeting; assert greeting.greet('Ada') == 'Hello, Ada'"` — no node
anywhere in the loop.

## Proof

- **Tests:** `cd py && PYTHONPATH=src python3 -m pytest -q` — the substrate (state,
  resolver, lint, gate, tick, CLI, executor including worktree isolation) under its own
  suite.
- **Installable:** `pip install ./py` yields a working `hb` console.
- **Live:** `python3 py/real-backend.py ollama qwen2.5:7b-instruct` drives a project where
  a local model writes `greeting.py` and a Python gate imports and runs it — a fully
  node/bash-free run, end to end.
