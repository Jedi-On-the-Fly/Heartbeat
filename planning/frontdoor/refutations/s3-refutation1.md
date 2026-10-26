# GATE_S3 refutation attempt 1 (phase S3, wave 5 "the shape contract": tasks s3a, s3b, s3c)

Refuter: an independent reviewer, not the doer. Every probe ran in a `mktemp -d` bootstrap
(`HB_NO_GIT=1 STUCK_TICKS=999`, HB_DIR/PROJECT_DIR/GATE unset) or as an allowed checker from the
repo root. The repo tree is unchanged (`git status --short` is the same 15 entries before and after).

Checkers run this round:
- `bash tests/dag-shape.sh` printed `SHAPE-LINT-OK (94 derived structure mutations, 100 existing dags …)`, `SHAPE-READERS-OK (94 …)` and `DAG-SHAPE-OK` (2m59s).
- `bash docs/howto/gate-examples/audit-rules-check.sh` printed `AUDIT-RULES-PROVEN:12`.
- `prose-check.sh` on the 11 s3w files printed `ALL-PROSE-OK:11`.

## Findings

### F1: the how-to's MCP sentence is false, and its anchor r8 asserts something different
`docs/howto/a-malformed-plan-fails-closed.md:55-56` says: "MCP tools answer by class — `tick` wakes,
`next` says `dag_invalid`, lint/audit/doctor report, the rest return an error result (r8)."
- Code: `py/src/heartbeat/mcp_server.py:195` `_SHAPE_FREE = {"tick", "next", "lint", "audit", "doctor", "diagnose", "code_context", "code_discover", "deplint"}`, so `diagnose` is in the report class.
- Test: `tests/dag-shape.sh:448` `MCP_REPORT="lint audit doctor diagnose"` and `MCP_EXEMPT="code_context code_discover deplint"`. r8 asserts that diagnose REPORTS (no isError) and skips the three code tools entirely.
- Probe: `m._handle(...)` on a bootstrap with `phases[0].tasks="x"` printed `diagnose isError= None {"diagnosis": "Diagnosis: dag_corrupted\n  phases[0].tasks must be a list …`. That is a report, not an error result. The code tools fail on their missing arguments (`'codemap'`, `'dag'`), not on the plan.

So "the rest return an error result" is false for `diagnose`, and the cited case r8 asserts the
opposite of the sentence. The refute prompt's G6 names exactly this case as a wrong anchor.
`docs/dev-python.md` (the mcp_server row: "lint/audit/doctor/diagnose report, `code_context`/`code_discover`/`deplint` are dag-independent") gets it right, so the how-to and the dev doc disagree.

### F2: the dev-plugin file table's `Module exports` cells are wrong for three files this wave extended
This wave changed `hb.js` (+39), `hb-audit.js` (+71) and `hb-report.js` (+5). Source: `git diff 8b0b197 HEAD --stat -- plugin/templates`.
- `hb-audit.js`: the cell says `audit, classify, isNondet`. `Object.keys(require('./hb-audit.js'))` printed `audit, classify, isNondet, reviewQuestions, nonBehavioral` (hb-audit.js:234). Two exports are missing from the cell.
- `hb.js`: the cell lists 5 names. The module exports 19 (hb.js:1101), including `checkAnswers`, `checkHoles`, `changed`, `withWlock` and others.
- `hb-report.js`: the cell says `refuterImpact`. The file has no `module.exports`, and `require('./hb-report.js')` runs the CLI and prints `Usage: hb-report.js <hb-dir> [--json]`.

The hb-lint.js row (`lint, extractPaths, constraintErrors, readDagFile, shapeErrors, structureView`) and the
hb-next-task.js row (`resolve, readyTasks`) are now correct. However, G2's failure condition also covers "any other
row's cell names an export the file does not have / omits one it has". The three rows above fail that test on files the wave extended.

### F3: an unstated honest limit — a criterion's REQUIRED `id` is enforced by nothing
`plugin/dag.schema.json` marks the criteria entry `x-hb-structure: true` with `required: ['id', 'cmd']`.
Three docs read as if required fields are enforced:
- `docs/dev-plugin.md` Lint says `shapeErrors(dag)` "reports every violation of the nodes … annotates `x-hb-structure` (containers, required ids, …)".
- Its data-model table types the criterion as `criteria[]{id, desc?, cmd, timeout_s?}`, with `id` not optional, and then says only "the remaining OPTIONAL fields' types are documented, not enforced".
- The SKILL and the how-to's Honest limits likewise speak only of "optional" fields.

Probes in a bootstrap with the base dag, where only the criterion changes:
- `del criteria[0]["id"]` → node `hb-lint.js` rc=0 and `hb lint` rc=0.
- `bash .hb/gate.sh G1` passes and prints `✓ [] behavioral`. `hb gate G1` passes and prints `✓ [None] behavioral` (the two runtimes render the label differently).
- doctor reports `healthy` on both.
- `criteria[0]["id"]=5` → lint clean on both, and the gate passes on both.

