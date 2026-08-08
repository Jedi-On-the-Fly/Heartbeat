# MCP real-client interop — live results

On-demand tier (`bash tests/mcp-interop.sh`): the **official MCP Python SDK** drives `hb mcp-serve`
over stdio as a real third-party client. Not a core-suite gate (needs a venv + `pip install mcp>=2`,
i.e. network) — it self-skips (`INTEROP-SKIPPED`) offline. The server stays stdlib-only; the SDK
lives only in the test venv.

| Date | SDK | Transport | Negotiated | Result |
|---|---|---|---|---|
| 2026-08-08 | `mcp` 2.0.0 (official Python SDK v2) | stdio | **2026-07-28** | `MCP-INTEROP-OK` |

What the run verified against the live SDK v2 client:
- `session.discover()` → `supportedVersions == ['2026-07-28', '2025-06-18']`.
- The client auto-negotiated **`session.protocol_version == '2026-07-28'`** (the modern path) — it
  probes `server/discover` and would fall back to `initialize` for an older server.
- `list_tools()` contains `tick`/`gate`/`state`; `call_tool('state')` equals `hb state`
  (`last_updated` excluded).

This is the third-party confirmation that the deterministic `mcp-2026.sh` wire-shape proof is
correct against the reference implementation, not just our own client.
