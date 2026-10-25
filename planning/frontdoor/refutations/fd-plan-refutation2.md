# Refutation round 2: planning/frontdoor.dag.json (S1/S2/S3)

Scope: read-only. Every probe ran in `mktemp -d` dirs. The full node suite ran in a throwaway `git clone` that was deleted afterwards. Nothing ran against the repo's own `.hb/`. `git status` afterwards shows only the two pre-existing untracked paths.

Probe scripts and outputs are in `scratchpad/r2/`:
- `probe2.sh`: 47 shapes outside (and at the edges of) the claimed STRUCTURE set, run through 30 readers on 2 runtimes. Output in `probe2.out`.
- `shapes-missing.txt`: absent and null containers. Output in `probe-missing.out`.
- `structchk.py`: the claimed STRUCTURE set, checked over every repo dag.
- `suite.log`: a baseline full node suite run.

Baseline measurements:
- Full node suite: `RESULT: 476 passed, 0 failed`, 873 s, GROUPS-SKIPPED 0.
- Round-1 sub-suite timings still hold.

---

## Part 1: convergence of round-1 findings

| # | Round-1 finding | Fold landed? | Coherent across tasks / criteria / constraints / `_meta`? |
|---|---|---|---|
| F1 | adjacent-group grep | **Yes.** s3y loops `for g in T184 T185 T186; do echo "$gp" \| grep -q " $g "`. It matches the real line `GROUPS-PASSED: … T184 T185 ` (run-tests.sh:2014, trailing space) once T186 is appended. | Yes |
| F2 | k4 0/0 unsatisfiable | **Yes.** k3 replaces it with a no-new-findings oracle, and `_meta` becomes any type. I verified the oracle works: `git show a500587:plugin/templates/hb-lint.js` requires only `fs`, and `git archive a500587 py/src` extracts and runs. Over 90 dag files (template, planning/\*\*, tests/fixtures, plugin/templates/fixtures), pre-wave node and current node outputs are byte-equal. The only node/python differences are the string-`_meta` crash. | Mostly. "the six string-_meta plans" is **nine** files in k3's scope: the six named, plus planning/refuter-{authoring,economics,profiles}/.hb/dag.json (N14). |
| F3 | d7 hostile criterion ids | **Yes.** Criterion ids are outside STRUCTURE, so the d7 dags stay structurally valid and `assert_quiet` holds. | Yes |
| F4 | regate tier vs T179 exit 3 | **Yes.** regate is not annotated. | Partly. The precedence of exit 4 against exit 3 and exit 2 on one gate is never specified (N8). |
| F5 | tier self-contradiction, fuzz | **Mostly.** Constraints are outside STRUCTURE, and parity-fuzz is in GATE_S1 and GATE_S2. | **No** for criteria entries. `_meta.design` says "criterion entries … stay owned by existing rules", but s1a's derivation rule ("for arrays of objects a null / string / number entry") applied to the annotated `criteria` array generates exactly those entries, and r1 demands they wake dag_corrupted (N3). |
| F6 | unreadable reads as empty valid plan | **Yes** for an empty, truncated or missing file and non-object tops (k2, r-cases on k2). | **No** for a readable empty object: `{}` lints clean and both ticks sleep `no_pending_tasks` forever (N4). The byte-identity of unreadable messages is unspecified, and NaN/BOM handling diverges (N5). |
| F7 | parked is control flow | **Yes.** parked is annotated, and the honest limit is corrected to strictBlock only at gate evaluation. | **No** at S1. k6 requires the two resolvers to agree, which they do not until S2 (N2). |
| F8 | python seam vs exempt tools | **Yes.** `read_dag_checked` is separate from the raw read, and MCP is handled per class. | Minor issue: the MCP class "every other tool returns an error result" sweeps in code_context, code_discover and deplint, none of which read the project dag (N12). |
| F9 | node has no `hb lint` | **Yes.** Node names `node .hb/hb-lint.js .hb/dag.json`, and s2t checks `hb-lint.js` and `hb lint`. | Yes |
| F10 | S1/S2 skip run-tests-only sub-suites | **Yes.** s1f, s2f and s3y run the full suite keyed on `^  RESULT: [0-9]+ passed, 0 failed$`, which matches the real line. | **Introduces N1.** The full suite at S2 is red by construction (T124.1). |
| F11 | selftest admits a crash | **Yes.** Strips must compile, keep the base clean, and turn the targeted mutation exit 0 with no traceback. | Yes |
| F12 | swallow + TOCTOU | **Yes.** resolver_error deadlock, r10, and an honest limit. | Minor issue: tick.sh:270-272 `no_next_task_script` is still a silent sleep (N13). |
| F13 | hand-written verb lists | **Yes, derived.** | Mechanics: hb.js `case '…'` also matches 10 event-type labels (hb.js:122-156), and cli.py's start/done/fail/heartbeat come from a loop (cli.py:70), not `add_parser("…")` (N12). |
| F14 | tolerant audit passes DOA plans | **Yes.** dag_shape plus the audit-rules-check fixture. The rule-set derivation (`F('sev','rule'` grep, audit-rules-check.sh:39) picks dag_shape up only if it is emitted via `F(...)`. | k5's "byte-identical (text and --json)" covers the whole audit output, which is not byte-identical today (N6). |
| F15 | runtime budget | **Yes.** s3y 3000 s; s2x 600 s with derived sets. | My estimate from the real schema (below) fits. |
| F16 | s2s vacuous; hook omits keys | **Yes.** s2t is real: it is RED today (both one-liners exit 1, verified) and works from PROJECT_DIR (`require('./plugin/templates/hb.js')` resolves against cwd; the CLI is guarded by `require.main`). The hook gains both keys. | Yes |
| F17 | self-heal before dag check | **Yes.** The structure check runs first, and r9 covers it. | Yes |
| F18 | small gaps | s3a anchor check, rearm/model fields, k4 writer list (unpark/reattach in, horizon close out), minLength, and dev-plugin:43 are folded. | "lints DISAGREE on exit status for 9 shapes": probe.out shows **8** (`lint(n=0,p=1)` rows). Not folded (N14). |

