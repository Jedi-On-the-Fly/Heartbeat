# Build and test a backend

A backend is the smallest thing in HeartBeat: an adapter that speaks a three-mode wire
protocol. The driver keeps Stage B untrusted ([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md))
and mediates every state transition, so an adapter only has to translate — it never touches
`state.json` or the gate. Keep it dumb, make it conform, and it drops in.

## The contract

```
driver → backend:  argv[last] = execute | refute | author,  stdin = payload JSON
backend → driver:  execute → {"ok": bool, "summary": str}
                   refute  → {"refuted": bool, "findings": str}
                   author  → {"ok": bool, "constraints": [{id, claim, subjects, violation}, …]}
```

`author` is the gate-time constraint author of the constraint-first review: a read-only model call
on `payload.prompt` whose reply must carry a JSON array of constraints (`ok: false` when it could
not — the driver escalates). A `refute` payload with `"review": "free"` is the free (unconstrained)
review: same reply shape as any refute. `findings` carry the reviewer's full text (the shipped
adapters keep up to 20 000 characters) — a constrained refute answers every constraint id on its
own line, and a truncated answer set is refused.

Three rules make an adapter safe:

- **Protocol JSON on the last stdout line.** The driver reads the last non-empty line and
  parses it; anything before it is ignored, anything non-JSON after it breaks the read. Print
  the result object last, nothing after.
- **Degrade, don't crash.** If the framework/model/server is unavailable, still emit a valid
  protocol object (`{"ok": false, "summary": "…unavailable…"}`) — never a traceback or empty
  output. The driver treats a failed shape as a failed task and escalates.
- **A verdict only when the reviewer gave one.** `refute` returns `{"refuted": bool, …}` only when
  the reply ends with an explicit, whole-word, upper-case `REFUTED` or `CLEAR` ("unclear" is not a
  `CLEAR`; read the model's own text, not a tool's output); a review that could not run (framework
  missing, server unreachable, CLI failed) or a reply with no final verdict token returns
  `{"error": "…"}`, which the driver escalates. Never `{"refuted": false}` for "could not review" —
  the driver reads that as "could not refute" and passes the gate.
- **Refuse an unknown mode.** Print `{"error": "unsupported mode …"}` and do nothing. A mode that
  is not `refute` must never fall through to `execute` — execute writes files, and the driver adds
  modes over time (`author` did).

The shipped adapters under `plugin/templates/executors/` (and the in-process
`py/src/heartbeat/backends/`) are the templates; see [dev-python.md](../dev-python.md). The two
methods are dispatched independently, so `refute` can be routed to a *different* backend than
`execute` — [cross-model-verification.md](cross-model-verification.md).

## Test it for conformance

Before trusting a backend, run it through the contract in degrade mode and confirm the shape.
[`gate-examples/backend-conformance.sh`](gate-examples/backend-conformance.sh) is a reusable
harness: it checks that **every shipped adapter** — python and shell (CLI absent) — degrades to
a protocol-valid object in all three modes (`ok` boolean; a `refute` that could not run is an
`{"error"}`, never a verdict; `author` → `ok:false` or a constraint list), and refuses an unknown
mode while writing nothing — deriving the list from the
executors directory so a new adapter is included automatically — and it proves the harness has
teeth by **rejecting** a wrong-shape backend (`{"done":true}`), one that prints junk after its
JSON, one that emits a CLEAR verdict while it could not review (fail-open), and one whose unknown
mode falls through to execute. Run it:

```bash
bash docs/howto/gate-examples/backend-conformance.sh   # -> BACKEND-CONFORMANCE-OK:<n>
```

Point it at your own adapter (the same `execute`/`refute`/`author` invocation) to check conformance
before you ship it.
