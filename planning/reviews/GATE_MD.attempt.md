# GATE_MD refutation attempt — phase MD (MCP tick tool teaches DRIVING the loop)

**Actor:** distinct-actor skeptic (Agent), separate from the implementer.
**Verdict:** COULD NOT REFUTE — SOUND.

Phase MD closes the interactive-MCP-client drive-loop gap: `py/src/heartbeat/mcp_server.py`'s
`tick` tool now teaches an MCP client (OpenCode, any MCP-capable agent) to call `tick` again until
`all_done`/human-needed — the MCP twin of the SessionStart-hook fix (T143). Proof:
`docs/howto/gate-examples/mcp-drives-loop.sh` (MCP-DRIVES-LOOP-OK / SELFTEST-OK), wired as T144.

## Attacks run (all held)

1. **Real server + RED on pre-fix.** The proof spawns the actual `hb mcp-serve` over JSON-RPC stdio
   and runs `desc_fail` on the real shipped `tick` description (`mcp-drives-loop.sh:102-121`). The
   pre-fix text "Run one Stage-A tick; returns the next action…" fails B2/B3/B4 → genuinely RED.
2. **Per-assertion teeth.** Each of the 4 `desc_fail` near-misses fails exactly one check; the
   payload teeth reject "advancing reason with no next" and "all_done WITH a nudge". Not a hollow
   token-grep — react-only text IS rejected (B2). The "call once, do NOT loop" grep-bypass is
   explicitly disclaimed in the SCOPE header (deterministic grep ≠ contradiction judge); the shipped
   text does not contain it.
3. **Fix scope confined.** `git diff` touches only `_tick` + the tool description in `mcp_server.py`;
   shared `tick.py` and `plugin/` are clean → `tests/parity.sh` = node ≡ python. MCP is Python-only.
4. **Nudge reason-set correct.** Fires on exactly `next_task`/`gate_pending`/`review_pending` (the
   work-advancing wakes, each with a `data.action`); `all_done`, human-needed, and corruption wakes
   get NO nudge. No advancing reason missed; no terminal reason wrongly nudged.
5. **No overclaim.** Docs + dev-tests claim metadata-presence / anti-drift ("teaches driving",
   "carries a nudge"); the proof header states it does not adjudicate whether the LLM obeys.
6. **Wiring.** T144 asserts the markers on the same line the proof runs; enumerated in dev-tests →
   `index-coverage.sh` = INDEX-COVERAGE-OK; node suite 144/144 groups, 0 skipped.

## Minor, non-blocking observations (not holes)

- `desc_fail` over-fits slightly: an exotic paraphrase ("requesting another tick"/"iterate", no
  call/run/invoke verb, no again/loop) would false-fail — acceptable for a first-party anti-drift
  check the author controls; the shipped text passes comfortably.
- The selftest's `good` string is a hand-written near-copy, but the LIVE path validates the real
  shipped description — correct teeth/artifact separation, not drift.

**Result:** GATE_MD is sound — proof is real (drives the server), teeth are load-bearing, fix is
surgical and parity-safe, docs are honestly scoped.
