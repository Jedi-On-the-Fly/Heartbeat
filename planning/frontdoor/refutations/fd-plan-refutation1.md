# Refutation round 1: planning/frontdoor.dag.json (S1/S2/S3)

Scope: everything was read-only. Probes ran only in `mktemp -d` dirs and scratch copies. Nothing was run against the repo's own `.hb/`. H1/H2 are byte-identical to `planning/horizon.dag.json` (phases[0:2] and GATE_H1/GATE_H2 compared with json.dumps). Both lints pass the plan at 0/0, and both audits report 0 warnings.

Re-ran the plan-time probes: `w5/probe.sh` and `w5/probe-tick.sh` reproduce the `_meta` evidence (outputs are in `scratchpad/r1/probe.out` and `probe-tick.out`). One caveat: probe-tick runs `ptick` in the same project right after `ntick` has already leased a task, so the python column reads `at_capacity` where a fresh project would read `next_task`. That column is not independent evidence. My own value-tier probe is `scratchpad/r1/vprobe.sh`, which uses a fresh bootstrap per reader and a completed a1.

Measured runtimes: replan.sh 19s, horizon.sh 58s, parity.sh 11s, parity-fuzz.sh 8s. All four are currently green.

---

## F1 (CRITICAL): s3y can never pass, because the GROUPS-PASSED grep cannot match adjacent groups

GATE_S3 s3y: `grep 'GROUPS-PASSED:' | grep -q ' T184 .* T185 .* T186 '`. run-tests.sh:2014 prints `GROUPS-PASSED: … T184 T185 T186 ` (grp order: T184 at l.1989, T185 at l.2000, T186 wired after). The literal ` T184 ` consumes the only space before `T185`, and the next literal ` T185 ` needs one more space.

```
$ printf 'GROUPS-PASSED: T182 T183 T184 T185 T186 \n' | grep 'GROUPS-PASSED:' | grep -q ' T184 .* T185 .* T186 ' && echo MATCH || echo NOMATCH
NOMATCH
```

S3 blocks permanently on a green suite. The previous wave used `'GROUPS-PASSED:.* T185 '`, which works.

**Fold:** `bash tests/run-tests.sh 2>&1 | grep 'GROUPS-PASSED:' > /tmp/gp; grep -q ' T184 ' /tmp/gp && grep -q ' T185 ' /tmp/gp && grep -q ' T186 ' /tmp/gp`. A single-regex alternative is `grep -qE 'GROUPS-PASSED:.* T184 (.* )?T185 (.* )?T186 '`, verified to match the adjacent case and reject a line without T186. Use a temp file under `mktemp`.

## F2 (CRITICAL): k4 cannot be satisfied as written, and it contradicts an existing pin (T21.1)

s1a k4: "plugin/templates/dag.json and every planning/*.dag.json lint at 0 errors AND 0 warnings on both runtimes". Lint over the real files gives:

- `plugin/templates/dag.json`: 1 warning, the skeleton warning, on both runtimes. This is by design and pinned by run-tests.sh:285 `T21.1 dag template → 'skeleton' warning`.
- 13 planning dags already carry heuristic warnings today, identical on both runtimes. Examples: agent-benchmark, cross-model-refuter, frameworks-*, gate-strengthening ("output/result.json" skeleton marker), howto-framework-dockers (2), mcp-2026, opencode-integration.
- 6 planning dags have a **string `_meta`**: detach, mcp-drive-loop, refuter-authoring, refuter-economics, refuter-profiles, regate. Today python lint crashes on them (`AttributeError: 'str' object has no attribute 'get'`). `_meta` is `"type": "object"` in the schema, so under the plan's own derivation rule ("every container (type object/array)") it is a STRUCTURE node and these 6 dags become lint ERRORS. If it is treated as VALUE instead, they become warnings. Either way k4 fails.

Consequences: SHAPE-LINT-OK can never print, so s1x is red. Otherwise the implementer has to weaken k4, or rewrite archived planning dags, which no task specifies. The `_meta` pre-check ("85 dag-shaped files … no existing dag gains a warning") looked only at undeclared keys and missed this. The same holds for S1 P2 ("a planning dag or the template gains a warning or error").

