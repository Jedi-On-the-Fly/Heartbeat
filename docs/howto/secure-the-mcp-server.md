# Secure the MCP server

`hb mcp-serve` lets an MCP agent drive HeartBeat ([drive-heartbeat-over-mcp.md](drive-heartbeat-over-mcp.md)).
Two things to understand before you expose it.

## What a caller can — and can't — do

- **Can't fabricate a pass.** A phase advances only when its behavioral gate passes; a `review`
  pass requires a substantive, phase-citing artifact from a **different actor**. A caller's
  self-report is never evidence ([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md)). Caveat:
  the distinct-actor check keys on the server's single `HB_ACTOR`, so over one shared, long-lived
  MCP server it is only as strong as callers using distinct identities — run a server per actor, or
  set `HB_ACTOR` per caller, for a real separation.
- **Can mutate state and run gate commands.** The act tools (`start`/`done`/`fail`) append events,
  and the `gate` tool **executes the DAG's gate criteria as shell commands**. So the server is as
  trusted as whoever can reach it, and **`dag.json` is trusted input** — a hostile DAG is a hostile
  program. There is no auth token in the server itself.

## Transports

- **stdio (default)** — the client launches the server as a subprocess; there is **no network
  surface**. This is the safe default (and what the plugin registers).
- **HTTP (`--http`)** — a convenience for remote/hosted clients. **Unauthenticated by design.**

## HTTP hardening (built in)

- **Loopback only by default.** A non-loopback `--host` is refused unless you pass `--allow-remote`
  (the endpoint is unauthenticated and can run gate shell-commands — remote exposure must be
  explicit).
- **Origin validation.** A request whose `Origin` isn't loopback is rejected with `403` — the
  DNS-rebinding defense the MCP spec requires of local HTTP servers. The allowlist is an **exact IP
  match** (`localhost` / a real 127.0.0.0/8 or `::1` address), so a lookalike host like
  `127.0.0.1.evil.com` is rejected, not matched by prefix.

Both are proven by [`gate-examples/mcp-http.sh`](gate-examples/mcp-http.sh) (`MCP-HTTP-SECURE-OK`),
part of the suite.

## If you must expose it

- Put it **behind a reverse proxy** that terminates TLS and authenticates — the server has no auth
  of its own; loopback + Origin checks defend the local case, not an open port.
- Keep **`dag.json` trusted**: gate criteria run through the system shell.
- Prefer **stdio + plugin registration** ([install-the-heartbeat-plugin.md](install-the-heartbeat-plugin.md))
  over a network endpoint whenever you can.
