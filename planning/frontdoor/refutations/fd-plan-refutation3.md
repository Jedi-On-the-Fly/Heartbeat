# Refutation round 3: planning/frontdoor.dag.json (S1/S2/S3)

Scope: read-only. All probes ran in `mktemp -d` dirs, plus one throwaway `git clone` (deleted afterwards). Nothing ran against the repo's own `.hb/`. `git status` afterwards shows only the two pre-existing untracked paths.

Probe material is in `scratchpad/r3x/`:
- `hook.js`: a NODE_OPTIONS `--require` census hook. It wraps `fs.readFileSync` and logs every dag read that breaks the new STRUCTURE contract or is unreadable: missing phases or gates, wrong-typed containers or items, bad ids, gate refs, parked, and non-object criteria entries.
- `_r3log.py`: the python twin. It was patched into the clone's `state.read_dag`, `lint.lint`, cli lint/audit dagfile reads, and `tick.py`.
- `census-node.jsonl` / `census-py.jsonl`: the census output. `summ.py` summarizes it.
- `suite.log`, `pytest.log`, `parity.log`, `fuzz.log`: all green under the census. Node `RESULT: 476 passed, 0 failed`, GROUPS-RAN 185, GROUPS-SKIPPED 0. Pytest 187 passed. `PARITY OK`. `FUZZ-PARITY-OK:12`.

---

## Part 1: convergence of round-2 findings

