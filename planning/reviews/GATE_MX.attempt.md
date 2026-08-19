# GATE_MX — discovery: MCP tool + docs + skill

**Distinct actor:** reviewer agent (not the doer). **Verdict: SOUND.**

Refutation attempts, all failed:
- code_discover MCP tool is real: code-discover-mcp.sh drives real mcp-serve and compares to the
  discovery FUNCTION (independent oracle). Reviewer independently ran tools/list + tools/call on its
  own codemap == python module; mutation-broke the handler → proof went RED (can't pass on a broken tool).
- Docs honest: advisory, change-impact via reverse edges, explicit graph-limits (dynamic/framework
  bindings + not-yet-existing symbols); no "every affected symbol" overclaim.
- Stale-claim cleanup real: no "node-only / not a parity surface" remains in the skill or the how-to;
  both now say the adapters ARE a parity surface (node ≡ python, T94/T98).
- skill-integrity T92 green (2 adapters, 6 wired proofs, 0 findings).
- Suites: node 316/0 (T98+T99 in GROUPS-PASSED), parity OK, python 88, self-audit 63/60, prose T93 green.
