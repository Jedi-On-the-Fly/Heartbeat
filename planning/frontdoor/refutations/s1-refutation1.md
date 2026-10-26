# GATE_S1 refutation, round 1

Setup: `unset HB_DIR PROJECT_DIR GATE; export HB_NO_GIT=1 STUCK_TICKS=999`. Mutation copies of the repo (with .git, without .hb) under mktemp dirs. The repo tree was not modified. No tool was run against the repo's .hb.
Harnesses (scratchpad-adjacent, /tmp/claude-1000): `both.sh` (lint+audit --json on both runtimes), `cmp.py` (about 55 fuzz fixtures; compares sorted lint lists, full audit JSON, exit codes, tracebacks).

## Baseline
- `bash tests/dag-shape.sh lint` -> `SHAPE-LINT-OK (94 derived structure mutations, 86 existing dags against the a500587 oracle)`.
- `--selftest lint` -> `SHAPE-SELFTEST-LINT-OK`.
- `bash tests/parity.sh` -> `PARITY OK`; `tests/horizon.sh` -> `HORIZON-OK`; `tests/replan.sh` -> `REPLAN-OK`; `pytest -q py` -> all dots, no failures.

## Direct G probes (repo, both runtimes)
- G1 `{"phases":[],"gates":{"10":"x","9":"y"}}`: lint errors `["gates.9 ...","gates.10 ..."]` on both; audit dag_shape names `gates.9` on both, byte-identical.
- G2 the `__proto__` gate: both give `[__proto__] criteria entry 0 ... (got a string)` plus never-referenced warnings for `__proto__` and `Z`, exit 1. Audit agrees.
- G3 phases[0] with id missing / 5.0 / true / "" / null / -0.0 / 1e400 plus all four detach fields: only the id error line, identical on both. No `[undefined]`, `[None]`, `[5]` or `[true]`.
- G4 criteria entries 1.0, -0.0, 12345678901234567890, 1e400, -1e400, 1E5, 0.1e1, 1e-400, 130 non-BMP emoji (raw and escaped): all render `(got a number)` / `(got a string)`, byte-identical.
- G5 `_meta` nested 10, 255 (both accept, `{"errors":[]}`), 256, 257, 600, 5000, object-nested 300, and a depth-1000 array inside a criterion: all `dag.json unreadable: nested too deeply`, exit 1, identical on both, no traceback. Brackets inside strings (1000 `[`, escaped quotes) are accepted by both.
- G6 `parked` = [] {} 0 "x" null [1]: audit findings, errors, warns and the parked list identical on both (`parked: []`, 2 errors).
- G7 k4's checker over `regate.bogus`, `regate.rearm.extra` and `review.bogus2`: prints `undeclared: ['.gates.G.regate.bogus', '.gates.G.regate.rearm.extra']`, exit 1. `review.bogus2` is NOT listed: the schema declares `review` with `additionalProperties: true` (explicit, plugin/dag.schema.json line 76). Real dags use only `prompt`/`profile`/`constraints`, and no verb writes `review`.

## Mutation results (copy, `bash tests/dag-shape.sh lint`)
| Re-introduced wrong implementation | Result |
|---|---|
| G1 python without `_js_order` | RED: `k7 [integer-like gate keys]: lint outputs differ` |
| G2 node `structureView` gates built by assignment (`gates[g]=gv`) | RED: `k7 [a gate named __proto__]: lint exits differ (node=0 py=1)` |
| G3 node `checkDetach` without the invalid-id skip | RED: `k7 [detach fields on an invalid-id phase]`, node emits `[5] a detached phase id ...` |
| G3 python `_check_detach` without the skip | RED: the same k7 case, python emits the `[5]` line |
| G4 python `_type_name` renders the value (`json.dumps`) | RED at `k1 [gates.G1.criteria[0]=[]]`: node `(got a list)` vs py `(got [])` |
| G5 node without the `tooDeep` call | RED: `k2 [nested 300] ... node=0 py=1` |
| G5 python without the `_too_deep` call | RED: `k2 [nested 300] ... node=1 py=0` |
| G5 node `MAX_DEPTH = 100000` | RED: `k2 [nested 300]` |
| G6 node view keeps non-boolean `parked` | RED: `k7 [parked []]: audit results differ ... parked ["P2"] vs []` |
| G7 schema regate/rearm `additionalProperties` removed | RED: `k4 teeth: the declared-key checker missed a planted key` |
| G7 `hb.js` and `cli.py` each writing `rearm.leak` | RED each: `k4 (node)` / `k4 (py)`: `undeclared: ['.gates.G1.regate.rearm.leak']` |
| audit `'?'` for a missing criterion id removed, both runtimes | RED: `k7 [criteria entry 1.0]` (node `G1[undefined]` vs py `G1[None]`). The pin is only the non-object entries. |

Derivation is schema-driven (the `derive()` python run on schema variants): original 94 cases; removing `parked`'s annotation -> 88; removing the tasks-items annotation -> 88; annotating `project` -> 100; annotating `title` -> 100; widening `phases[].id` type -> 92.