| # | Round-2 finding | Landing text (quoted) | Coherent? |
|---|---|---|---|
| N1 | T186 wired in S2 without the dev-tests row → T124.1 red | s2c: "Wire tests/dag-shape.sh into tests/run-tests.sh as group T186 … and in the SAME task add the T186 row to docs/dev-tests.md (T124.1's index-coverage.sh reddens the full suite on a wired group without a row; s3c re-specifies it string-accurately)". `_meta` falsified-pins: "docs/dev-tests.md gains its T186 row IN S2 (s2c)". | **Yes.** index-coverage.sh:13-15 needs only `\| T186 `. s3a writes the how-to and its howto-list row in the same task, so the guide half of index-coverage also holds. |
| N2 | k6 resolver agreement at S1 | k6: "parked 'no' / 1 / [] / {} is a lint error on both runtimes (the readers' agreement is S2's r2)". r2: "including on every parked 'no' / 1 / [] / {} mutation (the runtimes agree)". | **Yes** |
| N3 | non-object criteria entries | design: "a gate's criteria (array) and each criteria ENTRY (object … round-2 N3; its existing '[G] criteria entry N must be …' line is reused as the one line". s1b keeps "parity.sh hostile-criteria:lint keeps its bytes; doctor's 'dag: ' problem prefix stays". GATE_S1 P1: "every criteria entry". | **Yes.** Probed: today `[null]`/`["s"]`/`[5]`/`[[]]`/`[true]` each give exactly one identical line on both lints. See R3-4 for an audit-wording side effect and R3-3 for a byte split on lone surrogates. |
| N4 | `{}` / missing phases-gates sleep | design: "the root's REQUIRED phases and gates … phases: [] stays valid". k2 adds "{} / a dag missing phases or gates … the path-named 'phases: missing'". | **Partly.** The census shows no test lints, ticks or gates a gates-less or phases-less dag. The only such dags are plugin/adapters/*/fixtures, which are read only by deplint and coverage, never by lint or readers. The honest limit for a kept-valid empty plan, which the round-2 fold asked for, **did not land** (R3-5). |
| N5 | unreadable bytes | design: "FIXED bytes, never native parser text … 'dag.json unreadable: missing', '… empty', '… not valid JSON', '… top level is not an object'; python parses strictly (NaN/Infinity rejected via parse_constant; a BOM or invalid UTF-8 is 'not valid JSON' on both)". k2 lists NaN, Infinity, BOM and invalid UTF-8. | **Yes for the named classes.** Grep finds no test that pins lint's or audit's current `unreadable: ${e.message}` text. T12.5 only greps `dag_corrupted`. The rule misses one class (lone surrogates, R3-3), and in python it is only reached through a file argument (R3-1). |
| N6 | audit byte-identity scope | design: "Byte-identity is scoped to the dag_shape finding itself (its text line and JSON object) … on a dag_shape plan both summaries name the structure failure, never 'hollow gates'". k5 has the same wording. | **Yes.** k5's "exactly one error finding" wording is ambiguous (R3-4). |
| N7 | doctor short-circuit | design and s2b: "Doctor on a structure-invalid dag reports ONLY the structure errors plus one line 'plan checks skipped: dag.json invalid' and skips every plan-derived check (drift, rot, projection, regate, detach)". r6: "no drift, rot, projection, regate or detach line and no 'hb rebuild' note". | **Yes.** Doctor tests on hostile-criteria dags (test_hardening.py:150-154, parity hostile-criteria:doctor) need only the `dag: …criteria entry` problem, equal exits and no crash, and that still holds. Dags with non-STRUCTURE lint errors keep the full doctor. |
| N8 | exit 4 precedence | design: "the structure check is the first statement after argument parsing in every mode, so exit 4 precedes exit 2 (unknown gate) and exit 3 (regate pending)". r5: "a regate-pending gate inside a broken dag exits 4". | **Yes.** Nothing pins gate.sh's no-arg exit 2 or the "Available gates" text (grep over tests, py/tests and gate-examples). T179's exit-3 shapes are all structure-valid. |
| N9 | message-rule ambiguity | design: "the existing SHAPE message about that very node where one exists (today only '[G] criteria entry N …') … every other rule SKIPS a malformed container (requires:'a1' no longer iterates …)". | **Mostly.** "Today only" is wrong (hb-lint.js:184 and :49), and the skip rule does not reach wrong-typed items (R3-6). |
| N10 | array items not derived | s1a: "for every annotated array wrong-typed ITEMS derived from its items.type (null, a number, a string, a list, an object …)". | **Yes** |
| N11 | out-of-STRUCTURE lint errors | honest limit: "lint-ERROR shapes outside STRUCTURE (review, review.profile, review.constraints and subjects, regate, the criterion entry's fields) keep today's runtime path …". GATE_S2 prompt (a): "lint-error shapes outside it are a recorded honest limit". | **Yes** |
| N12 | derivation mechanics | s2a: "hb.js's switch after `if (require.main === module)` (never the projector's event-type case labels) and python's parser choices (incl. the start/done/fail/heartbeat loop …) … 'exempt — does not read the project dag' for code_context, code_discover and deplint". | **Yes.** The r8 tool classes contradict r1/r2 for `tick` and `next` (R3-2). |
| N13 | missing resolver sleeps | design: "A MISSING resolver script … wakes the same deadlock resolver_error". s2b: "or a missing resolver script, becomes the deadlock wake with cause resolver_error". r10: "AND removed entirely". | **Yes.** Nothing pins `no_next_task_script`. |
| N14 | counts and dag predicate | k3: "every planning/**/*.json file that is a dag (a JSON object with a phases or gates key) … the nine string-_meta planning files". evidence: "the lints DISAGREE on exit status for 8 shapes". | **Yes** |

---

## Part 2: questions the brief asked, answered by probe

