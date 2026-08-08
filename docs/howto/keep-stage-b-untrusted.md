# Keep Stage B untrusted

Stage B — the worker, whatever framework drives it — is **untrusted**. It can be confidently
wrong, return success on work that doesn't hold, or emit garbage. The driver (the executor)
mediates every state transition and trusts the **gate**, not the worker
([AGENTS.md](../../AGENTS.md) rule 5). This is what that buys you, and how to prove it still
holds.

## What the driver guarantees

- **Escalate-only.** When a gate fails, the driver **escalates** — it never auto-weakens or
  auto-fixes the gate. A blocked phase surfaces for a human; the gate definition
  (`dag.json`) is left exactly as written.
- **Trust the gate, not the worker.** A backend returning `{"ok":true}` does not advance a
  phase — only the behavioral gate passing does. The worker's self-report is recorded, but it
  is not evidence.
- **Reject malformed output.** A backend that emits non-JSON (or the wrong shape) does not
  advance a task; it degrades to a failure and, past the attempt cap, escalates.
- **A hung gate can't hang the run.** Each criterion runs under `GATE_TIMEOUT_S`; a gate that
  blocks forever is killed and the phase is marked blocked, not left hanging.

## Why it matters for backends

This is what makes "drive it with any of ten backends" safe: the trust boundary is the
gate, not the adapter. A new or buggy backend can fail, stall, or lie — and the worst it can
do is get the phase escalated. It cannot fabricate a pass. See the backend list and contract
in [dev-python.md](../dev-python.md).

## Proof

[`gate-examples/driver-guarantees.sh`](gate-examples/driver-guarantees.sh) drives the real
executor with stub backends and proves all four: a compliant worker plus an unpassable gate
escalates with `dag.json` byte-unchanged and the phase not completed (with a control that a
passable gate *does* complete); a non-JSON backend never advances a task; a `sleep` gate is
killed at `GATE_TIMEOUT_S`. Run it:

```bash
bash docs/howto/gate-examples/driver-guarantees.sh   # -> STAGE-B-UNTRUSTED-OK
```

Corollary: never make a gate depend on the worker's output *about itself*
([side-effecting](gate-examples/side-effecting/)) — that hands the untrusted side the pen.

The same trust boundary applies when an agent drives HeartBeat *over MCP*: it can't fabricate a
pass, but it can trigger gate shell-commands — see
[secure-the-mcp-server.md](secure-the-mcp-server.md).
