# GATE_VS review — `hb viz --serve` (live DAG dashboard, node runtime)

Adversarial review of the shipped work (refute-don't-confirm). Reviewer: a distinct actor
(general-purpose sub-agent), not the implementer. Two rounds.

## Round 1 — plan refutation → UNSOUND (folded before build)
- Snapshot-regression contract was prose-only (no criterion gated "T14 stays green"); vc1's
  snapshot sub-check checked a generic task id, not `P0T1` verbatim. → Tightened the proof's
  snapshot sub-check to the verbatim T14 conditions (`t-done` AND `P0T1`, no external URL).
- 5s per-criterion timeout risk (many node cold-starts + bootstrap). → `HB_NO_GIT=1` bootstrap,
  one reused server, bounded `curl --max-time` polls. Measured: ~0.37s.
- Non-loopback sub-check should prove nothing bound, not just a non-zero exit. → addressed
  (later simplified in round 2, since refusal precedes socket creation).

## Round 2 — implementation refutation → UNSOUND, then SOUND after fixes
Found on the shipped code:
1. PRIMARY — `isLoopbackHost` compared to unbracketed `::1`, but `new URL('http://[::1]').hostname`
   yields the bracketed `[::1]`, so a loopback `[::1]` Origin was wrongly 403'd; and the
   "mirrors py oracle" comment overclaimed (AGENTS rule 7 — a comment is a claim). This
   contradicted the gated `mcp-http.sh` proof + `secure-the-mcp-server.md`, which treat `::1`
   as valid loopback.
2. SECONDARY — the proof's sub-check 4 hardcoded port 8791 with a reachability probe that could
   false-FAIL on a busy host (non-deterministic gate).

Fixes applied (root-cause, gate not weakened):
- `hb-viz.js`: `isLoopbackHost` strips URL brackets (`[::1]` → `::1`); security comment reworded
  to describe the shared DNS-rebinding defence without claiming byte-identical mirroring; the
  listen banner brackets IPv6 hosts.
- `viz-serve.sh`: added a regression assertion that `Origin: http://[::1]` → 200 (locks the fix);
  sub-check 4 dropped the fixed-port probe and uses `--port 0` (refusal precedes `createServer`,
  so no socket can leak — deterministic).

Re-review verdict, verified by running the server + curling hostile/loopback Origins and the full
suite: both defects CLOSED, no new holes, `VIZ-SERVE-OK`, node suite 297 passed / 0 failed
(T1–T86 green incl. T14 snapshot regression).

Out-of-scope note (not claimed as parity, not caused by the fix): node's hand-rolled
`isLoopbackHost` rejects the exotic IPv4-mapped-IPv6 loopback `::ffff:127.0.0.1` that py's
`ipaddress.is_loopback` accepts. viz is node-only and not a parity surface.

**VERDICT: SOUND**
