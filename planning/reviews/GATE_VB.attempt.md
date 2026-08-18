# GATE_VB — bump to v1.25 + STATUS changelog (whole branch)

**Phase:** VB (v1_25-finalize) — bump version files to v1.25 consistently, de-hardcode the version
test, write the STATUS v1.25 entry capturing the entire branch, refresh release/README.md.

**Distinct actor:** reviewer agent (not the doer).

## Refutation attempts (all failed)
- **Version consistency/completeness** — plugin.json `1.25.0`, marketplace heartbeat entry `1.25.0`,
  pyproject `0.15.0`. Repo sweep for `1.24.0`/`0.14.0` finds hits only in the plan file (spec text),
  no stale shipping literal.
- **T39.4 de-hardcoded** — now asserts plugin.json version == marketplace entry version (no literal);
  `! grep -q '1.24.0' tests/run-tests.sh` holds; reviewer mutated a copy to `9.9.9` and confirmed the
  check FAILS on divergence (real teeth). Label "T39.4" preserved.
- **STATUS honesty** — leads with v1.25; the entry covers viz --serve (T86), both adapters + both
  seams (T87/T88/T90/T91), skills + skill-integrity (T92), whole-docs prose gating (T93), T55.2
  de-flake, the parity port node≡python (T94/T95) + node-free (T96), MCP tools (T97). Every cited Tnn
  exists as a suite group. No overclaim (ollama/live references stay on-demand, older sections only).
- **release/README.md** — "New in v1.25" blurb matches reality, no overclaim.
- **Suites** — node 313/0 (incl. T39.4), parity OK, python 85 passed.

**Verdict: SOUND (could not refute).**