- **broken.json (`"G0": {}`, `"G1": {}`).** The schema marks gate `criteria` as required. But the plan makes only the ROOT's required keys STRUCTURE ("the root's REQUIRED phases and gates"), and derives missing-key mutations only "for a required id". A gate missing `criteria` therefore stays outside the contract, and k3's byte-equality on broken.json holds. The phase's required `tasks` stays outside too: a missing `tasks` lints 0/0 and crashes no reader (round-2 probe-missing.out). The plan is consistent, but nowhere says so outright. An implementer who reads "annotated node + parent `required`" as STRUCTURE would change broken.json's output and redden k3. It would help to say it in one line (folded into R3-6).
- **Gates-less dags.** All ten are plugin/adapters/{code,docs}/fixtures. They are outside k3's scope (template, planning, tests/fixtures), and the census shows they are read only by deplint.js, deplint-accept.js and codegraph-coverage.js. None of those calls lint (grep). No test-generated dag lacks phases or gates.
- **Empty-criteria gates.** `criteria: []` is a valid array. horizon.sh:433 and test_lint use them, and they keep today's path.
- **Census hits on the new STRUCTURE set** (the complete list, both runtimes):
  - parity.sh hostile-criteria: inline, compares runtime vs runtime, still green when mirrored.
  - test_hardening.py hostile criteria: lint, doctor and audit. See R3-4.
  - replan.sh's id-less phase: the T184 re-spec the plan names.
  - horizon.sh t7: `crit-str`, `crit-obj`, `gate-str`, `gate-arr`, `exit-num`/`zero`/`true`/`list`/`obj`, `gates-arr`. These are STRUCTURE shapes, although the pre-checks say t7's nodes "are not annotated STRUCTURE". t7 asserts only no crash, equal exits and equal full finding objects across runtimes, so it stays green if dag_shape is mirrored including every field.
  - T12.5's `{broken` tick.
  - Nothing else in 476 node checks, pytest, parity or fuzz. The fuzz generator emits no STRUCTURE-invalid dag.
- **Fixed unreadable bytes vs pins.** None conflict (above).
- **Exit 4 before exit 2.** Nothing pins it.
- **Doctor skip.** It is conditioned on the structure check, so a dag with only semantic errors (broken.json, lint-*.json) still gets the full doctor.

---

## Part 3: new findings, ranked

### R3-1 (MEDIUM-HIGH): python `hb lint` / `hb audit` with no file argument report a missing or truncated dag as VALID. That is the very command the python refusal tells the user to run, and the design sentence "the raw read_dag stays for lint, audit …" keeps it that way.

```
.hb/dag.json = '{"phases":['   →  hb lint --dir P   → "✓ DAG valid (0 warning(s))"  rc=0
                                   hb audit --dir P  → "✓ gates look behavioural (0 warning(s))" rc=0
.hb/dag.json removed           →  hb lint --dir P   → "✓ DAG valid (0 warning(s))"  rc=0
```

cli.py:437 and :451 do `json.loads(Path(args.dagfile)…) if args.dagfile else st.read_dag(hb)`, and state.py:35-38 turns any read failure into `{"phases": [], "gates": {}}`. The MCP `lint`/`audit` tools (mcp_server.py `_lint`/`_audit`) use the same raw read.

After S2, the python tick wakes dag_corrupted saying "run hb lint for every error" (r4, protocol.py), and `hb lint` then answers "DAG valid". This is a recovery trap, and no case catches it:
- k2 and k5 drive lint and audit with a file path.
- r8 covers the MCP lint tool, but no case runs the python CLI `hb lint` / `hb audit` with no argument on the unreadable representative.

Every gate can pass with this broken.

**Fold:**
- design: "lint and audit read through the structure layer's checked file read (never read_dag's fallback), with or without a file argument. The raw read_dag stays only for doctor/diagnose's tolerance, and their structure test also reads the file."
- k2 and k5 additionally run `hb lint --dir P` and `hb audit --dir P` (no file argument) on every unreadable class: exit 1, the fixed bytes, no "DAG valid".
- r8 asserts the MCP lint tool on the unreadable representative returns `dag.json unreadable: …`.

### R3-2 (MEDIUM): r8's MCP classes contradict r1/r2 and s2c for `tick` and `next`

r8: "lint returns the errors, audit returns findings incl. dag_shape, doctor/diagnose report, **every other tool returns an error result**". `tick` and `next` are "other" tools. mcp_server.py's `_tick` returns `tickmod.tick(hb)`, which r1 makes the dag_corrupted WAKE, a normal result. `_next` returns `rv.resolve(...)`, which r2 makes `{type: deadlock, cause: dag_invalid}`, also a normal result.

