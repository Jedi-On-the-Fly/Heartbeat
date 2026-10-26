# GATE_S1 refutation, round 2

Setup: `unset HB_DIR PROJECT_DIR GATE; export HB_NO_GIT=1 STUCK_TICKS=999`. Mutation copies under /tmp/claude-1000/r2* (rsync of the repo, .hb excluded; the three tracked planning/refuter-*/.hb dirs copied back in). Probe fixtures in /tmp/claude-1000/p2xAvl. Repo tree untouched.

## Baselines (repo)
parity.sh PARITY OK; horizon.sh HORIZON-OK; replan.sh REPLAN-OK; pytest 187 passed; `--selftest lint` SHAPE-SELFTEST-LINT-OK; copy `bash tests/dag-shape.sh lint` -> SHAPE-LINT-OK (94 derived structure mutations, 97 existing dags against the a500587 oracle).
Round-1 finding: parity-notes now records the 256 bound ("nested too deeply", line 464), integer-key ordering (482) and the prototype-free maps (483). Round-1 side finding 2 (node `__proto__` self-cycle) now agrees: both runtimes give `dependency cycle: X -> X` exit 1 (probed __proto__, constructor, toString).

## G1 probes
gate_exit / gate_entry / detached_from each set to constructor, toString, hasOwnProperty, valueOf, __proto__, isPrototypeOf with `gates:{}`: node and python give identical error lists (`[P] undefined gate: <k>`, `[Q] detached_from must name a defined gate ... (got "<k>")`), exit 1 both (only json spacing differs, as always). hb-lint.js builds the view's gates with Object.create(null).
Mutants: m1 gates = {} -> RED `k7 [a gate named __proto__]` (node=0 py=1). m10 gates = {} + defineProperty (so __proto__ keys still work, constructor inherited; node then lints the constructor reference exit 0) -> RED `k7 [a gate_exit referencing 'constructor']: lint exits differ (node=0 py=1)`. So the reference pin has its own teeth.

## G3 probes
`--questions` on: gate value "x" / 5 / [] ; gates "abc"; criteria "abc"; phases "x"; missing, truncated, empty, BOM, top-level [] files: all exit 1 on both with the identical fixed line `dag.json structure is invalid: <first structure error> — run the lint ...`, no traceback. `{gates:{}}` with constructor/toString/__proto__/hasOwnProperty: `no gate` exit 0 on both. A gate literally named constructor with criteria: a checklist on both, toString `no gate` on both. cmd = 5/null/[1]/{}/true: identical, exit 0. A 3000-criterion plan: 383152 bytes on node, python, piped through `cat` and through a delayed consumer; cmp of node and python outputs IDENT. 
Mutants: m3 node reviewQuestions raw `dag.gates[gate]` -> RED (constructor outputs differ). m5 process.exit(0) after write -> RED `a large node checklist was truncated when piped`. m6 node fail-closed removed -> RED (exits node=0 py=1). m7 python fail-closed removed -> RED. m4 python raw `.get` lookup instead of the view stayed GREEN, but it is an equivalent mutant: the fail-closed gate runs first, so the view and the raw dict cannot differ there.
Minor (not STRUCTURE, pre-existing CLI arg parsing): `hb-audit.js f.json --questions` with no gate prints `no gate 'undefined'` exit 0, python's argparse errors exit 2.

## G2 probes
Mutant m2 (adapter-fixture glob removed) -> RED but by the 90-dag floor (86 < 90), so the inventory includes them. Allowlist assertion is exact (`post.errors == [<key>: missing...] + pre.errors`, warnings equal).
Repo-wide scan (git ls-files -co, JSON object with phases or gates): every dag-like file is in k3's list EXCEPT three tracked files: planning/refuter-authoring/.hb/dag.json, planning/refuter-economics/.hb/dag.json, planning/refuter-profiles/.hb/dag.json. Python's glob(recursive=True) skips dot-directories, and `ls-files` shows all three tracked. Today their lint output is unchanged (✓ DAG valid on a500587 and post-wave), so nothing is wrong yet, but the oracle cannot see them.
Mutant m9: hb-lint.js appends `MUTANT flip` as an error only when the path contains `planning/refuter-` and `/.hb/dag.json`. `node plugin/templates/hb-lint.js planning/refuter-economics/.hb/dag.json` -> `✗ MUTANT flip`, exit 1, while `bash tests/dag-shape.sh lint` -> `SHAPE-LINT-OK (94 ..., 97 existing dags ...)` GREEN. Mutant m8 (the dag's gates key removed, so lint gains `gates: missing`) -> GREEN as well. A flip on a shipped dag is silent, contradicting G2's "applied repo-wide / sees every dag the repository ships".

## P1-P4
P1: NOT-REPRODUCED — derived mutations and the G1/G3 fuzz above give identical sorted lists, exit 1/1, no traceback; k7 and k2 held in baseline.
P2: NOT-REPRODUCED — k3 (97 dags) green, python agrees with node; the three uncovered .hb dags lint unchanged by hand (✓ valid on oracle and post); parity, horizon, replan, pytest green.
P3: NOT-REPRODUCED — baseline derive-based count 94; round-1 schema-variant behaviour not re-run, but nothing in this round's diff changed dag-shape derivation; k4 green in baseline.
P4: NOT-REPRODUCED — audit dag_shape / questions probes identical on both runtimes; parity-notes now carries the depth bound, key-order and prototype-free sentences (true per m10); parity, replan, selftest green.
G1: NOT-REPRODUCED — 18 reference probes agree on both runtimes (exit 1, same error); m1 and m10 mutants redden k7, m10 on the reference pin specifically.
G2: VIOLATED — `bash tests/dag-shape.sh lint` stays `SHAPE-LINT-OK (94 ..., 97 existing dags ...)` with a lint mutant that errors on planning/refuter-economics/.hb/dag.json (command output above: node lint prints `✗ MUTANT flip`, exit 1); python glob skips dot-dirs so the three tracked planning/refuter-*/.hb/dag.json dags are outside k3's inventory. The ten adapter fixtures are covered (allowlist exact), but the "every dag the repository ships / predicate applied repo-wide" requirement is not met.
G3: NOT-REPRODUCED — all malformed/unreadable `--questions` probes give the same fixed line exit 1 on both, 383152-byte checklist whole when piped, constructor handled via own-property on both; mutants m3, m5, m6, m7 redden.

REFUTED

HOLES: G2 — k3's inventory (python glob) skips dot-directories, so the three tracked dags planning/refuter-{authoring,economics,profiles}/.hb/dag.json are never lint-compared against the a500587 oracle (mutant m9 green). Fix: build the inventory from `git ls-files` (or walk with dot-dirs) with the same predicate. Minor side note: `hb-audit.js f --questions` with no argument exits 0 `no gate 'undefined'` vs python argparse exit 2 (pre-existing, outside STRUCTURE).