**Fold:** re-spec k4 as "no NEW findings". The oracle is the HEAD copy of both lints run in a scratch tree. For the template, every planning/*.dag.json and every fixture, the post-S1 error and warning sets must equal the HEAD sets, apart from an explicit named allowlist, and the base dag lints 0/0. Decide `_meta`'s tier in the schema itself. Recommended: `"_meta": {}` (any type), because it is documentation and 6 archived plans use a string. Then k1 does not derive a `_meta` mutation, and k6 still requires lint.py to stop crashing on a string `_meta`.

## F3 (CRITICAL): unnamed falsified pins in replan.sh case_drift d7 (T184.1) turn s1r red at S1

tests/replan.sh:323-341 builds dags whose **criterion ids** are `null` (d7a), `1` (d7c), `9007199254740992` (d7e) and `7` (d7f). For d7a, d7c and d7e it calls `assert_quiet`, which requires `node hb.js doctor` and `hb doctor` to exit 0 with no `✗` line naming GATE_X (replan.sh:124-133). Criterion `id` is a REQUIRED string property, so S1 k1 makes all of these lint ERRORS. Doctor embeds lint errors as problems:

```
$ (criteria [{"id":"c","cmd":7}]) node .hb/hb.js doctor  → "✗ dag: [G] criteria entry 0 …", rc=1   (python identical, rc=1)
```

After s1b, d7a, d7c and d7e fail with "node doctor exit 1 (want 0)". REPLAN-OK goes red, so s1r (and s2p) block. The `_meta` "falsified pins" list names only the degenerate-id block (l.160-178).

**Fold:** add d7a, d7c and d7e (and d7f's expectations) to the falsified-pins list and to s1c. Re-spec them so the dag side carries string ids, keeping the hostile values in the event-log pin, where the drift-classification contract actually lives. Alternatively, assert doctor exit 1 with the structure problem and keep the cross-runtime identity of the drift classification. S1 P4 should name d7.

## F4 (CRITICAL): the regate marker's tier contradicts the T179 exit-3 pins (pytest is in s2q)

s1b declares `regate` in the schema as "the marker object" (type object). By the derivation rule that makes it a STRUCTURE container, and r5 then requires gate eval to refuse with **exit 4**. Existing pins require **exit 3** for exactly these shapes:

- tests/regate-fail-closed.sh:175-180 loops `for junk in '[]' '{}' '"yes"'` and expects `gate.sh` and `hb gate` to exit 3 (T179).
- py/tests/test_regate.py:198-215, `test_regate_malformed_marker_fails_closed`, asserts `run_cli(["gate","GATE_A",...]) == 3` for `[]`, `{}` and `"yes"`.

s2q runs pytest, so S2 goes red. The other outcome is that the implementer silently exempts `regate` from the derivation, which S1 P3 forbids ("the mutation list is hand-coded"). The same tier ambiguity hits `review` (object) and `review.constraints` (array of objects with required id/claim/subjects/violation; F5).

**Fold:** put an explicit tier on every container in the schema (`"x-hb-structure": true|false`) and derive from that, not from `type`. Mark `regate`, `review`, `review.constraints` and `_meta` as **false**: they are owned by existing lint rules and runtime perimeters. Add a precedence rule: the regate perimeter (exit 3) is evaluated before the structure refusal (exit 4) on the gate being evaluated, or else re-spec and name the T179 pins.

## F5 (HIGH): the tier rule contradicts itself, and the "generator emits well-formed dags only" pre-check is false (parity-fuzz goes vacuous)

- The design's parenthetical lists the containers as top, phases, phase, tasks, task, requires, gates, gate value, criteria and criterion. s1a's walk uses "type object/array, a required property, or x-hb-structure", which also captures `_meta`, `review`, `review.constraints`, constraint items, constraint required fields, `subjects`, and the new `regate`/`rearm`/`prev_criteria`. The VALUE paragraph lists `cmd`, `review`, `regate` and `constraints` as fields "an existing rule already ERRORS on" with message bytes unchanged. The STRUCTURE paragraph lists `criterion id+cmd` as STRUCTURE, and k1 requires a path-named error line (`phases[1].tasks[0].id`) for every STRUCTURE mutation. The existing messages (`[G] criteria entry 0 must be …`, `[G] review.constraints must be a list …`, `[a1] requires a non-existent task: 5`) are not path-named. So either a second error line is added, which changes the fixture error sets and conflicts with k4/P2, or k1 fails.
- tests/gen-parity-case.py:72-85 deliberately emits malformed constraints: `[dict(ok, subjects=[]), None, "P3"]` and `{"id": "P1"}` ("not a list"). Of the 12 default seeds, **0, 1, 4, 5 and 6** carry them:
  ```
  $ for s in 0..11: gen-parity-case.py $s - | <check non-list / non-object constraint entries>
  0 malformed  1 malformed  4 malformed  5 malformed  6 malformed  (others clean)
  ```
  If constraints are STRUCTURE, S2 makes `rebuild`, `state`, `next`, `ready` and `report` refuse with a non-JSON line. parity-fuzz's `run_case` pipes both sides through JSON parsers, gets `""` on both sides, and compares `"" = ""`. That is vacuous agreement on 5 of 12 seeds. GATE_S2 does not run parity-fuzz at all.

**Fold:** use the F4 schema tier table. If any constraint node stays STRUCTURE, re-spec the generator and add a non-vacuity floor to parity-fuzz (every surface's output must parse on both runtimes). Add `bash tests/parity-fuzz.sh | grep -q '^FUZZ-PARITY-OK'` to GATE_S2.

## F6 (HIGH): an unparseable or missing dag.json slips past every new guard except the tick

`readDag()` (hb.js:72-75) and `state.read_dag` (state.py:35-39) swallow a parse error into `{phases: [], gates: {}}`, which is a structurally VALID empty plan. A structure check applied to that value passes. Demonstrated today with `dag.json = '{broken'`:

```
py doctor      → "✓ hb doctor: healthy"
py gate --all  → "✅ ALL GATES PASS (0 gate(s) in 0s)"
py state/ready/next → empty projection / [] / null;  node state/ready → empty / []
py tick        → dag_corrupted (only the tick notices)
```

The re-specified PROTOCOL says dag_corrupted means "unreadable or structurally malformed". The r-cases are only schema mutations, so the most common corruption (truncated or emptied JSON) goes untested and keeps passing.

**Fold:** the checked read parses the file itself. An unreadable or missing file becomes the first shape error, `dag.json unreadable: <msg>`. Doctor reports it as a problem. Add r-cases for truncated JSON, an empty file and a missing file across r1-r9.

## F7 (HIGH): VALUE tier includes control-flow fields, causing a silent all_done, runtime divergence, and a false honest limit

`parked` is a typed scalar, so it is VALUE (warning only, readers proceed). The runtimes read it by truthiness. Results from vprobe.sh (fresh project per reader):

```
P[0]["parked"]="no"  ntick:all_done  ptick:all_done      (lint today: ✓ DAG valid (0 warning(s)))
P[0]["parked"]=[]    ntick:all_done  ptick:next_task     ← node≢python
P[0]["parked"]={}    ntick:all_done  ptick:next_task     ← node≢python
```

A strict unattended run on `parked: "no"`:

```
HB_EXEC_STRICT=1 node .hb/hb-exec.js run  → "HB-EXEC DONE: all phases complete", rc=0, backend never ran
python exec run                           → "HB-EXEC DONE: project complete"
```

The `_meta` honest limit "strict exec refuses lint warnings, so unattended strict runs stop" is false. `strictBlock` lints only on `gate_pending` (hb-exec.js:169-180, 433-436), so a parked typo never reaches it, and s3a would document it as true. The parity contract (AGENTS rule 2) is broken on a dag that would still only warn.

**Fold:** annotate `parked` `"x-hb-structure": true`. Alternatively, make every reader use strict `=== true` / `is True`, as horizon.sh n3 already pins for `horizon`, and add a parity pin for `parked: []`. Correct the honest-limit text to say that strict exec checks lint warnings only at gate evaluation.

## F8 (HIGH): the python seam contradicts the exemptions; r9 contradicts "lint/audit exempt"

s2c makes "a single checked dag-read helper in state.py the preferred seam". `st.read_dag` is also the read path of the exempt and reporting surfaces: mcp_server.py:74 `_lint`, :75 `_audit`, cli.py:437/451 (lint and audit with no dagfile), and doctor.py:18/174. Checking inside `read_dag` breaks `hb lint` and the MCP `lint` tool on exactly the dags they exist to diagnose. It also breaks audit's tolerance and doctor's reporting. Separately, r9 says "the python MCP tools return an error result" for every tool, which includes `lint`, `audit`, `doctor` and `diagnose`.

**Fold:** add a new `read_dag_checked` (node: `readDagChecked`) that only interpreting paths use, and leave `read_dag` raw. Give r9 a per-tool expectation table: lint returns its errors, audit stays tolerant, doctor returns problems, diagnose names dag_corrupted, and all others return an error result.

## F9 (MEDIUM): node has no `hb lint`, so the refusal points at a verb that does not exist

r4 requires the read-verb refusal to name "`hb lint`", and the PROTOCOL re-spec says "hb lint names every shape error". hb.js has no `lint` case (dispatch default, hb.js:1770 usage list), so `node .hb/hb.js lint` prints the usage error. The node convention is `node .hb/hb-lint.js .hb/dag.json` (hb.js:529, hb-next-task.js:148).

**Fold:** node messages and the node PROTOCOL action name `node .hb/hb-lint.js .hb/dag.json`, python names `hb lint`, and r4 greps the runtime-specific string. The other option is to add a `lint` verb to hb.js.

## F10 (MEDIUM): S1/S2 gates skip the 15 sub-suites that only run-tests.sh reaches; failures surface in a docs phase

GATE_S1 runs replan, horizon, parity, fuzz and pytest. GATE_S2 runs dag-shape, parity, horizon, replan, single-source, hook and pytest. Neither runs regate-fail-closed.sh (F4), regate-rearm, review-holes, refute-fail-closed, constraints-grounded, detach, detach-surfacing, golden-unconstrained or gate-blocked-cause, which run-tests.sh invokes. GATE_S2 also omits parity-fuzz even though S2 rewrites the resolvers and state verbs (F5). The first full run is S3's s3y, whose tasks are docs-only and cannot fix code.

**Fold:** GATE_S2 adds a criterion that runs those sub-suites directly (each is fast) plus parity-fuzz. Alternatively, add a full run-tests criterion keyed on `GROUPS-PASSED` containing T179-T186 (using the F1-correct grep).

## F11 (MEDIUM): the selftest "right reason" admits a crash

s1a: the strips "redden k1 for the RIGHT reason (a structure mutation then lints clean **or crashes**)". A strip that leaves a syntax or NameError crashes, so it reddens for the wrong reason, which S1 P4 itself treats as a failure ("reddens for a parse error"). The spec and the constraint disagree.

**Fold:** define the right reason as: the stripped copy passes `node --check` / `python -m py_compile`, the base dag still lints exit 0 with it, and the targeted mutation lints exit 0 with no traceback. Apply the same rule to sr1, sr2, st1 and st2.

## F12 (MEDIUM): the silent-sleep swallow stays; TOCTOU is asked about but not designed

tick.sh:274-278: `NEXT=$(node "$NEXT_TASK_SCRIPT" … || echo "null")` → `no_pending_tasks`. The plan only adds an upstream check "so no later section ever sees a malformed dag". Any resolver crash the check does not anticipate still sleeps silently. That includes a dag rewritten between the dag-check slot and §6, a hostile state.json or events.jsonl, or a VALUE-field crash. The S2 review prompt (b) asks for exactly this TOCTOU, but no design element or case covers it, so the review will refute S2.

**Fold:** treat a nonzero or unparseable resolver output as a wake (`dag_corrupted`, or a new `resolver_error` key in both PROTOCOL tables), never a sleep. Read the dag once per tick and per gate.sh invocation (a snapshot passed to every section). Add an r-case that malforms the dag between check and resolve, using a `NEXT_TASK_SCRIPT` wrapper that rewrites dag.json and then execs the real resolver.

## F13 (MEDIUM): the entry-point lists are hand-written and incomplete

r3 (mutating) omits `import`, which appends task/gate events (hb.js:1752-1767), plus `anchor` and `heartbeat`/`beat`. r4 (read) omits `drift` (which gate.sh --all consumes), `refute-prompt`, `constraints --prompt/--json` and `refuters`. On the python side the lists omit `exec`, `bench`, `reward`, `deplint`, `mcp-serve` and `init`. S2 P2 claims "every other plan-interpreting entry point".

**Fold:** derive the verb set from `hb.js` `case '…'` and `cli.py` `add_parser(...)`. The test then asserts that every verb is classified as mutating, read or exempt, so a new verb cannot slip past.

## F14 (MEDIUM): a tolerant audit means "audit-clean + refuted SOUND" still admits dead-on-arrival plans

AGENTS rule 3 and the pre-commit table name `hb-audit` as the DAG check. Today audit reports **0 errors** on `T[0].id=5`, `P[0].id=5`, a missing phase id, `tasks=[5]`, criterion `id=null` and `review=[]`. After S2 each of these is a dag that wakes dag_corrupted on every tick. The design keeps audit tolerant but never requires it to *say* so.

**Fold:** audit adds an `error` finding `dag_shape`, built from the lint structure layer, and still never crashes. Pin it with byte-identical parity (it fits the r8 case).

## F15 (MEDIUM): runtime budget

s2x and s2y each get 900s. T186 runs both inside run-tests.sh (about 13-15 min today, per the horizon `_meta`), under s3y's 1800s timeout. The plan's own budgets add up to more than 1800s. At about 0.12s per bootstrap, 0.06s per python CLI call and 0.26s per tick, roughly 50 schema-derived mutations × about 30 invocations × 2 runtimes, plus exec drivers, plus 4 strip reruns, is plausibly close to the 900s caps.

**Fold:** add a measured budget criterion (for example `DAG-SHAPE-OK` within 300s, measured), let T186 run a seeded subset of mutations (full set in the gate), and raise s3y's timeout to 3000s.

## F16 (LOW): s2s proves nothing about S2; the "immutable" text is not gated; the hook omits dag_corrupted

single-source.sh compares PROTOCOL **keys** only, and the keys are unchanged by design. hook-drives-loop.sh tests a file S2 does not touch. So s2s passes whether or not the dag_corrupted text was re-specified. The SessionStart hook's stop list (plugin/hooks/heartbeat-detect.sh) omits `dag_corrupted` and `state_corrupted`, and S2 makes dag_corrupted common.

**Fold:** add a criterion `! grep -q 'immutable' plugin/templates/hb.js py/src/heartbeat/protocol.py plugin/templates/tick.sh && node -e "…PROTOCOL.dag_corrupted.includes('hb-lint')"`, plus the python twin. Add dag_corrupted to the hook's human-needed list.

## F17 (LOW): the state check runs before the dag check, so the self-heal calls a rebuild that now refuses

tick.sh §2 (l.151-159) self-heals a corrupt state.json through `hb.js rebuild`, and S2 makes rebuild refuse on a structure-invalid dag. If state.json is corrupt and dag.json is malformed, the tick wakes `state_corrupted`, whose action (rebuild) refuses. tick.py `_body` has the same order. This is untested.

**Fold:** run the structure check before the state self-heal, or specify the combined case and add it as an r-case.

## F18 (LOW): smaller gaps

- s3x (docs-currency.sh) checks only the v1.29 sweep tokens. It asserts nothing this wave writes, and no S3 criterion checks that the how-to's cited case names (k1-k6, r0-r9) exist in tests/dag-shape.sh. **Fold:** add a check that greps each cited case id from the how-to and finds it in dag-shape.sh, in the gated-docs style.
- s1b's regate field list (at/reason/actor/prev_criteria/pending) omits `rearm{at,actor,model,artifact,sha256}`, which hb.js rearm writes. `model` can be `null`. k5 will catch this only if rearm runs with and without `--model`. **Fold:** list rearm and `model: ["string","null"]`.
- k5 names "horizon close" as a dag writer, but it only appends an event (hb.js:1689-1717). It omits reattach and unpark, which do write dag.json.
- The "empty id" STRUCTURE rule cannot be derived, because the schema has no `minLength` on id. **Fold:** add `"minLength": 1` to phase and task ids.
- docs/dev-plugin.md:43 says "(immutable at runtime; restore from git if corrupt)". s3c does not name it, and a grep for 'structure is immutable' would miss it.
- `_meta` says the lints disagree on 9 shapes, but the probe shows 8.

---

## Verdict reasoning

F1 makes S3 unpassable on a correct implementation. F2, F3 and F4 make S1/S2 unpassable unless the implementer weakens a test, which the plan's own constraints prohibit. F5 through F8 are spec holes where the gate would pass with the work broken: vacuous fuzz parity, unreadable dags slipping through, a control-flow typo ending the project, and the lint MCP tool failing closed on the dags it should diagnose.

VERDICT: UNSOUND
