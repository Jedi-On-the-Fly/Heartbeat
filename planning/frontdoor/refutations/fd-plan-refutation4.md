# Refutation round 4: planning/frontdoor.dag.json (S1/S2/S3)

Scope: read-only. Probes ran in `mktemp -d` dirs and one throwaway `git clone`, which was deleted afterwards. Nothing ran against the repo's own `.hb/`. `git status` afterwards shows only the two pre-existing untracked paths. The one read-only checker run in place was `prose-check.sh`.

Probe material is in `scratchpad/r4/`:
- `run.sh`: the census runner.
- `census-r4.jsonl`: the census output.
- `pytest.log`, `parity.log`, `fuzz.log`, `suite.log`: the run logs.

Round 3's census logged only file reads (node `readFileSync`, python `read_dag`, lint, cli, tick). This round adds an **in-memory** census. The clone's `resolver.resolve`, `resolver.ready_tasks`, `audit.audit`, `audit.review_questions`, `report.refuter_impact`, `state.project` and `lint.lint` were wrapped to log every *dict argument* that breaks the new STRUCTURE set, including a missing `phases` or `gates`. Every suite stayed green under the census:
- Node suite: `RESULT: 476 passed, 0 failed`, GROUPS-RAN 185, skipped 0.
- Pytest: 187 passed.
- Parity: `PARITY OK`.
- Fuzz: `FUZZ-PARITY-OK:12`.

---

## Part 1: R3 convergence

| # | Round-3 finding | Landing text (quoted) | Coherent? |
|---|---|---|---|
| R3-1 | python no-arg `hb lint` / `hb audit` read the raw fallback | design "readers fail closed": "lint and audit read through the structure layer's own checked FILE read — never read_dag's silent empty-plan fallback — with or without a file argument, on the CLI and the MCP lint/audit tools … the raw read_dag stays only for doctor/diagnose's tolerance". s1b: "is the read path of lint and audit with or without a file argument (python's no-arg CLI and the MCP lint/audit tools included — never read_dag's empty-plan fallback)". k2: "every k2 class ALSO runs python's no-argument `hb lint --dir P` and `hb audit --dir P` (exit 1, the fixed bytes, never 'DAG valid' / 'gates look behavioural')". r8: "lint returns the errors (on the unreadable representative: 'dag.json unreadable: …')". | **Yes, except one stale sentence in s2c.** s2c still says "state.read_dag_checked (the raw read_dag stays for lint, audit, doctor, diagnose)" (R4-2). Probed for collateral damage: the only test of python no-arg lint is `test_cli.py:47`, which runs `hb lint --dir` on a freshly `init`ed valid project and expects 0, and that still holds. `park-phase.sh` runs `hb audit --dir` on valid dags. No test drives the MCP lint/audit tools (`mcp-*.sh` call deplint/tick/state on valid dags only). Nothing pins today's `dag.json unreadable: ${e.message}` text or python's file-argument traceback (grep over tests, py/tests and gate-examples: no hits). |
| R3-2 | MCP class table vs r1/r2 | design: "MCP tools per class (R3-2): tick returns the dag_corrupted wake (as r1), next returns deadlock dag_invalid (as r2), lint returns the errors, audit returns its findings incl. dag_shape, doctor/diagnose report, the three dag-independent tools are exempt, and every other tool (ready, state, report, gate, start, done, fail, review, …) returns an error result". r8 and GATE_S2 P2 use the same wording. | **Yes.** s2c's "every mcp_server tool per s2a's class table (an error result, never a raise)" defers to the table, but its parenthetical reads as if every tool returns an error result (R4-2). |
| R3-3 | lone surrogate | design: "An unpaired surrogate escape in any string or key is also 'dag.json unreadable: not valid JSON' on both runtimes". k2: "plus an unpaired surrogate escape in a string and in a key". s1b: "unreadable/empty/missing/non-object top/unpaired surrogate = the first error". | **Yes.** I probed for conflicts. All 151 JSON files under tests/fixtures, planning and plugin parse strictly (no NaN, no BOM) and carry no surrogate code point in a dag. The only surrogate escape in the repo is `tests/fixtures/review-holes/refuse.json`, a review-answer list read by `checkHoles`/`check_holes`, never by a dag reader. Literal non-BMP characters appear only in `tests/fixtures/review-answers/{edges,legit}.json`, also lists and not dags. The rule says *unpaired*, so python's `json.dumps` paired escapes for emoji stay valid. |
| R3-4 | k5 "exactly one" ambiguity | design audit: "exactly one finding with rule dag_shape … the other rules still run tolerantly (test_hardening.py's hollow_gate … and parity hostile-criteria:audit's no-hollow floor stay; R3-4) — with every field of the dag_shape object (severity, phase, extras) mirrored, since horizon.sh t7 compares full finding objects". k5: "exactly one finding with rule dag_shape (the other rules still run tolerantly …) … never 'hollow gates', even when hollow_gate co-fires". s1b: "every field of that object mirrored". | **Yes.** horizon.sh t7 (l.464-488) compares `[errors, warns, sorted full findings]`. A mirrored dag_shape adds +1 to errors on both runtimes, so t7 stays equal. |
| R3-5 | empty-phases limit | honest limits: "a plan with an EMPTY phases array is valid and the tick sleeps no_pending_tasks; only an absent or wrong-typed container fails closed (round-3 R3-5)". s3a: "the HONEST LIMITS from _meta (including the empty-phases plan that still sleeps)". | **Yes** |
| R3-6 | skip rule, "today only", t7 pre-check, absent criteria/tasks | design lint: "every other rule SKIPS a malformed container, every wrong-typed item of an annotated array (requires:[1.0] …), and a phase or task whose id is STRUCTURE-invalid in the id-keyed rules — keeping the '[?]' rendering where T184 pins it". It also has "e.g. '[G] criteria entry N …'; hb-lint.js's other shape messages at the criteria and phase levels count likewise". design STRUCTURE: "OUTSIDE the contract by design: a gate missing criteria and a phase missing tasks … broken.json's G0/G1 stay byte-equal under k3". pre-checks: "horizon.sh t7's hostile GATE shapes ARE structure shapes and now also exercise dag_shape". | **Yes for what it names.** The skip rule still omits one STRUCTURE class: wrong-typed gate references (R4-1). |

