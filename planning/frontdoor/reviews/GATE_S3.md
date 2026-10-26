# GATE_S3 refutation attempt 3 (phase S3, wave 5: docs for the shape contract and the fail-closed readers)

Refuter: an independent reviewer, not the doer. All probes ran in `mktemp -d` fixtures (`HB_NO_GIT=1 STUCK_TICKS=999`, HB_DIR/PROJECT_DIR/GATE unset), and every fixture was removed afterwards. The repo tree was not modified: `git status --short` lists the same 19 entries before and after.

## Checkers run this round
- `bash tests/dag-shape.sh lint` printed `SHAPE-LINT-OK (94 derived structure mutations, 100 existing dags against the a500587 oracle)`. Under k3, this means no git-tracked dag's lint output moved after the lint change.
- `bash tests/dag-shape.sh readers` printed `SHAPE-READERS-OK (94 derived mutations through the core readers; 5 representatives through every verb, gate mode, driver and MCP tool)`. It exited 0, and the run includes r8, r11 and r17.
- `bash docs/howto/gate-examples/audit-rules-check.sh` printed `AUDIT-RULES-PROVEN:12`. That matches the auditor how-to's new "twelve findings" and its `-> AUDIT-RULES-PROVEN:12` line.

## Cycle-2 holes, re-verified

### README.md:147 (cycle 2's F1): fixed
The bullet now names the fields that keep their own lint rules: `horizon`, `cmd`, `review`, `regate` and the detach fields. It says `timeout_s` is checked by the runner, and it states the honest limit that a criterion's `id` is documented, not enforced.

I walked `plugin/dag.schema.json`:
- The 15 `x-hb-structure` nodes are the ones the bullet and the how-to describe.
- The remaining optional props are `desc`, `title`, `description`, `note`, `parked_reason`, `project`, `_meta`, `$schema` and `criteria[].desc`. None of them has a lint rule.

Probes:
- `{horizon:"yes", review:true}` makes `node hb-lint.js --json` exit 1 with the `horizon` and `review` errors.
- `{title:5, zzz:1, task title:[], gate desc:7, top-level extra:true}` lints `{"errors":[],"warnings":[]}` on both runtimes.

The bullet is now literally true.

### dev-plugin.md gate.sh exit table (cycle 2's F2): fixed
The table's rows now read:
- `gate.sh <GATE>`: 0 / 1 / 2 / 3 / 4.
- `--check`: 0 / 1 / 3 / 4.
- `--all`: 0 / 1 / 4.

A footnote says every mode checks structure first (exit 4, no event), ahead of usage (2) and a pending regate (3). Code: gate.sh:234 (exit 4, before everything), :310/:315 (exit 2), :322 (exit 3, before the `--check` branch at :329). Probed exits: `--check NOPE`=2, `--check` with no argument=2, `NOPE`=2.

### dev-plugin.md:175 Lint "Errors (exit 1)" additions: true
- The duplicate phase ID rule is scoped to non-empty string ids, which matches hb-lint.js:166-170.
- "An object criteria entry whose `cmd` is not a string" matches hb-lint.js:223-225 (`isObj(c) && typeof c.cmd !== 'string'`). The non-object entry now comes from the shape walk.

## Probe for G1: shapeErrors comments and dev-plugin's Lint paragraph
- hb-lint.js:89-91 now says "Every caller passes true — lint, audit and every reader — so they all walk ONE order … lint's own criteria-entry rule then reports only OBJECT entries with a non-string cmd". lint.py:141-142 says the same.
- `grep -rn 'shapeErrors(\|shape_errors('` shows every call site passes true: tick.sh:153, gate.sh:233, hb.js:253, hb-next-task.js:90, hb-audit.js:118/208, hb-report.js:26, hb-viz.js:41, hb-lint.js:153, state.py:41, resolver.py:76, audit.py:132, cli.py:461, lint.py:245.
- dev-plugin.md:173 documents `shapeErrors(dag, true)` as "the entries mode every caller uses (lint, audit and every reader walk ONE order, so lint's first error is every reader's first error)". dev-python.md's lint.py row describes the same walk.

The constraint's exact fixture is P1→G1 / P2→G2 with `G1.criteria=[5]` and `G2.criteria="x"`:
- `node hb-lint.js --json` gives `["[G1] criteria entry 0 must be an object with a string cmd (got a number)", "gates.G2.criteria must be a list"]`.
- `lint.shape_errors(d, True)` gives the identical pair.
- The node and py audits both print `✗ [dag_shape] … [G1] criteria entry 0 …`.
- r17 (green) pins the same first error across both ticks, both resolvers, both refusals and both doctors.

## Probe for G2: range labels and the T186 row
- `grep -rn 'r0-r1' tests/dag-shape.sh tests/run-tests.sh planning/parity-notes.md docs` finds only `r0-r17`: dag-shape.sh:17, run-tests.sh:2014 and parity-notes.md:525.
- r17 is at dag-shape.sh:757.
- dev-tests.md:189 (the T186 row) ends "lint's first error is every reader's first error (one walk, one order)".