## Other hunts (P1-P4)
- Fuzz (about 55 cases, `cmp.py`): BOM, invalid UTF-8, duplicate keys, unicode keys, lone surrogates, NaN/Infinity, empty/whitespace files, top-level null/array/number/string, float/huge ids, `constructor`/`toString` names, 500k-element array, many closers: lint (sorted) and audit agree, no traceback.
- k3's oracle extracts a500587's linters via `git show` / `git archive` and runs them. The 86-dag floor is enforced.
- `tests/replan.sh` T184: the old `exit 0` expectation became `exit 1/1`. The `[?]` bytes assertion is kept and a path-named error assertion added, so it is stricter.
- Parity shape cases are inline (`mktemp` and `printf`), with node-side non-vacuity floors.

## Findings
1. parity-notes is stale on a shipped part of the contract. `grep -n -i "too deeply|nested|nesting|256|_js_order|integer-like" planning/parity-notes.md` returns nothing. The notes list the fixed unreadable classes as `missing / cannot be read / empty / not valid JSON / top level is not an object` (line 463), but lint and audit also emit `dag.json unreadable: nested too deeply` (bound 256, a pre-parse text scan). The JS-integer-key ordering adoption is not recorded either.
2. Side, low severity (cross-runtime divergence on a structure-VALID dag, same class as G2 for task ids). `{"phases":[{"id":"P","tasks":[{"id":"__proto__","requires":["__proto__"]}]}],"gates":{}}`: node lint says `✓ DAG valid`, exit 0; python says `dependency cycle: __proto__ -> __proto__`, exit 1. The a500587 node lint behaves the same (pre-existing), so P2 holds, but a self-cycle slips through node lint.
3. Side, low severity (value-tier, outside STRUCTURE). Audit messages for criteria whose `id` is a non-string differ: id 5.0 -> `G[5]` (node) vs `G[5.0]` (py); true -> `G[true]` vs `G[True]`; `[1]` -> `G[1]` vs `G[[1]]`; `{"a":1}` -> `G[[object Object]]` vs `G[{'a': 1}]`. The `'?'` fix covers only missing/null.
4. Side, low severity. Node writes lint/audit `--json` output with `process.exit` after `console.log`, so piped output truncates at 64 KiB (5000 junk phases -> 65536 of 163917 bytes). The new one-line-per-violation rule makes this easier to hit. The pattern is pre-existing.
5. Gap in G7's coverage. k4's teeth plant bogus keys in regate, rearm, a phase and a task, but not in `review`. `review` stays `additionalProperties: true` by design, so the G7 text "a gate's review is detected" is not met literally. The constraint's own failure condition (`undeclared: []`, exit 0) does not reproduce.

## One line per id
P1: NOT-REPRODUCED — 94 derived mutations plus about 55 fuzz fixtures (`cmp.py`) give exit 1/1, identical sorted lists, no traceback; unreadable classes carry fixed bytes (k2 and the depth-5000 probe).
P2: NOT-REPRODUCED — `dag-shape.sh lint` k3 ran the extracted a500587 linters over 86 existing dags; parity, horizon, replan and `pytest -q py` all green.
P3: NOT-REPRODUCED — the schema-variant run changes the case count (94 -> 88 / 100 / 92); `rearm.leak` mutants in `hb.js` and `cli.py` each redden k4.
P4: VIOLATED — `grep -n -i "too deeply|nested|nesting|256|_js_order" planning/parity-notes.md` returns nothing: the fixed-bytes class list (line 463) omits `nested too deeply` (bound 256), and the JS key-order rule is unrecorded, so the contract note is stale (dag_shape, T184, parity and strips themselves held: dag_shape single and identical on every probe, T184 stricter, strips red for the right reason).
G1: NOT-REPRODUCED — `{"phases":[],"gates":{"10":"x","9":"y"}}`: both audits give `dag_shape ... gates.9 must be an object`, lint lists identical; mutation without `_js_order` reddens k7.
G2: NOT-REPRODUCED — the `__proto__` gate probe gives identical errors, warnings and exit 1 on both; the assignment-built-gates mutant reddens k7.
G3: NOT-REPRODUCED — invalid ids (missing, 5.0, true, "", null, -0.0, 1e400) with detach fields give only the path-named id error on both; both skip mutants redden k7 and the `\[(5|5\.0|undefined|None|true|True)\]` detector is in place.
G4: NOT-REPRODUCED — 1.0, -0.0, 12345678901234567890, 1e400 and 130-emoji entries all give `(got a number)` / `(got a string)` byte-identically; a value-rendering mutant reddens k1.
G5: NOT-REPRODUCED — depths 255 accepted by both, 256 up to 5000 `nested too deeply` exit 1 on both, no traceback; three depth mutants redden k2.
G6: NOT-REPRODUCED — parked []/{}/0/"x"/null/[1] give identical audit findings, errors=2, parked=[] on both; the mutant keeping parked reddens k7 (`parked ["P2"]` vs `[]`).
G7: NOT-REPRODUCED — k4's checker flags `regate.bogus` and `regate.rearm.extra` (exit 1), schema-open mutant and both `rearm.leak` verb mutants redden k4; note finding 5 (`review` is explicitly open and untested by teeth).

REFUTED

HOLES: planning/parity-notes.md omits the shipped `nested too deeply` class and 256 bound and the JS key-order rule (P4); side findings 2 (node `__proto__` task self-cycle passes lint while python errors), 3 (non-string criterion id renders differently in audit messages), 4 (node `--json` output truncates at 64 KiB when piped).