---

## Part 2: new findings, ranked

### N1 (CRITICAL): GATE_S2's full-suite criterion is red by construction. T124.1 requires a dev-tests.md row that only S3 writes.

s2c wires `grp "T186 …"` into run-tests.sh. index-coverage.sh:13-15 runs as **T124.1** (run-tests.sh:1484) in the full suite:

```
for t in $(grep -oE 'grp "T[0-9]+' tests/run-tests.sh | grep -oE 'T[0-9]+' | sort -u); do
  grep -qE "\| ${t} " docs/dev-tests.md || { echo "  suite group ${t} missing from dev-tests.md table"; missing=1; }
```

The T186 row in docs/dev-tests.md is written only by **s3c** (S3). So in S2, s2f (`RESULT: N passed, 0 failed`) always shows at least one failure. GATE_S2 blocks, and S3 cannot start until GATE_S2 passes. This is a deadlock. (Wave 4 shipped the same split, with T185 wired in H1 and its row added in H2. The suite stayed silent only because GATE_H1 had no full-suite criterion. `git show --stat 065f129` touches run-tests.sh and not dev-tests.md.)

**Fold:** s2c adds a T186 row to docs/dev-tests.md in the same task that wires the group (s3c then re-specifies it string-accurately), and names T124.1. As an alternative, move the wiring and the row together into S3, and key S2 on dag-shape.sh alone. Either way, add T124.1 to S2's pin list.

### N2 (HIGH): k6 requires the resolvers to agree in S1, but they disagree today and only S2 changes them

k6 sits in case `lint` (its success prints SHAPE-LINT-OK, which is s1x): "parked 'no' / [] / {} is a lint error on both **and the two runtimes' resolvers agree on it** (S2 makes both fail closed)". No S1 task touches a resolver. Measured with a fresh bootstrap per value:

```
parked="no" node=all_done py=all_done
parked=[]   node=all_done py=None      ← disagree
parked={}   node=all_done py=None      ← disagree
```

So s1x cannot pass at S1, unless the implementer weakens k6 or pulls S2 work forward.

**Fold:** in S1, k6 asserts lint only. Move "resolvers agree" into r2, which S2 makes true for every parked mutation.

### N3 (HIGH): non-object criteria entries crash gate evaluation on both runtimes, and the tick re-dispatches gate_pending forever; the design and the derivation disagree on whether they are STRUCTURE

The design excludes "criterion entries" from STRUCTURE. But s1a's derivation, applied to the annotated `criteria` array (an array of objects), generates `[null]`, `["s"]` and `[5]`, and S2 runs "the core readers on EVERY k1/k2 mutation", so r1 demands dag_corrupted on them. The plan contradicts itself.

The runtime behaviour is the very class this wave claims to close ("DISPATCH ON A BROKEN PLAN"). Both lints reject `criteria:[null]` today (lint n=1, p=1), yet:

```
node tick   → {"reason":"gate_pending",…}
gate.sh G   → TypeError: Cannot read properties of null (reading 'id')   (no event)
node tick   → gate_pending again                                         (forever)
HB_EXEC_MAX_ITERS=6 node .hb/hb-exec.js run → 3× gate crash … "HB-EXEC: max iterations reached" rc=0
   (the default maxIters is Infinity: hb-exec.js:378, an unbounded spin)
hb exec run → AttributeError: 'NoneType' object has no attribute 'get'   (gate.py:113)
hb gate G --check → traceback;  gate.sh --check G → TypeError   (probe2: ngchk pgchk on [None], pgchk on ["x"])
```

**Fold:** annotate `criteria.items` (the entry must be an object) `x-hb-structure: true`. Leave the entry's fields (id/cmd/desc/timeout_s) out, which keeps d7 and the `cmd:7` / `cmd:null` hostile-criteria shapes unchanged. Reuse the existing `[G] criteria entry N must be an object with a string cmd …` line as the one line, with no added path line, so parity.sh:240-257 `hostile-criteria:lint` keeps its bytes. Keep doctor's `dag: ` problem prefix, because py/tests/test_hardening.py:153 asserts `p.startswith("dag: ") and "criteria entry" in p`. Update `_meta.design` and the S1 P2 claim accordingly.

### N4 (HIGH): a readable empty object `{}` (or a dag that lost `phases`/`gates`) lints clean and sleeps silently forever

F6 is folded only for unparseable, empty and non-object input. The derivation generates "missing" mutations only for required **ids**, so absent required containers are never errors:

```
dag.json = {}                    → node lint ✓ DAG valid, py lint ✓ DAG valid, audit ✓
                                   node tick {"wakeAgent":false,"data":{"reason":"no_pending_tasks"}}
                                   py tick   same
dag.json = {"project":"p"}       → identical
del d["phases"] / del P[0]["tasks"] / del G["criteria"] → all lint 0/0 (probe-missing.out)
```

This is the same "empty valid plan" failure as F6, reached by truncating to `{}` or by an editor dropping a key. The wave's own "no silent sleep" principle is broken here.

**Fold:** the schema's root `required: ["gates","phases"]` is STRUCTURE, so absence is an error with the path-named line `phases: missing`. This is safe: structchk.py finds no planning, template or tests/fixtures dag lacking either key, and the AST scan of py/tests finds only deplint-adapter dags, which never go through readers. Keep `phases: []` valid, because docs/howto/gate-examples/gate-timeout-portable.sh:37 evaluates a gate on `{"phases": [], …}`. Either do not make a gate's missing `criteria` STRUCTURE, or allowlist tests/fixtures/parity/broken.json (`"G0": {}`), whose k3 output would otherwise change. Add `{}` and the missing-key mutations to k2/k1, plus an honest limit for an empty `phases: []` plan if it is kept valid.

### N5 (MEDIUM): "unreadable" cannot be byte-identical as specified, and NaN/BOM split the runtimes on readability

- Node already prints `✗ dag.json unreadable: ${e.message}` (hb-lint.js:303-304), which is V8's text (`Unexpected token 'N', …"imeout_s":NaN}]}}}" is not valid JSON`). Python's JSONDecodeError text differs, so k2's byte-identity forces a fixed message, and no task says so.
- Python `json.loads` accepts `NaN`, `Infinity` and `-Infinity`, and node rejects them:
  ```
  {"…","timeout_s":NaN} → node: dag.json unreadable …   py: ✓ DAG valid (0 warning(s))
  UTF-8 BOM + {…}       → node: dag.json unreadable …   py: JSONDecodeError traceback
  ```
  GATE_S1's review prompt (b) explicitly fuzzes BOMs, so this will be refuted.

**Fold:** define the unreadable classes and their exact bytes (for example `dag.json unreadable: missing` / `empty` / `not valid JSON` / `top level is not an object`), with no native error text. Python parses strictly (`parse_constant` raises; a BOM or invalid UTF-8 counts as unreadable). k2 adds NaN, Infinity, BOM and invalid UTF-8.

### N6 (MEDIUM): k5 demands whole-output audit byte-identity, which does not hold today, and the summary line misnames a dag_shape plan as "hollow gates"

The audit output differs between runtimes today:

```
hollow.json text: node "✗ 1 error(s), 0 warning(s) — this DAG has hollow gates; fix before running"   (hb-audit.js:203)
                  py   "✗ 1 error(s), 0 warning(s) — fix hollow gates before running"               (cli.py:464)
--json (every file): node {"findings":[],…}  vs  py {"findings": [], …}   (separators / ensure_ascii)
```

parity.sh:23-24 compares only `[errors, warns, sorted rules]`. k5 ("byte-identical across runtimes (text and --json)") is therefore unsatisfiable without changing audit output outside the contract, which goes against S1 P2's "nothing outside STRUCTURE changes". On a dag_shape-only plan, both summaries would also claim "hollow gates".