## Part 2: questions the brief asked, answered by probe

- **Does the checked read for lint/audit break an existing test?** No.
  - Python no-arg CLI lint/audit appears only on valid dags: `test_cli.py:47`, `park-phase.sh:34-64`.
  - The MCP lint/audit tools are never called by a test.
  - Every file-argument call (`detach.sh:276`, `regate-fail-closed.sh:340`, `replan.sh:499`, `detach-surfacing.sh:141`, `horizon.sh`, `constraints-schema.sh:65`, `parity-selftest.sh:31`) passes an existing, parseable file.
  - Census: no test reads a missing or unreadable dag, apart from T12.5's `{broken` tick (unchanged key).
- **Does the unpaired-surrogate rule conflict with a fixture?** No (Part 1, R3-3).
- **Node lint CLI on a missing file today.** It exits 1 with `✗ dag.json unreadable: ENOENT: …` on stderr (`--json`: `{"errors":["dag.json unreadable: ENOENT…"]}`). Nothing greps that text, so the fixed `dag.json unreadable: missing` bytes conflict with no pin.
- **In-memory dags.** These are new this round. Across pytest, parity, fuzz and the full node suite (python side), the only dict-level calls with a STRUCTURE break are the known deliberate ones:
  - test_hardening and parity hostile-criteria items: `gates.GATE_H.criteria:item`.
  - replan.sh's id-less phase.
  - horizon.sh t7's twelve shapes.

  No test hands `resolve` / `ready_tasks` / `audit` / `project` a dag missing `phases` or `gates`. S2's in-resolver structure check therefore reddens nothing.