s2c adds dag_corrupted to "mcp_server's tick description … human-needed list", and s3b adds it to drive-heartbeat-over-mcp.md's stop list. Both only make sense if the MCP tick returns the wake. To satisfy r8 as written, the implementer must special-case those two tools into `isError`. That would make the new stop-list docs false for MCP clients, because an MCP-driven agent would see an error instead of the dag_corrupted reason. Otherwise r8 stays red. GATE_S2 review (e) asks for "no third route".

**Fold:** in r8, `tick` returns the dag_corrupted wake (as r1) and `next` returns deadlock dag_invalid (as r2). `ready`, `state`, `report`, `gate`, `start`, `done`, `fail` and `review` return an error result. The three exempt tools are as stated. Match s2a's MCP class table and GATE_S2 P2 to this.

### R3-3 (MEDIUM): lone surrogates break "byte-identical, never a traceback for any file content" on a STRUCTURE node

A `\ud800` escape is valid JSON to both parsers, but:

```
criteria: ["\ud800"]   (a STRUCTURE criteria-entry violation)
  node --json: "[G] criteria entry 0 must be an object with a string cmd (got \"\\ud800\")"   ← escape TEXT (JSON.stringify)
  py   --json: "[G] criteria entry 0 must be an object with a string cmd (got \"\ud800\")"    ← a raw surrogate CHAR
  py   text  : UnicodeEncodeError: 'utf-8' codec can't encode character '\ud800' … surrogates not allowed (traceback)
gate_exit "\ud800" (structure-valid) → node "[A] undefined gate: �";  py text: same UnicodeEncodeError traceback
```

So the reused "existing message" is not byte-identical across runtimes for this STRUCTURE violation, and python lint tracebacks. GATE_S1 P1 claims "byte-identical … never a traceback for any file content", and review (b) fuzzes "unicode keys", so the S1 review will find this. The plan leaves the cure unspecified. Today no repo dag carries a surrogate escape; the only file with one is tests/fixtures/review-holes/refuse.json, which is not a dag.

**Fold:** add an unreadable class. An unpaired surrogate escape in any string or key is `dag.json unreadable: not valid JSON` on both runtimes: node scans after parse, python checks after parse. This matches the invalid-UTF-8 rule and RFC 8259's "unpredictable" clause. Add it to k2.

### R3-4 (LOW-MEDIUM): k5's "exactly one error finding with rule dag_shape" can be read so that it reddens test_hardening.py:160 (s1q)

test_hardening.py:158-160 asserts that `audit.audit()` on all-garbage criteria (`[None]`, `["garbage"]`, `[["garbage"]]`), which are now STRUCTURE, still emits `hollow_gate`. parity.sh:254 asserts that `hollow_gate` does NOT fire when one real criterion remains. Both tests assume audit "stays tolerant (analyzes what it can)", as the design says.

k5 and GATE_S1 P4 ("exactly one dag_shape error finding") can also be read as "exactly one ERROR finding". Under that reading, a dag_shape short-circuit would pass k5 and fail s1q.

**Fold:** k5 reads "exactly one finding with rule dag_shape; the other rules still run tolerantly (test_hardening.py:160's hollow_gate on all-garbage criteria stays; parity hostile-criteria:audit's no-hollow floor stays)". k5 also checks that the summary avoids "hollow gates" even when hollow_gate co-fires. horizon.sh t7 compares FULL finding objects with sort_keys across runtimes, so the dag_shape object's every field (severity, phase, extras) must be mirrored. State that in s1b.

### R3-5 (LOW-MEDIUM): the N4 honest limit did not land. `{"phases":[],"gates":{}}` still sleeps silently forever on both runtimes.

```
dag.json = {"phases":[],"gates":{}}  → lint ✓ (both)   node tick {"wakeAgent":false,"data":{"reason":"no_pending_tasks"}}   py tick same
```

