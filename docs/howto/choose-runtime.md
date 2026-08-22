# Choose Claude Code vs the Python runtime

**They are the same product, not two.** The Claude Code plugin (node + bash) and the pure-Python
port share the `dag.json` format and the tick protocol, and a
[parity contract](keep-the-runtimes-in-parity.md) keeps `lint` / `audit` / `project` identical on
both. So this is not "which is better" — it's "which fits where you're running."

## The rule: pick by environment

- **Claude Code plugin** — you're working *inside* Claude Code interactively and want the
  `/heartbeat` skill (plan, run, drive) in the session. This is the beachhead
  ([use-heartbeat-with-claude-code.md](use-heartbeat-with-claude-code.md)).
- **Python runtime** (`pip install -e py`, the `hb` console) — anywhere else: CI, a
  server, cron, a container, or embedding in a larger Python program. No Claude Code required;
  it runs wherever Python does ([run-heartbeat-in-ci.md](run-heartbeat-in-ci.md),
  [embed-heartbeat-in-python.md](embed-heartbeat-in-python.md)).

## It's not a lock-in

Because the DAG format is shared, a project authored one way runs the other way unchanged — the
parity test exists precisely so `hb audit`/`hb lint` give the same verdict on both. Start in the
plugin while you explore, move to the Python runtime for unattended operation; the `dag.json`
comes with you.

## Related

- Prove the two runtimes agree: [keep-the-runtimes-in-parity.md](keep-the-runtimes-in-parity.md).
- Once you've picked a runtime, pick the worker: [choose-a-backend.md](choose-a-backend.md).
