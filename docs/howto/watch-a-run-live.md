# Watch a run live

HeartBeat can render your DAG two ways: a **snapshot** (a self-contained HTML file, frozen at
the moment you generate it) and a **live dashboard** (a small local server that always shows the
current execution state). Use the snapshot to share or archive a phase; use the live view to
watch a run unfold without regenerating anything.

Both come from `hb-viz.js`, the plugin (node) visualizer that ships in every `.hb/`. (The Python
`hb` console has no visualizer; this guide is the node runtime.)

## Snapshot — a point-in-time picture

```bash
node <project-dir>/.hb/hb-viz.js <project-dir>/.hb        # writes <project-dir>/.hb/dag-view.html
```

The output is fully self-contained (no external resources), so you can open it by double-clicking
or commit it as a record. It is a *snapshot*: to reflect newer state, generate it again.

## Live — always current

```bash
node <project-dir>/.hb/hb-viz.js <project-dir>/.hb --serve --port 8787
# → prints http://127.0.0.1:8787   (open it; it re-reads the DAG every 2s)
```

The `--serve` server re-reads `dag.json` and `state.json` **fresh on every request**, so the page
reflects the current state with no regenerate — mark a task done in another terminal (a tick, or
the CLI) and the dashboard updates on its own. Pass `--port 0` for an ephemeral port (the chosen
port is printed on startup).

Why a server at all? A page opened over `file://` cannot read sibling JSON — browsers block local
`fetch`. That is exactly why the snapshot bakes its data in, and why a *live* view needs something
serving the data over HTTP.

## What it shows

Phases and tasks colored by status (done / active / pending / locked), each gate as passed or
waiting, and `requires` edges between tasks — the same cascade in both modes, plus a progress bar.

## Safety

The live server is unauthenticated, so it is locked down by default: it binds `127.0.0.1` only
and validates the `Origin` header (a non-loopback origin is rejected `403` — the DNS-rebinding
defence, the same posture as [secure-the-mcp-server.md](secure-the-mcp-server.md)). A non-loopback
bind is refused unless you explicitly pass `--allow-remote`.

## Proof

[`gate-examples/viz-serve.sh`](gate-examples/viz-serve.sh) starts a real `--serve` server and
proves the claims above: a task marked done through the CLI is reflected by a second request on
the same server (live re-read, not a baked file); a loopback `[::1]` origin is accepted `200`
while a foreign origin is rejected `403`; a non-loopback bind is refused; and snapshot mode still
writes a self-contained page. Run it:

```bash
bash docs/howto/gate-examples/viz-serve.sh   # -> VIZ-SERVE-OK
```

It is wired into the suite as **T86**, so the behavior this guide describes is re-checked on every
run.
