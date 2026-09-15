# Plan refutation — refuter-economics — ROUND 2 (verdict: SOUND)

Same refuter as round 1 (context retained — round 2 verified the 11 dispositions adversarially
instead of re-hunting). Full text preserved by the plan author from the agent's report.

All 11 round-1 findings: RESOLVED, each verified against today's files (the four new grep
tokens confirmed RED pre-implementation by execution; the re3z pytest exit-code fix attacked
with mixed-fail / zero-collected / missing-venv constructions — all fail closed; GROUPS-PASSED
accumulation format verified against run-tests.sh:1765-1779; MCP fail-path traced through the
shared accept_review writer; dogfood binding read from disk).

Three NEW notes (hardening residue, none blocking):
- NEW-1: the declared RE1→RE2 ordering debt bites exactly once — GATE_RE1's own reviewer must
  record WITHOUT --model (py would refuse loudly; node would swallow it into the note).
  → Disposition: instruction added to GATE_RE1's review prompt.
- NEW-2: GROUPS-PASSED lists zero-check groups (filters _GFAIL only, not _GCHECKS), so re3z's
  wiring enforcement was gameable by a no-op group in bad faith.
  → Disposition: re1c now tasks the suite hardening (membership requires registered checks).
- NEW-3: round-2 spec additions weren't gate-asserted (trust-boundary + deferrals in the guide;
  PROTOCOL-table instruction in both runtimes).
  → Disposition: re3y gained self-report/trust-boundary + deferral greps; re1a(6) extended to
  both PROTOCOL tables; GATE_RE1/RE3 review prompts refreshed.

## VERDICT: SOUND
"Both round-1 blockers are demonstrably closed with runnable evidence; every weakening finding
has a wired disposition verified against today's files rather than the mapping's word; the
three remaining notes are hardening residue that requires bad faith or affects only
reviewer-prompt breadth, not the load-bearing claims."