- **k3 oracle feasibility.**
  - All 86 dags in scope (template, planning/**, tests/fixtures) pass the structure check.
  - The current node lint and python lint agree on 80 of them. The remaining 6 crash python only on the string `_meta`. With `_meta` neutralised, all 6 agree byte-for-byte.
  - hb-lint.js has no filesystem or `__dirname` dependence, so running the a500587 copy from a mktemp tree gives the same bytes.
- **Gate mechanics.**
  - GROUPS-PASSED ends with a trailing space (`… T184 T185 $`), so s3y's `" $g "` matches the last group.
  - The 10 existing S3 docs are prose-check clean today (`ALL-PROSE-OK:10`), so s3w needs only the new how-to.
  - s2t: `require('./plugin/templates/hb.js').PROTOCOL.dag_corrupted` resolves without running main. `immutable` occurs only at hb.js:55, protocol.py:15 and tick.sh:162.
  - Exit 4 is unused by gate.sh and by python `hb gate`.
  - Both exec drivers already print `HB-EXEC STOP: <reason>` generically (hb-exec.js:127, executor.py:595).
  - No cross-surface stop-set consistency test exists, so adding the stop set to the hook and mcp_server in S2 and to SKILL and the how-to in S3 creates no intermediate red.

---

## Part 3: new findings, ranked

### R4-1 (LOW-MEDIUM): the skip rule omits wrong-typed gate references, so the design's "keeps its message bytes everywhere else" contradicts k1

`gate_entry` / `gate_exit` are STRUCTURE (string|null). s1a derives "for a string|null reference a list and a number". The design's skip list covers malformed containers, wrong-typed array items and STRUCTURE-invalid ids, but not a wrong-typed reference *scalar*. Read literally, the gate-reference rules ("undefined gate", "gate_entry … is no phase's gate_exit") keep running there with their message bytes. Today, with a valid base and `P1.gate_exit` mutated:

```
gate_exit=5      node "[P1] undefined gate: 5"                py "[P1] undefined gate: 5"
gate_exit=5.0    node "[P1] undefined gate: 5"                py "[P1] undefined gate: 5.0"
gate_exit=true   node "[P1] undefined gate: true"             py "[P1] undefined gate: True"
gate_exit=[]     node "[P1] undefined gate: "                 py (no line)
gate_exit={}     node "[P1] undefined gate: [object Object]"  py (no line)
gate_exit=["G1"] node (no line: coerces to "G1")              py TypeError: unhashable type: 'list' (traceback)
```

k1 demands "EXACTLY ONE structure-attributable line … sorted error lists byte-identical", and the S1 review (b) fuzzes "floats as ids". So the implementer *must* also skip these rules on a wrong-typed reference, which departs from the design text. The gate is not unpassable, because k1 governs and the fix is obvious. But the plan says two different things about the same node, and the S1 reviewer could cite either sentence. Audit already agrees across runtimes on these shapes (probed: identical rule sets), so the fix is lint-only.

**Fold:** in design "lint" and s1b, extend the skip clause: "… and a phase whose gate_entry/gate_exit is STRUCTURE-invalid in the gate-reference rules (undefined gate, gate_entry-locked): the structure line is its only line". In s1a, name the derived reference values (e.g. `5`, `[]`) so k1 covers both the extra-line case and the divergence case.

### R4-2 (LOW): s2c has two stale parentheticals that contradict the R3-1 and R3-2 folds

- s2c: "state.read_dag_checked (the raw read_dag stays for **lint, audit**, doctor, diagnose)". The design now says "the raw read_dag stays **only for doctor/diagnose**", and s1b moves lint/audit (CLI and MCP) onto the checked file read. An S2 implementer following s2c could revert the MCP `_lint`/`_audit` to `st.read_dag(hb)`. r8's unreadable-representative assertion would catch that, so it is a reading hazard, not an open hole.
- s2c: "every mcp_server tool per s2a's class table (**an error result, never a raise**)". This can be read as "every tool returns an error result", against R3-2's tick/next classes.

**Fold:**
- s2c: "(the raw read_dag stays only for doctor and diagnose; lint and audit already read through S1's checked file read)".
- s2c: "every mcp_server tool per s2a's class table (tick → the dag_corrupted wake, next → deadlock dag_invalid, the error-class tools → an error result; none raises)".

### R4-3 (LOW): "nine string-_meta planning files" is six

Every JSON under `planning/**` whose `_meta` is a string: `detach`, `mcp-drive-loop`, `refuter-authoring`, `refuter-economics`, `refuter-profiles`, `regate` (`.dag.json`). That is six, and each is a dag that crashes pre-wave python lint (`AttributeError: 'str' object has no attribute 'get'`). No other dag in k3's scope crashes. Both `_meta.design.lint` ("nine planning files carry a string") and k3 ("the nine string-_meta planning files") say nine. If k3 or the review counts them, the gate is unpassable on a correct implementation.

**Fold:** "six" in both places, or drop the number ("every string-_meta planning file"). k3 must not assert the count.

---

## Verdict reasoning

Every R3 fold landed and is coherent across `_meta`, the tasks, the criteria, the constraints and the review prompts, apart from the s2c stale text (R4-2).

The brief's three re-probes found no collision:
- No existing test calls python lint/audit (CLI or MCP) on a missing or unreadable dag expecting today's output.
- No fixture or test carries a lone surrogate in a dag.
- Node's current missing-file lint text (exit 1, `unreadable: ENOENT…`) is pinned by nothing.

The new in-memory census shows that no test feeds the resolver, audit or projection a structurally broken dict beyond the known deliberate shapes.

No gate is unpassable on a correct implementation, provided k3 does not hard-code "nine". No gate passes with the work broken. The three findings are wording contradictions with exact folds. R4-1 is the only one that changes code behaviour, and k1 already forces the right behaviour. Folding them before the run is cheap and recommended, but none blocks soundness.

VERDICT: SOUND
