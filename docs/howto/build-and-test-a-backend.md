# Build and test a backend

A backend is the smallest thing in HeartBeat: an adapter that speaks a two-method wire
protocol. The driver keeps Stage B untrusted ([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md))
and mediates every state transition, so an adapter only has to translate — it never touches
`state.json` or the gate. Keep it dumb, make it conform, and it drops in.

## The contract

```
driver → backend:  argv[last] = execute | refute,  stdin = payload JSON
backend → driver:  execute → {"ok": bool, "summary": str}
                   refute  → {"refuted": bool, "findings": str}
```

Two rules make an adapter safe:

- **Protocol JSON on the last stdout line.** The driver reads the last non-empty line and
  parses it; anything before it is ignored, anything non-JSON after it breaks the read. Print
  the result object last, nothing after.
- **Degrade, don't crash.** If the framework/model/server is unavailable, still emit a valid
  protocol object (`{"ok": false, "summary": "…unavailable…"}`) — never a traceback or empty
  output. The driver treats a failed shape as a failed task and escalates.

The shipped adapters under `plugin/templates/executors/` (and the in-process
`py/src/heartbeat/backends/`) are the templates; see [dev-python.md](../dev-python.md). The two
methods are dispatched independently, so `refute` can be routed to a *different* backend than
`execute` — [cross-model-verification.md](cross-model-verification.md).

## Test it for conformance

Before trusting a backend, run it through the contract in degrade mode and confirm the shape.
[`gate-examples/backend-conformance.sh`](gate-examples/backend-conformance.sh) is a reusable
harness: it checks that **every shipped adapter** degrades to a protocol-valid object (`ok`
and `refuted` are booleans, valid JSON on the last line) — deriving the list from the
executors directory so a new adapter is included automatically — and it proves the harness has
teeth by **rejecting** a wrong-shape backend (`{"done":true}`) and one that prints junk after
its JSON. Run it:

```bash
bash docs/howto/gate-examples/backend-conformance.sh   # -> BACKEND-CONFORMANCE-OK:<n>
```

Point it at your own adapter (the same `execute`/`refute` invocation) to check conformance
before you ship it.
