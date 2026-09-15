# Plan refutation — refuter-economics — ROUND 1 (verdict: UNSOUND)

Refuter: independent general-purpose agent (strong/session model — plan refutation tier).
Doer/plan author: claude-fable-main. Artifact stored verbatim; findings folded into the plan
before round 2.

## Attempts (what I tried to break and how)

1. Byte-parity landmines (RE1): read parity.sh:139-152 (byte cmp of refute-prompt text), refuter-compose.sh (T147), refuter_profiles.py/.js compose, hb.js:592-601, cli.py:53,320; ran the compose on the parity fixture. --json as tasked is additive; but "one compose" and "byte-unchanged" claims enforced more weakly than stated (findings 6, 7).
2. RE2 blast radius: enumerated every review_passed/review_failed consumer (state projections, doctor Sev-1, impact py+node, parity impact case, fuzz — safe, suite pins T32.2/T33.4/T45/T152, test_state.py:51, bench.py:45, mcp_server.py:158-181, exec verdict recording). Found two untasked surfaces: MCP review tool; record-side instruction text (findings 2, 3).
3. Gate quality: audit clean, lint valid; timed every criterion (suite 2m40s vs 900s — timeouts generous); attacked greps for pre-satisfaction: parity-notes review/model grep matches TODAY (line 100); parity.sh 'refute-prompt' grep matches TODAY (line 139); demonstrated the re3z pytest hole: printf '2 failed, 113 passed' | grep -qE '[0-9]+ passed' → matches.
4. Coverage: correctness/default refuter profiles carry NO model field (dogfood claim unwired); --json omitted refute_if (panel unaggregatable); audit --agent routes no model, emits no event; MCP review schema lacks model; interactive record path never gains --model in any task.
5. Doctrine: four guards + Sev-1 rot unweakened (additive field); but self-reported --model vs the plan's own token-rejection epistemics undistinguished (finding 9).
6. Spec-first: re1a/re2a genuinely RED-authorable; plan state fresh (events.jsonl: initialized only).

## Findings

1. BLOCKING — re3z's "py suite green" clause hollow: pytest exit discarded; a failing run still prints a passed-count (demonstrated). Only criterion running the py suite in the whole DAG. Fix: exit code is the verdict.
2. BLOCKING — gap (b) stays open interactively: the record side is never instructed. Skill/PROTOCOL record commands never gain --model; no proof asserts the instruction; net effect: spawn cheap (RE1) then record model:null. Fix: instruct both halves + prose-integrity grep.
3. Weakening — MCP review surface missed entirely (mcp_server.py:158-181 schema {gate, verdict, artifact, note}). Fix: schema + pass-through + proof case.
4. Weakening — re2w's parity-notes grep green today (parity-notes.md:100). Fix: distinctive token.
5. Weakening — re1z's parity grep vacuous (matches line 139 today); wiring greps are the repo's own catalogued filename-grep weakness; re1z's desc said "never a filename grep" while its cmd was one. Fix: distinctive case label + GROUPS-PASSED enforcement at re3z.
6. Weakening — factual premise wrong: NO model: line in the composed prompt (renderSkill only — refuter_profiles.py:47-48). Fix: correct _meta.
7. Weakening — "one compose" enforced only profile-less: json.prompt never byte-pinned to text for the PROFILED fixture. Fix: byte-pin both.
8. Weakening — dogfood claim unwired: correctness.json/default.json carry no model field; the plan's own reviewers would inherit the session model — the exact failure mode the plan describes. Fix: bind the model as plan prep, or drop the claim.
9. Note — self-reported provenance vs the plan's own epistemics (tokens rejected as "self-report"; interactive --model IS one). Fix: trust-boundary in the guide's honest limit.
10. Note — panel (--json lacked refute_if) and audit --agent surfaced as questions, not closed. Fix: emit refute_if; scope both out explicitly.
11. Note — GATE_RE2 guards "proven" python-only (refutation-demo.sh drives cli only); null-model key is a real node/python divergence trap (JS "null" vs py None); no fixture mixes null+named models. Fix: node guard case + mixed fixture.
12. Held: audit clean/0 hollow; timeouts realistic; markers exist; fuzz unaffected; spec-first genuine.

## VERDICT: UNSOUND
Two blocking findings: the exit bar accepts a failing python suite, and the plan's stated purpose (recording which model reviewed) remains open on the interactive path.

---
Disposition by the plan author (round 1 → round 2): ALL findings folded into .hb/dag.json —
re3z exit-code verdict + GROUPS-PASSED T163/T164; record-side --model instruction in re1a(6)/re1b
+ re2w grep; MCP surface in re2a(4)/re2b; distinctive tokens (refute-prompt:json,
review-event model field); _meta premise corrected; profiled-fixture byte-pin re1a(3);
correctness.json binds model sonnet (done); trust-boundary added to RE3's honest-limit spec;
refute_if added to --json; panels/audit-agent explicitly deferred in _meta; node guard case +
mixed null/named impact fixture in re2a(5,6)/re2c.