So a field the schema requires on a STRUCTURE node is unchecked everywhere. No doc states this limit, and
the docs' "optional fields are unenforced" wording implies the opposite. The plan's _meta placed
"the criterion entry's FIELDS id/cmd/desc/timeout_s" outside STRUCTURE on purpose. The docs that
ship to agents did not carry that over: they list `cmd` and `timeout_s` but leave out `id`.

### F4: "Every claim below is anchored" is false for the Honest limits
`a-malformed-plan-fails-closed.md:7-8` says "Every claim below is anchored to a case in `tests/dag-shape.sh`". The
Honest limits paragraph (l.63-73) makes behavioral claims with no case id:
- "the tick sleeps on" an empty-phases plan. k2 asserts only that this plan lints valid (dag-shape.sh:183-184). No case asserts the sleep.
- "refute-prompt can still crash … the exec driver stops on it". No case.

Both claims are TRUE in my probes (see G7 below), but the anchoring claim is not.

### Side notes (pre-existing or minor, not the basis of the verdict)
- With `review: {"profile": 5}` or `{"prompt": 5}`, python `hb exec run` ends in a raw Traceback (`TypeError: argument of type 'int' is not iterable` / `unsupported operand type(s) for +`), rc=1. Node stops with `HB-EXEC STOP: review_error — G1: eff.includes is not a function`. The how-to's "the exec driver stops on it" holds loosely (rc 1). The plan _meta's "hb exec stops on them with review_error" holds only on node.
- `planning/parity-notes.md` new section: "`SHAPE_CHECKED` in hb.js ≡ `_shape_checked` in cli.py". The two sets differ (node: beat, anchor, import, drift; python: report, reward, bench). Each set is complete for its own runtime, so this is a symbol choice, not a false behavior claim.
- `plugin/hooks/heartbeat-detect.sh`'s "When blocked (…) run diagnose" list does not name `dag_corrupted`, although diagnose handles it.
- The how-to's r11 sentence ("every reader fails closed") is node-only by nature (hb-lint.js). It does not say so, but python ships its checker in-package.

## Per-constraint probes

Probe for G1: tick.sh:154/156 (`touch` + `log_event` once, then `rm -f "$DAGBAD_FLAG"` right after the shape guard), tick.sh:289 (`rm -f "$RESERR_FLAG"` on any verdict that is not cause resolver_error) and tick.sh:326-327 (resolver_error never touches `$DEADLOCK_FLAG`). The python side matches: tick.py:53-58 `_dag_corrupted_wake` and tick.py:102-103 `_rm` after the guard. dev-plugin.md:107 now lists both flags inside the "Once" parenthesis, with "cleared once the plan's structure is sound" and "cleared on a usable resolver answer … never arms `.deadlock-alerted`". Both agree with the code. r15/r16 are green.

Probe for G4: I listed the schema properties per level (root `$schema,_meta,gates,phases,project`; phase 13 fields; task `description,id,note,requires,title`; gate `desc,review,criteria,regate`). dev-plugin.md:83-86 names every one of them, `gate_exit` is typed `gateId|null`, and the table points at Lint for STRUCTURE.

Probe for G5: STATUS.md:1159-1161, README.md:158-159 and the dev-plugin tick table row 1.5 all put the structure check first ("unreadable or structurally malformed"). In tick.sh the shape guard (l.153-154) runs before the state block (l.160). r9 is green.

Probe for G6: run-tests.sh:2014 and dag-shape.sh:17 now say `(r0-r16)`, and parity-notes says `readers (r0-r16)`. Every k/r id the how-to cites exists. The r8 anchor is wrong (F1).

Probe for G7:
- (a) On a bootstrap with `phases[0].tasks="x"`, `node .hb/hb.js state` and `hb state` each gave rc=1, stdout 0 bytes and stderr 1 line.
- (b) `hb-report.js .hb` and `hb-viz.js .hb` gave rc=1, and `cmp` showed the lines identical to each other and to hb.js's line.
- (c) `{"phases":[],"gates":{}}` lints clean, and both ticks return `wakeAgent:false no_pending_tasks`. `refute-prompt G1` with `review:{"profile":5}` gives node rc=1 (`eff.includes is not a function`) and python rc=1 (TypeError).
- (d) A dag with 8 structure errors gives `errors` with 5 entries on both ticks, `cmp`-identical to each other and equal to the first 5 of `hb lint --json`.

Probe for G3: the SKILL (l.234-241) and the how-to (l.63-66) now name horizon/cmd/review/regate(/detach) as lint errors and say the runner fails an invalid timeout_s. Lint probes:
- `horizon="yes"` → `[P1] horizon must be true or false` on both, exit 1.
- `cmd=5` → the criteria-entry error on both.
- `timeout_s="abc"` → `invalid timeout_s: 'abc'` and the criterion fails on both.
- title/desc/note/description/parked_reason/project/criteria desc/review.prompt/review.profile/undeclared key → all lint rc=0 on both.

