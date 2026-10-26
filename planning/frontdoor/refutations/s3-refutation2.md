# GATE_S3 refutation attempt 2 (phase S3, wave 5: docs for the shape contract and the fail-closed readers)

Refuter: an independent reviewer, not the doer. All probes ran in `mktemp -d` bootstraps
(`HB_NO_GIT=1 STUCK_TICKS=999`, HB_DIR/PROJECT_DIR/GATE unset). The repo tree was not modified:
`git status --short` lists the same 19 entries before and after.

## Checkers run this round
- `bash tests/dag-shape.sh lint` printed `SHAPE-LINT-OK (94 derived structure mutations, 100 existing dags against the a500587 oracle)` with rc=0. k3 holds, so the lint change left every git-tracked dag's lint output unchanged.
- `bash tests/dag-shape.sh readers` printed `SHAPE-READERS-OK (94 derived mutations …; 5 representatives through every verb, gate mode, driver and MCP tool)` with rc=0. That run includes the new r17.

## The lint change (re-verified)
- `hb-lint.js:153` and `lint.py:245` now call `shapeErrors(dag, true)` / `shape_errors(dag, True)`.
- The criteria-entry rule (`hb-lint.js:223`, `lint.py:316`) now fires only for an OBJECT entry with a non-string cmd. A non-object entry still produces exactly one line, now emitted by the shape walk, so no line is duplicated and none is lost.
- `grep -rn 'shapeErrors(\|shape_errors('` finds every caller passing true (tick.sh:153, gate.sh:233, hb.js:253, hb-next-task.js:90, hb-audit.js:118/208, hb-report.js:26, hb-viz.js:41, state.py:41, resolver.py:76, audit.py:132, cli.py:461). The new comments are therefore accurate. python's `entries=False` default is unused.

## Probe for G1: the constraint's exact fixture
The plan is P1→G1 / P2→G2 (t2 requires t1) with `G1.criteria=[5]` and `G2.criteria="x"`. On both runtimes, every surface below now leads with the same error:
- node and py lint `--json`: `["[G1] criteria entry 0 must be an object with a string cmd (got a number)", "gates.G2.criteria must be a list"]`.
- Both ticks' `errors`, and both resolvers' `detail.errors`: the identical list.
- `hb.js state` / `hb state` refusals.
- doctor's first `✗ dag:` line (node and py).
- audit `[dag_shape]` (node and py).
- `diagnose` → `Diagnosis: dag_corrupted` plus that line (node and py).

Lint's order is now the readers' order. A second variant (an object entry with `cmd:5` plus `G2.criteria="x"`) puts `gates.G2.criteria must be a list` first in both lints and in the tick. These five sentences are now literally true:
- parity-notes.md:513 ("lint's own order — … the same entries-mode walk")
- dev-plugin.md:141 and 155
- the how-to l.52-53
- SKILL.md:186-187
- the-auditor-catches-each-weakness.md:29

r17 (dag-shape.sh:757-771) pins it on all of them.

## Probe for G2
- `grep -c dag_corrupted docs/howto/diagnose-a-stuck-project.md` prints 1. The bullet at l.26-28 names what diagnose prints (the first structure error), the restore-or-fix cure and doctor's structure-only output.
- The deadlock bullet (l.23-25) now names `Cause: resolver_error` with the cure "(restore `.hb/hb-next-task.js`, or repair the python install)". This matches hb.js:550 ("restore .hb/hb-next-task.js from the plugin templates") and doctor.py:269 ("repair the heartbeat install").
- The hook text (mktemp `CLAUDE_PROJECT_DIR`) reads "When blocked (… / criteria_drift / dag_corrupted), run `node .hb/hb.js diagnose`".

## Probe for G3
README.md:147 no longer says "validate against". It now says the schema "documents the format", that `hb lint` is the judge of STRUCTURE (`x-hb-structure`), and that readers refuse a broken plan. `grep -rn schema.json plugin/templates plugin/bootstrap.sh py/src/heartbeat` returns only hb-lint.js:26 and lint.py:17 (comments). G3's literal failure condition is gone. The bullet's closing clause is still false, though: see F1.

## Earlier-round constraint drafts (s3-gate-constraints3.json), re-verified
- **Comments and documented call.** The shapeErrors comments and dev-plugin's Lint paragraph (l.155: "`shapeErrors(dag, true)` — the entries mode every caller uses") describe the call the code makes. This holds.
- **Range labels.** `grep -rn 'r0-r16'` finds nothing. dag-shape.sh:17, run-tests.sh:2014 and parity-notes.md:525 all say r0-r17. The T186 row in dev-tests.md ends with "lint's first error is every reader's first error (one walk, one order)". This holds.
- **How-to scoping.** l.56-58 exempts `code_context`/`code_discover`/`deplint`, which matches `_SHAPE_FREE` (mcp_server.py:195) and r8's `MCP_EXEMPT`. l.59 says "node's `hb-lint.js` … every node reader", which matches r11. This holds.

## Other claims checked and found true
- The how-to's anchors k1-k7 and r0-r17 exist (dag-shape.sh case headings) and assert what each sentence says. Checked: r3 no event and dag untouched; r4 one line plus the lint command; r5 exit 4 on G1, `--check` and `--all`, re-probed this round as rc=4/4/4; r6/r6b doctor/diagnose; r9 structure before state; r16 one event per blockage.
- The CLI class lists in dev-plugin.md:141 and dev-python.md:217 equal `SHAPE_CHECKED` (hb.js:1113) and `_shape_checked` (cli.py:122).
- Honest limits re-probed:
  - Empty `phases` makes both ticks sleep (`no_pending_tasks`).
  - `review.constraints=[5]`: python `hb exec` dies with `AttributeError: 'int' object has no attribute 'get'` (a traceback), while node stops with `review_error`.
  - A criterion without an `id` lints clean, and gate output renders `✓ []` on node and `✓ [None]` on py.
