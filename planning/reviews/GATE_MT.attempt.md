# GATE_MT review — MCP adapter tools (deplint + code_context)

Adversarial review of the shipped MT work, distinct actor.

## Round 1 — SOUND (no defects)
- Proof is a real in-process oracle (mcp-adapters.sh derives expected via importing the adapters,
  drives the REAL mcp-serve JSON-RPC server, asserts tool == adapter). Mutation-tested: `_deplint`→{}
  and `_code_context`→"MUTATED" each make the proof FAIL; restored → MCP-ADAPTERS-OK.
- Tools genuinely read-only: SHA-256 of events.jsonl/state.json byte-identical before/after calling
  them (handlers call pure adapter fns, no state.mutate).
- Bad args don't crash the server (KeyError caught → isError result; subsequent call still works).
- Stdlib-only (adapters lazy-imported, json/sys only); no regressions — mcp-server.sh (T67),
  mcp-http.sh (T68), mcp-2026.sh (T70) all pass.
- Wiring: T97 single-line (mtb + self-audit both satisfied); proof referenced in the how-to body →
  self-audit SELF-AUDIT-OK:63/59.
- Docs accurate (node-free, read-only, == adapter; --strict divergence by design — the tool returns
  the full dict, "Advisory").
- Suites: node 313/0, python 85, parity node ≡ python.

**VERDICT: SOUND**