The narrowed sentences are true as far as they go (F3 is the gap they leave).

## Answers

P1: VIOLATED — docs/howto/a-malformed-plan-fails-closed.md:55-56 says "lint/audit/doctor report, the rest return an error result (r8)", but the MCP `diagnose` tool reports. The probe `m._handle(hb, tools/call diagnose)` on a `phases[0].tasks="x"` bootstrap returned `isError=None {"diagnosis": "Diagnosis: dag_corrupted …"}`, `_SHAPE_FREE` (mcp_server.py:195) contains diagnose, and r8's own `MCP_REPORT="lint audit doctor diagnose"` (dag-shape.sh:448) asserts the opposite of the sentence. Also the how-to's l.7-8 "Every claim below is anchored to a case" does not hold for the Honest limits (the empty-phases tick sleep and the refute-prompt crash cite no case).
P2: VIOLATED — an honest limit is hidden. The schema's STRUCTURE criteria entry is `required: ['id','cmd']`, yet a criterion with no `id` (or `id: 5`) lints clean on both runtimes (node rc=0, `hb lint` rc=0), passes `gate.sh G1` (`✓ [] behavioral`) and `hb gate G1` (`✓ [None] behavioral`), and doctor says healthy. Still, dev-plugin.md Lint claims shapeErrors reports "every violation of the nodes … annotates x-hb-structure (containers, required ids, …)", its data-model table types `id` as non-optional while saying only optional fields are unenforced, and the SKILL's plan rule and the how-to's Honest limits name only optional fields.
G1: NOT-REPRODUCED — dev-plugin.md:107 names `.dag-corrupted-alerted` (cleared once the structure is sound) and `.resolver-error-alerted` (cleared on a usable resolver answer, never arms `.deadlock-alerted`). That matches tick.sh:154-156, tick.sh:289 and tick.sh:326-327, and tick.py:53-58 with the `_rm` at l.103. r15/r16 green in this round's `bash tests/dag-shape.sh`.
G2: VIOLATED — the hb-lint.js and hb-next-task.js cells are now correct, but the cells for three files this wave extended do not match their exports. hb-audit.js reads `audit, classify, isNondet` while `node -e "Object.keys(require('./plugin/templates/hb-audit.js'))"` prints `audit, classify, isNondet, reviewQuestions, nonBehavioral` (hb-audit.js:234). hb.js lists 5 of its 19 exports (hb.js:1101). hb-report.js claims `refuterImpact` while the file has no module.exports and `require` runs the CLI (`Usage: hb-report.js <hb-dir> [--json]`). G2's clause "any other row's cell names an export the file does not have / omits one it has" covers all three.
G3: NOT-REPRODUCED — SKILL.md:234-241 and the how-to's Honest limits now list horizon/cmd/review/regate as lint errors and timeout_s as runner-checked. Probes: `horizon="yes"` and `cmd=5` exit 1 on both lints; `timeout_s="abc"` fails the criterion on gate.sh and gate.py (`invalid timeout_s: 'abc'`); title/desc/note/project/review.profile lint rc=0 on both, so the remaining "not enforced" wording is literally true.
G4: NOT-REPRODUCED — dev-plugin.md:83-86 lists every schema property per level (root 5, phase 13, task 5, gate desc/criteria{id,desc,cmd,timeout_s}/review{prompt,profile,constraints}/regate{…rearm}), types gate_exit as `gateId|null` like the schema's `["string","null"]`, and points at Lint for x-hb-structure. This was checked against a python listing of plugin/dag.schema.json.
G5: NOT-REPRODUCED — STATUS.md:1159-1161, README.md:158-159 and dev-plugin tick table row 1.5 all put the dag.json structure check (unreadable or structurally malformed) first and the state self-heal after it, matching tick.sh:153-156 before l.160. r9 green.
G6: VIOLATED — the range enumerations now agree (`(r0-r16)` at dag-shape.sh:17, run-tests.sh:2014 and parity-notes), but the how-to's r8 citation is a wrong anchor. The how-to says "lint/audit/doctor report, the rest return an error result (r8)", while r8's report class is `MCP_REPORT="lint audit doctor diagnose"` (dag-shape.sh:448) and the MCP diagnose probe returned a non-error `Diagnosis: dag_corrupted` result. This is the exact wrong-anchor example the constraint gives.
G7: NOT-REPRODUCED — (a) `node .hb/hb.js state` and `hb state` on `tasks="x"`: rc=1, stdout 0 bytes, stderr 1 line; (b) hb-report.js and hb-viz.js print byte-identical lines (cmp) equal to hb.js's line, rc=1; (c) `{"phases":[],"gates":{}}` lints clean and both ticks return `wakeAgent:false no_pending_tasks`, and refute-prompt with `review:{"profile":5}` exits 1 on node (`eff.includes is not a function`) and python (TypeError); (d) with 8 structure errors both ticks carry 5 errors, cmp-identical and equal to the first 5 of `hb lint --json`.

REFUTED