**Fold:** scope k5's byte-identity to the dag_shape finding (its text line and its JSON object, as s1c's shape:audit case already does). Make the error summary on a dag_shape plan name the structure failure instead of hollow gates, on both runtimes.

### N7 (MEDIUM): doctor's raw read reports spurious problems whose cures now refuse; the "doctor reports" class needs a short-circuit

On an unreadable dag (after one gate pass), doctor today reports:

```
  ⚠ state.json differs from the event-log projection — run: hb rebuild
  ✗ G: criteria drifted from the pinned evidence without sanction — sanction the revision through a full regate cycle …
```

Python doctor reports the same two lines, and node diagnose says "no blocker detected". After S2, `rebuild` and `regate` both refuse on that dag (s2b classes rebuild as a read verb and regate as mutating). Doctor would then point at the structure error and at two cures that cannot run. That is a recovery trap, and it pushes the agent toward a regate it does not need. r6 asserts only that doctor "exits 1 naming the errors".

**Fold:** when the checked structure test fails, doctor reports the structure errors and skips the plan-derived checks (drift, rot, projection, regate, detach). It can print one line, `plan checks skipped: dag.json invalid`. r6 asserts that doctor outputs no drift, projection or rot line. Diagnose's cure is the dag_corrupted action.

### N8 (MEDIUM): gate.sh exit-code precedence is unspecified

gate.sh's order today is: `--all` (l.~290) → no-arg usage, which lists `dag.gates` (exit 2, l.299-307) → unknown gate (exit 2, l.308-311) → regate (exit 3, l.316-318) → eval. On `gates: null` the unknown-gate `node -e` itself crashes. The plan says "exit 4 … all modes" but never says where the check sits relative to exits 2 and 3. A regate-pending gate in a structurally broken dag could exit 3 or 4. The drivers react differently: hb-exec.js:442 escalates only on 3 and otherwise loops back to tick.

Exit 4 itself is free. gate.sh exits 0/1/2/3, cli.py gate returns 0/1/2/3, and no test asserts 4 (grep over tests, py/tests and gate-examples).

**Fold:** the structure check is the first statement after argument parsing in every mode, including no-arg usage. Add an r5 case for a regate-pending gate inside a structure-invalid dag (exit 4 on both, no event), and the same rule for `hb gate`.

### N9 (LOW-MEDIUM): the message rule is ambiguous for existing rules that misfire

"One line per structure error: an existing rule's message where one already fires on that node" collides with today's output:

```
requires:"a1"  → ✗ [a2] requires a non-existent task: a   /  …: 1     (character iteration, 2 lines)
requires:"xyz" → 3 lines
gates:[]       → ✗ [A] undefined gate: G     (fires on the phase, not on the gates node)
gate_exit:5    → ✗ [A] undefined gate: 5  + ⚠ gate defined but never referenced: G
```

s1b also says existing rules "skip" malformed containers. Whether the requires rule "fires" (keeping the junk lines) or "skips" (giving a path line) is up to the implementer. k1 only asserts "at least one line".

**Fold:** "existing message" means only an existing shape message about that very node (today only `criteria entry N …`). Every other rule skips a malformed container, and the structure layer emits the path line. k1 asserts exactly one structure-attributable line per mutation.

### N10 (LOW): the derivation does not generate wrong-typed items for `requires`, though they crash six python readers

The `requires` node is annotated "array of strings", but item mutations are derived only "for arrays of objects". `requires:[["a1"]]` crashes plint, pres, pdoc, pdiag, pready and ptick (probe2.out). `requires:[null]` and `[5]` lint as errors and do not crash. **Fold:** for every annotated array, derive wrong-typed items from `items.type` (null, a number, a list, an object).

### N11 (LOW): lint errors outside STRUCTURE still crash read verbs, and no honest limit names them

From probe2.out, every one of these shapes is a lint ERROR today:

- `review:"x"` / `5` crash `hb refute-prompt` and `hb constraints --prompt` (python traceback).
- `review.profile:5` crashes refute-prompt on both runtimes.
- `constraints:[null]` crashes refute-prompt and constraints on both runtimes.
- `subjects:"x"` crashes the node versions of both.

hb-exec does stop (`HB-EXEC STOP: review_error`), so no driver spins. But GATE_S2's review prompt (a) asks for "ANY entry point … still crashes" on "a malformed … dag", and the honest limits only cover semantic errors and unenforced scalars. **Fold:** add an honest limit: lint-error shapes outside STRUCTURE (review, constraints, regate and criterion fields) keep today's runtime path, with the known read-verb crashes listed. Alternatively, scope review prompt (a) to STRUCTURE and unreadable.

