# Use HeartBeat with OpenCode

[OpenCode](https://opencode.ai) (SST) is a provider-agnostic terminal coding agent. It connects to
HeartBeat two ways — HeartBeat can *drive* it, and it can *be driven by* it over MCP.

## Drive OpenCode as the worker (Stage B)

OpenCode does the tasks; HeartBeat schedules and verifies them. Select the backend:

```bash
HB_EXEC_BACKEND=opencode hb exec run --dir <project>
```

The adapter runs `opencode run --format json` with the task prompt. Pick the model with
`HB_EXEC_MODEL` (opencode's `provider/model` form, e.g. `anthropic/claude-sonnet-4-6`), or set
`HB_EXEC_PROVIDER` + a bare `HB_EXEC_MODEL` and the adapter joins them. For a keyless local run,
configure an ollama provider and use `HB_EXEC_MODEL=ollama/qwen2.5:7b-instruct`.

**Autonomy (the gotcha).** Headless `opencode run` blocks on an "ask" permission when there's no
terminal. Configure opencode's `permission` to `allow` (in `opencode.json`) for unattended use —
opencode 0.15.3 has no `--auto` flag (newer builds add one). The adapter closes stdin defensively.

**Trust the gate, not the exit code.** `opencode run` exits `0` even when the model call fails
(it reports the error as a JSON event). That's fine here: HeartBeat advances a phase only when its
**behavioral gate** passes, never on the worker's self-report ([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md)).

**Proof.** The deterministic suite proof is a stub `opencode` on PATH —
[`gate-examples/opencode-backend.sh`](gate-examples/opencode-backend.sh) drives the *real* adapter
to a passing gate (and a failing stub does not complete the phase), with no model or network. A
live run is on-demand and **best-effort**: an authed provider works; the local ollama path needs
opencode's AI-SDK provider install and did not complete a headless turn in our environment — so,
like the codex backend, the honest suite gate is the stub. See
[choose-a-backend.md](choose-a-backend.md).

## Be driven by OpenCode over MCP

OpenCode is an MCP client, so it can call HeartBeat's `tick` / `gate` / `state` tools mid-session
([drive-heartbeat-over-mcp.md](drive-heartbeat-over-mcp.md)). Add HeartBeat to `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "heartbeat": { "type": "local", "command": ["hb", "mcp-serve"], "enabled": true }
  }
}
```

For a remote server, use `{ "type": "remote", "url": "http://<host>:<port>" }` against
`hb mcp-serve --http`. OpenCode uses its own `opencode.json` config here — it does **not** read the
`.claude-plugin/marketplace.json` that Codex and Claude Code share (so the SessionStart drive-loop
hint never reaches it). The tools become available to the model automatically.

**Drive the whole DAG, don't stop at one tick.** Because OpenCode reaches HeartBeat only through the
MCP tools (not the plugin hook), the `tick` tool itself carries the drive-loop guidance: its
description — and a `data.next` nudge on each work-advancing wake — tells OpenCode to call `tick`
again until `all_done` or a human-needed reason. See
[drive-heartbeat-over-mcp.md](drive-heartbeat-over-mcp.md#drive-the-loop-dont-stop-after-one-tick).

**Proof.** [`gate-examples/opencode-mcp.sh`](gate-examples/opencode-mcp.sh) validates the config
shape and confirms the wired `hb mcp-serve` command spins a working MCP server (initialize
handshake). Full third-party-client interop is guaranteed by the official MCP SDK v2 reference
proof ([`tests/mcp-interop.sh`](../../tests/mcp-interop.sh)); an opencode-specific live check is
on-demand.

**Security.** The MCP server is unauthenticated and its `gate` tool runs shell commands — read
[secure-the-mcp-server.md](secure-the-mcp-server.md) before exposing it beyond local stdio.
