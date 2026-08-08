# Embed HeartBeat in a Python application

**Outcome:** drive HeartBeat from inside your own Python program — no CLI subprocess. The core
is a stdlib library, so the tick, the gates, and the event-sourced state are all importable.

## The API

The pieces you need live in a few modules:

```python
from heartbeat import state as st, gate, tick

hb = "myproject/.hb"                          # the .hb directory (dag.json + events.jsonl)

st.mutate(hb, {"event": "task_started", "task": "P0T1"})   # append an event + reproject
# ... do the work ...
st.mutate(hb, {"event": "task_done", "task": "P0T1"})

res = gate.run_gate(hb, "GATE_P0")            # run the phase's behavioral gate, in-process
s = st.project(st.read_events(hb), st.read_dag(hb))        # the current derived state
assert "P0" in s["completed_phases"]
```

- `state.mutate` is the only way to change state — it appends to the log and reprojects, so you
  keep the same guarantees as the CLI ([never-hand-edit-state.md](never-hand-edit-state.md)).
- `gate.run_gate` runs the real behavioral gate and records the outcome; `tick.tick` gives you
  the next action if you want the driver loop.

This is the same surface the CLI is built on — the `hb` console is a thin wrapper. Embedding
lets you run HeartBeat inside a larger service, a notebook, or your own orchestration.

## Prove it worked

[`gate-examples/embed-python.sh`](gate-examples/embed-python.sh) drives a project to completion
using only `state.mutate` / `gate.run_gate` / `state.project` (no CLI), and shows a missing
artifact leaves the phase incomplete (the library gate is real) → `EMBED-PYTHON-OK`.

## Next

- The event log those calls append to: [read-the-event-log.md](read-the-event-log.md).
- Write a backend adapter instead, to plug in a worker: [build-and-test-a-backend.md](build-and-test-a-backend.md).