### N12 (LOW): verb and tool derivation mechanics

- `grep "case '"` in hb.js returns 36 labels, including the projector's `initialized`, `task_started`, … `horizon_closed` (hb.js:122-156).
- cli.py adds start/done/fail/heartbeat in a loop (cli.py:70). prose-check.sh:14-17 already special-cases that loop.
- MCP TOOLS includes `code_context`, `code_discover` and `deplint`, which take inputs as parameters and never read `.hb/dag.json`. Under r8's "every other tool returns an error result" they would have to fail on an unrelated corrupt project dag.

**Fold:**
- Scope node enumeration to the CLI switch after `if (require.main === module)`.
- Derive the python verbs from the parser (`hb -h` choices, or a factored parser builder).
- Add an MCP class `exempt: does not read the project dag`.

### N13 (LOW): one more silent sleep remains

tick.sh:270-272 `[ ! -f "$NEXT_TASK_SCRIPT" ] && sleep_out no_next_task_script`. A missing resolver is the limiting case of a crashed resolver. **Fold:** make it a resolver_error wake, or name it as an honest limit.

### N14 (LOW): counts and scope wording

- "the six string-_meta plans" → nine files in k3's `planning/**/*.json` scope.
- "lints DISAGREE on exit status for 9 shapes" → 8.
- `planning/**/*.json` also matches constraints and refutation JSON (for example planning/regate/rg1-gate-constraints.json). k3 needs a dag predicate, such as "an object with a `phases` or `gates` key".

---

## Part 3: checks that hold

- **Probe-1 crash coverage.** Every crash in r1/probe.out is inside the claimed set except `_meta` non-object. I traced the python doctor, diagnose and tick crashes on `_meta` to lint.py:232 (`dag.get("_meta", {}).get(...)`), so lint.py's fix covers them, including `_meta: null`, which also crashes today. Crashes the probe set misses are N3, N10 and N11.
- **No existing dag breaks the claimed set.** structchk.py over every repo dag: only adapter fixtures (no `gates`; never read by readers) and broken.json (missing `criteria`, which is absence, not wrong type).
- **s3a anchor regex.** It is sound. GNU `grep -E` supports `\b`. `[ -n "$ids" ]` blocks the vacuous pass. `\(r1\)` does not match `(r10)`. `ids=$(grep … | sort -u)` turns a missing doc into an empty id list, which then fails. The regex picks up no stray tokens such as `sr1` / `k8s`. Its weakness is that it proves cited ids exist, not that every claim cites one; the review covers that.
- **s3w.** The ten existing docs are prose-clean today (`ALL-PROSE-OK:10`), so `:11` with the new how-to is reachable.
- **Budget.** Derived from the real schema: about 66 k1 mutations (root/phases/phase/tasks/task/criteria containers at 5 types each, plus 3 entry types per array of objects, ids at 3, refs at 2, parked at 4) plus 7 k2. That is about 73 fixtures × (bootstrap 0.12 s + setup ~0.1 s + 4 ticks ~0.9 s + 2 resolvers + gate + doctor + lint + audit ≈ 1 s), roughly 160 s. Add 5 representatives × about 85 verb/tool/gate calls (~35 s) and k3 (~90 dags × 3 lints, ~20 s). The default run comes to about 250-300 s, inside 600 s. The full selftest is about 200-300 s, inside 900 s. The suite would grow from 873 s to roughly 1400-1700 s, inside 3000 s.
- **Suite pins at S1.** audit-rules-check derives rules from source, so the count docs going stale until S3 is not test-pinned. The hook stop list has no cross-surface pin (hook-drives-loop.sh E needs only one of four keys). T21.1's template skeleton warning is preserved by k3. T137 is untouched because the parity cases are inline. T12.5 (`dag_corrupted` on `{broken`) stays true. No test asserts `no_pending_tasks` from tick.sh's swallow path.

## Verdict reasoning

N1 makes GATE_S2 unpassable on a correct implementation, because s2f's full suite fails T124.1 until S3 writes the row. N2 makes s1x unpassable in S1. N3 and N4 are holes in the wave's own headline guarantee:
- N3: a plan both lints reject is dispatched to a gate that crashes, forever. The derivation and the design also contradict each other on it.
- N4: `{}` sleeps silently forever.

N5 and N6 are byte-identity requirements that cannot be met as written. The other findings are small specification gaps. The round-1 folds otherwise landed and are coherent.

VERDICT: UNSOUND