- The T184 row's id-less-phase claim is asserted at replan.sh:161-183.
- Stop lists (SKILL:228-230, drive-heartbeat-over-mcp.md:62-64, the hook, the MCP tick tool via r12) name `dag_corrupted` and `state_corrupted`.
- `immutable` survives only in archived `planning/*/.hb` copies and refutation files, not in current-state docs.
- The notifier lists (README:303, dev-plugin:106) correctly omit `dag_corrupted`, since tick.sh never calls `notify` for it.

## Findings

### F1: README.md:147 says every non-structure optional field's type is unenforced, which is false
The bullet ends "`hb lint` is the judge of its STRUCTURE (the nodes the schema marks `x-hb-structure`) … — the other optional fields' types are documented, not enforced". `horizon` and `review` are optional and are not `x-hb-structure`: a walk of `plugin/dag.schema.json` lists the 15 STRUCT nodes, and neither is among them. Lint rejects a wrong type for both. The probe used `{"phases":[{"id":"P1",…,"horizon":"yes",…}],"gates":{"G1":{"review":true,…}}}`:
- `node hb-lint.js d.json --json` printed rc=1 with `["[P1] horizon must be true or false (the knowledge-horizon marker)","[G1] review must be a non-empty object ({prompt, profile?, constraints?})"]`.
- `hb lint d.json --json` printed the same bytes, rc=1.

SKILL.md:96-99 and dev-plugin.md:102 give the carve-out: horizon, cmd, review, regate and the detach fields keep their own lint rules, and timeout_s is checked by the runner. They also state that a criterion's REQUIRED `id` is unenforced. README, the twin G3 was meant to align, carries neither. It contradicts lint on horizon, review, regate and the detach fields. It is also silent on the one required field nothing checks.

### F2: dev-plugin.md's gate.sh exit-code table is stale against the wave's exit 4
In the "Gates — `gate.sh`" table (dev-plugin.md:110-114), the Exit column reads:
- `gate.sh <GATE>`: "pass 0 / blocked 1 / unknown 2"
- `--check`: "would-pass 0 / would-block 1"
- `--all`: "0 / 1"

gate.sh:234 exits 4 on an unreadable or structure-invalid plan in every mode, and r5 asserts it. Re-probed this round with `phases[0].tasks="x"`, the three modes exited rc=4, 4 and 4. The file table in the same doc (dev-plugin.md:29) was updated to "Exit 0 pass / 1 blocked / 2 usage or unknown gate / 3 regate pending / 4 …". The section that documents gate.sh's exits per invocation was not updated, so the doc contradicts itself. Exit 3 was already missing before this wave; exit 4 is this wave's omission. P1 names "an exit-code table … is stale" as a violation.

### Side notes (pre-existing, not owned by this plan)
- The dev-plugin Lint "Errors (exit 1)" list (l.157) still omits the duplicate-phase-id error and the object-entry `cmd` rule.

## Answers

P1: VIOLATED — README.md:147 says "the other optional fields' types are documented, not enforced", but `node hb-lint.js` and `hb lint` both exit 1 on `horizon:"yes"` / `review:true` with `[P1] horizon must be true or false …` / `[G1] review must be a non-empty object …` (hb-lint.js horizon/review rules). Separately, dev-plugin.md:112-114's gate.sh exit-code table still lists only 0/1/2 (`--check` 0/1, `--all` 0/1), while gate.sh:234 exits 4 in every mode: probed rc=4 for `G1`, `--check G1` and `--all` on `phases[0].tasks="x"`, and r5 asserts it.
P2: NOT-REPRODUCED — SKILL.md:94-101 and the how-to l.22-25, l.63-78 say lint judges STRUCTURE only and carve out the fields with their own checks. They state the unenforced criterion `id` (probed: lint rc=0, gate `✓ []` / `✓ [None]`), the refute-prompt crash (probed: python exec traceback `AttributeError`) and the empty-phases sleep (probed: `no_pending_tasks` on both). Every dag_corrupted row (SKILL:371, README:211, CLAUDE-MD-SNIPPET:52) gives lint, then restore or fix, and "Never hand-edit state.json". No invented route or state.json edit found. README's omission is reported under P1.
G1: NOT-REPRODUCED — on the constraint's exact mktemp fixture, both lints' `--json`, both ticks' `errors`, both resolvers' `detail.errors`, both `state` refusals, both doctors' first `✗ dag:`, both audits' `[dag_shape]` and both diagnoses all lead with `[G1] criteria entry 0 must be an object with a string cmd (got a number)`, then `gates.G2.criteria must be a list`. One order now, from `shapeErrors(dag, true)` at hb-lint.js:153 / lint.py:245, pinned by r17, and the `readers` run is green.
G2: NOT-REPRODUCED — `grep -c dag_corrupted docs/howto/diagnose-a-stuck-project.md` = 1, and the bullet at l.26-28 names the first error and the restore-or-fix cure. The deadlock bullet (l.23-25) names `Cause: resolver_error` with cures matching hb.js:550 / doctor.py:269. The hook text, probed, routes dag_corrupted to `node .hb/hb.js diagnose`.
G3: NOT-REPRODUCED — README.md:147 no longer says "validate against". It says the schema documents the format and `hb lint` judges the `x-hb-structure` STRUCTURE. The schema.json grep returns only the comments hb-lint.js:26 / lint.py:17. The bullet's remaining false clause is reported under P1 (F1).

REFUTED