## Probe for G3: the how-to's scoping
- **MCP sentence.** Lines 56-58 now read "the three tools that never read the project's plan (`code_context`, `code_discover`, `deplint`) are exempt, and the rest return an error result (r8)". That matches `_SHAPE_FREE` (mcp_server.py:193) and r8's `MCP_EXEMPT="code_context code_discover deplint"` (dag-shape.sh:448).
- **Missing-checker sentence.** Line 59 reads "If node's `hb-lint.js` itself is missing or outdated, every node reader fails closed", which matches r11's heading (dag-shape.sh:687) and its node-only probes. The python readers use the in-package lint.py.

## Final hunt: other claims checked and found true
- **Honest limits, re-probed.**
  - A dependency cycle lints `dependency cycle: a → b → a` on both runtimes. The node tick wakes `deadlock` with `next_task.cause=dag_invalid`, the python `next` gives `{"type":"deadlock","cause":"dag_invalid"}`, and nothing wakes `dag_corrupted`. This matches how-to l.71-72.
  - Undeclared keys and wrong-typed `title`/`desc` lint clean and the tick dispatches. This matches l.65-66.
- **Doc lists match the code.**
  - The CLI class lists in dev-plugin.md:153 and dev-python.md equal `SHAPE_CHECKED` (hb.js:1113-1114) and `_shape_checked` (cli.py:122-123).
  - dev-python's gate row "exit 4 … checked before every mode" matches cli.py:125.
  - The auditor how-to's `dag_shape` row ("the first structure error, as hb-lint reports it") matches hb-audit.js:118-119.
- **Every dag_corrupted row says the same thing.** The rows are README:211, CLAUDE-MD-SNIPPET:52, SKILL:371, PROTOCOL in hb.js:55 and protocol.py:15. Each says: unreadable or structurally malformed; lint; restore or fix; never hand-edit `state.json`.
- **Stop lists and "immutable".** The stop lists (SKILL:230, drive-heartbeat-over-mcp.md:63, hook l.15/18) name `dag_corrupted` and `state_corrupted`. `immutable` survives in no current-state doc; r1 asserts its absence from the action.
- **Integrity lines.** README:158 and STATUS:1160 order the dag check before the state self-heal, which matches tick.sh:151-168 and tick.py:100-111.

## Side notes (pre-existing or non-exhaustive, not owned by this plan)
- The `--check` row of dev-plugin's gate.sh table omits exit 2 for usage or unknown gate (probed rc=2). The footnote directly below says every mode checks structure "ahead of usage (2)", so the doc as a whole states it. Exit 2 is not this wave's surface.
- The dev-python `gate` row still names only exit 1 and the new exit 4, not 2 or 3. This omission predates the wave.
- The dev-plugin Lint "Errors (exit 1)" list does not enumerate the regate, detach or reserved-gate-id rules. They are documented as lint rules in the Data model note (l.52) and the Regate/Detach paragraphs. This omission predates the wave.

## Answers
P1: NOT-REPRODUCED — I checked every changed claim against the code and the green `dag-shape.sh` lint and readers runs. README.md:147's field carve-out holds: horizon and review rules fire, title, desc and undeclared keys lint clean. dev-plugin's gate.sh exit table lists 3 and 4, matching gate.sh:234/:322. The Lint error additions match hb-lint.js:166-170/:223-225. The T186 and T184 rows, the stop lists, the dag_corrupted rows and the audit count of 12 (`AUDIT-RULES-PROVEN:12`) are current. No `immutable` remains in current-state docs.
P2: NOT-REPRODUCED — SKILL.md:94-101, the how-to l.11-25/63-78 and README:147 say lint judges STRUCTURE only and carve out the fields that keep their own checks. They state the unenforced criterion `id` and empty `phases` limits and the refute-prompt crash limit. Every dag_corrupted row gives lint, then restore or fix, then "Never hand-edit state.json". I probed the cycle case: it is `dag_invalid` deadlock, not `dag_corrupted`, as l.71-72 says.
G1: NOT-REPRODUCED — hb-lint.js:89-91 and lint.py:141-142 now say every caller passes true, and grep confirms all 15 call sites do. dev-plugin.md:173 documents `shapeErrors(dag, true)` as the one-walk entries mode. On the constraint's fixture, both lints, both audits and `shape_errors(d, True)` lead with `[G1] criteria entry 0 must be an object with a string cmd (got a number)`. SHAPE-LINT-OK holds (k3 unchanged).
G2: NOT-REPRODUCED — grep finds `r0-r17` at dag-shape.sh:17, run-tests.sh:2014 and parity-notes.md:525, and no `r0-r16` anywhere. r17 is at dag-shape.sh:757. The dev-tests.md:189 T186 row ends "lint's first error is every reader's first error (one walk, one order)".
G3: NOT-REPRODUCED — how-to l.56-58 exempts `code_context`/`code_discover`/`deplint`, the same as `_SHAPE_FREE` (mcp_server.py:193) and r8's `MCP_EXEMPT` (dag-shape.sh:448). l.59 scopes the missing-checker sentence to "node's `hb-lint.js` … every node reader", the same as r11 (dag-shape.sh:687). The readers run is green.

CLEAR
HOLES: none