This is byte-for-byte the shape that read_dag's fallback fabricates, and the shape an editor can leave behind by deleting the array contents. The plan keeps `phases: []` valid for a good reason (gate-timeout-portable.sh:37). The round-2 fold asked for "an honest limit for an empty `phases: []` plan if it is kept valid", and the honest-limits list has no such line.

**Fold:** add the honest limit "a dag with an empty phases array is valid and the tick sleeps no_pending_tasks; only absent or wrong-typed containers fail closed". Alternatively, have the tick wake on a live plan with zero phases. Then name the limit in the s3a how-to.

### R3-6 (LOW): the skip rule stops at containers. Wrong-typed ITEMS still feed other rules, which emit extra and divergent lines.

```
requires: [1.0]  → node "[b] requires a non-existent task: 1"   py "[b] requires a non-existent task: 1.0"
```

k1 derives requires-item mutations (N10), demands "EXACTLY ONE structure-attributable line", and compares byte-identical error lists. With the derived integer `5`, both runtimes print "…: 5", so k1 passes. The extra line is still there, and review (b)'s "floats as ids" finds the split.

Related inaccuracy: the design says the criteria-entry line is "today only" an existing shape message, but two more exist:
- hb-lint.js:184, `[${p.id}] a detached phase id must be usable as an anchor file name`, about the phase id node, which is STRUCTURE. A detached phase with an empty or numeric id would emit both lines.
- hb-lint.js:49, the horizon rule rendered with `pidS`.

**Fold:** "every other rule skips a malformed container AND every wrong-typed item of an annotated array, and skips a phase or task whose id is STRUCTURE-invalid in the id-keyed rules (detach-id), keeping the '[?]' rendering where T184 pins it". Correct "today only". Add one line: "a gate missing criteria and a phase missing tasks are outside STRUCTURE (broken.json's G0/G1 stay byte-equal under k3)". Correct the pre-check that calls horizon t7's nodes non-STRUCTURE: t7 now exercises dag_shape.

---

## Part 4: checks that hold

- Every round-2 fold is quoted in Part 1 and landed coherently. The exceptions are R3-5 (missing limit) and the R3-2 and R3-6 wording.
- **Census.** Across 476 node checks, pytest (187), parity and fuzz, the only reads that break the new STRUCTURE set are the deliberate ones listed in Part 2. No test lints, ticks, gates or doctors a gates-less, phases-less or unreadable dag expecting success. T12.5 keys only on `dag_corrupted`.
- **S1 suite.** S1 changes only lint and audit. The node resolver calls `lint()` for its deadlock diagnosis (hb-next-task.js:143, resolver.py:128), so structure errors in S1 route to deadlock dag_invalid when nothing is eligible. No test observes that on a STRUCTURE-invalid dag.
- **s2t.** `immutable` appears only at hb.js:55, protocol.py:15 and tick.sh:162, which are exactly the re-specified rows.
- **planning/frontdoor.dag.json.** It passes the census checker (0 STRUCTURE breaks), node lint (0 warnings) and audit (clean). Its S3 is `horizon: true`.
- **Budget.** Suite baseline 873 s. With T186 default (≤600 s) plus selftest (≤900 s) the suite stays inside the 3000 s criteria. run-tests.sh has no per-check timeout.

## Verdict reasoning

No gate is unpassable on a correct implementation. Two holes remain:
- R3-2: r8 as written forces MCP `tick`/`next` to return errors. That contradicts r1/r2 and the s2c/s3b stop-list docs, so either s2x reddens or the docs become false.
- R3-1: every gate passes while the python cure command, `hb lint` with no argument, still certifies a truncated or missing dag as valid. That is a passable-with-work-broken hole in the wave's headline guarantee, on the exact recovery path the new protocol text names.

R3-3 is a STRUCTURE-scoped byte split and traceback that the S1 review will surface, with no specified cure. R3-4 to R3-6 are small wording folds.

VERDICT: UNSOUND
