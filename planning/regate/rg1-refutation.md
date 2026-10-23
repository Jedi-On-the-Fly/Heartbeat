# GATE_RG1 refutation (correctness refuter)

All probes ran in mktemp fixtures (/tmp/tmp.ClycQ55XMk/*) or in rsync copies of the repo. The repo tree and its .hb/ were not modified. Helper scripts are in `.../scratchpad/rf/` (lib.sh, mut.sh).

## Baseline
- `bash tests/regate-fail-closed.sh` prints REGATE-FAIL-CLOSED-OK.
- `--selftest` prints REGATE-FAIL-CLOSED-SELFTEST-OK.
- `pytest -k regate` and `parity.sh` are green.
- Spec-first is not provable from the repo. Nothing is committed, and the log keeps no RED run. The `.hb/events.jsonl` timestamps show rg1a (write the test) running 12:48-12:58Z, before rg1b. `tests/regate-fail-closed.sh` was last edited after rg1e.

## Mutation sweep (single-site guard strips against the full non-selftest suite, on repo copies)
I deleted each guard site's line range in a copy and ran the full `tests/regate-fail-closed.sh`. A guard that is not load-bearing leaves the suite green.

| Site | Result |
|---|---|
| gate.sh 313-314, 274-276, 284, 262-263 | red |
| gate.py 99-100, 183, 248 | red |
| gate.py 231-235 | **green** (the stripped copy crashes with `NameError: _rg_live`, and the test only asserts a nonzero exit) |
| review_policy.py 41-42 | red |
| hb.js 994-995 | red |
| executor.py 478-479, 542-543 | red |
| tick.sh 307-308, 333-334 | red |
| tick.py 153-154, 159-160 | red |
| hb-lint.js 80, lint.py 68 | red |
| **hb.js 885-886 (node `constraints --record` guard)** | **GREEN, so the test is hollow** |
| **hb-exec.js 439 (exit-3 escalation)** | **GREEN, so the test is hollow** |
| constraints.py 172-173 | green in the shell suite, red in pytest |
| executor.py 309-310 | green in the shell suite; covered only by the m5 pytest |

- **Node constraints guard.** The test records constraints with subject `m.txt`, which does not exist in the fixture. With the guard stripped, the record is still refused, by the subject-must-exist rule (`no subject names a real project path`). I put a real `m.txt` in the fixture and stripped the guard. Node then printed "constraints recorded for GATE_B" with rc=0 and appended a `constraints_recorded` event. Python behaves the same without its guard. Python is caught only by pytest `test_regate_constraints_record_refused`. The node guard is caught by nothing.
- **hb-exec.js exit-3 escalation.** The shim check only greps the executor's output for "regate". That text is gate.sh's own refusal line, which `stdio:'inherit'` passes through. It does not prove the exit-3 branch is reached. The selftest has no mutation for this site.

## Per-id probes and answers

### P1
- gate.sh single, `--check`, `--all` (ever-passed and never-passed), python `gate`/`--check`/`--all`, diagnose (both runtimes), direct `accept_review` and the CLI review verdicts, and constraints on both runtimes all refused. No criterion ran (the executed.flag was never touched) and no gate or review event was appended.
- Exit 3 and the sweep failing both held. The sweep printed "❌ 1 failing criteria" with rc=1, and python returned 1.
- Side findings, none a bypass of a declared record:
  - **Runtime divergence on a malformed marker.** With `regate.pending` set to `[]` or `{}`, `gate.sh GATE_A` exits 3 (node refuses) and `PY gate GATE_A` exits 0 and runs the criteria (executed.flag touched). JS treats `[]` and `{}` as truthy and Python as falsy. Lint flags the record, but the evaluation perimeter itself diverges.
  - **Phase-id slip.** Declare resolves phase ids, but the review guard is keyed on the raw typed id. After `regate B`, `HB_ACTOR=rev hb review B fail x` exited 0 on both runtimes and appended `{"event":"review_failed","gate":"B"}`, which bumped build_stuck_count. The same call is accepted for any unknown id without a regate, and `review B pass/free` is rejected for other reasons. The effect is bookkeeping only.
  - **Direct anchor write.** `hb.js anchor GATE_B` on a pending gate writes `anchors/GATE_B.json`. `tryAnchor` keeps an existing anchor, so a pre-written one would freeze the gate's accepted-file snapshot.

P1: NOT-REPRODUCED — every declared-record path (gate.sh single/`--check`/`--all` in both fixture states, `PY gate`, `PY diagnose`, `accept_review` called directly for pass/fail/free, node and python CLI review, constraints on both runtimes) refused, ran no criterion and appended no event. Only malformed or hand-edited markers differ (the `pending: []` runtime divergence, the phase-id `review fail` slip), listed above.

### P2
- Sequential refusals held: empty reason, unset/blank/"unknown" `HB_ACTOR`, unknown id, gateless phase and second declare. All exited nonzero, left the dag md5 unchanged and added no event, on both runtimes.
- The python declare left the projection unchanged apart from `last_event` and `last_updated`.
- **Second-declare guard is racy.** In hb.js the pending check reads the dag before `withWlock`. Python's declare takes no lock at all (`dagpath.write_text` in cli.py). I ran six concurrent `HB_ACTOR=aN node .hb/hb.js regate GATE_A rN` in a fresh fixture, 12 rounds. The maximum was 3 `gate_regated` events from 6 concurrent declares. Two or more succeeded against a gate that had no pending record when each read the dag, and the last writer's snapshot and actor replaced the earlier ones. The sequential test cannot see this.

P2: VIOLATED — a second declare overwrites the pending snapshot under concurrency. Six concurrent `node .hb/hb.js regate GATE_A rN` produced up to 3 `gate_regated` events, and the final dag kept only the last writer (e.g. actor a2). The pending check runs before the lock (hb.js ~1262 vs `withWlock` ~1272), and python takes no lock.

### P3
- Idle ticks: both ticks returned `False regate_pending_waiting` with `"gate":"GATE_X"` from the gate_pending and review_pending states, and the executors exited with the backend never dispatched.
- Mid-review race, run by me for node and py with refuted true and false: `HB-EXEC STOP` appeared, there were 0 review events and no hang or crash.
- Node unwrapped variant: I replaced the wrap with a bare `hb('review',…)` call. The executor died with an unhandled throw and a Node stack trace, so the wrap is load-bearing. The selftest m6 deletes the call entirely rather than unwrapping it, and only asserts that the HB-EXEC STOP line is absent, which a crash or idle exit also satisfies.
- Selftest coverage: m1 to m8 do not strip hb-exec.js:439 (the exit-3 escalation). The shim therefore does not prove delivery to the escalation branch (see the mutation table).
- Runtime behaviour matches the violated-if clauses: no loop, no crash, no review event, identical sleep reasons, no unconditional wake.

P3: VIOLATED — the proof gap named in the constraint is reproduced: "the selftest strips each executor guard" and "the gate-path signal delivers exit 3 to each executor's escalation branch" are not backed. Deleting hb-exec.js line 439 in a copy leaves the full regate-fail-closed.sh green (REGATE-FAIL-CLOSED-OK), because the shim check greps gate.sh's own inherited refusal text. Runtime behaviour itself held: bounded exits, no crash, zero review events in all four race runs.

### P4
- Sixteen malformed variants of the record each produced a non-empty "regate…" error, identical on both lints: string/list/true/`{}` record, `pending` as `'yes'` or `[]`, missing or non-list `prev_criteria`, empty reason or actor, non-string `at`.
- Well-formed and `pending:false` records lint clean on both.
- Lint gaps, neither a divergence: `actor:"unknown"` and `prev_criteria:[1,2]` are accepted.
- Parity wiring has teeth. Changing python's tick string to `regate_pending_wait` made `parity.sh` print `✗ regate:tick`. The cross-declare case declares from each runtime and checks the exit-3 signal, the marker and the ticks.

P4: NOT-REPRODUCED — malformed records give identical, non-empty errors on both lints, and a one-character divergence in python's sleep reason turns parity red.

### G1
- Marker presence: every listed site carries the marker.
- **gate.sh strip is not clean.** Running `sed -i '/regate-guard/d'` on a copy of gate.sh leaves a dangling `fi` from the `if [ -n "$REGATED" ]` block (the `if` and its body carry the marker, the `fi` does not).
  - `bash -n` on the stripped template reports `syntax error near unexpected token 'fi'` at line 287, rc=2.
  - In a fixture, the stripped `.hb/gate.sh GATE_A` on a pending gate printed `.hb/gate.sh: line 273: PLANNED: unbound variable` and exited 1. The gate was never evaluated (executed.flag absent) and it was not exit 3.
- Selftest m1 only asserts `rc != 3`, so a parse or unbound-variable crash satisfies it. It reddens "via an unrelated parse/runtime error", not via a guard bypass.
- A surgical strip of lines 313-314 does re-open the guard (exit=0), so the guard is real. It is the selftest strip of gate.sh that is not clean.
- The other nine files compile after the same strip (`node --check` / `bash -n` / `py_compile` rc=0).

G1: VIOLATED — `sed '/regate-guard/d'` on gate.sh leaves a dangling `fi` (`bash -n` rc=2, runtime "PLANNED: unbound variable" rc=1). The selftest m1 passes on that crash because it only asserts `rc != 3`, not on the guard being re-opened.

### G2
- Exit codes on non-regate fixtures: no argument 2, unknown gate 2, `--check` on an unknown gate 2, bad flag 2, failing criterion 1, `--check` on a blocked gate 1, `--all` 0, a criterion that itself runs `exit 3` gives gate.sh exit 1, invalid dag.json 2, `PY gate NOPE` 1, `PY gate` on a blocked gate 1. Only the pending-regate refusal exits 3.
- A plain blocked gate (no regate) made both executors print `gate_blocked`, not `regate_pending`.

G2: NOT-REPRODUCED — exit 3 appeared only for the pending refusal. All of the cases above exited 1 or 2 without a regate, and plain blocked executors printed gate_blocked.

### G3
- Realistic shapes held. Floats (1.5), non-ASCII text, nested objects, `1e22`, key order and null/true values round-tripped for a node declare and a python declare. Editing the criteria afterwards and then running park/unpark and start/done through both CLIs left `prev_criteria` unchanged.
- **Node declare is not byte-faithful for exotic numbers.** I put `"big":12345678901234567890`, `"neg0":-0.0` and `"timeout":1.0` in a criterion and ran a node declare.
  - `prev_criteria` came back with `big` as 12345678901234567000, `neg0` as 0, and `timeout` as `1` (int).
  - The live criteria were mangled the same way, so the declare silently rewrote the gate's criteria.
  - This is the `JSON.parse` + indent-2 re-serialization limit. A python declare followed by any node dag rewrite (e.g. `hb.js park`) also changed the snapshot.
- Severity is low, since realistic criteria do not carry such numbers.

G3: VIOLATED (low severity) — the node declare is not a faithful copy of exotic numerics. With `big=12345678901234567890`, `neg0=-0.0` and `timeout=1.0` in a criterion, a node declare gave `prev_criteria` big=12345678901234567000, neg0=0 and timeout=1 (int), and rewrote the live criterion identically. Ordinary values were faithful on both runtimes.

### G4
- Refused declares are clean: nonzero exit, dag md5 unchanged, no `gate_regated`, and a message naming the specific cause (HB_ACTOR, the reason, the id, or the pending declare's actor and reason).
- The gate.sh exit-3 line and the python `gate`/`diagnose` surfaces name the gate and `regate GATE --rearm --artifact <findings-file>`.
- Tick sleep JSON carries `"gate":"GATE_A"` / `"GATE_B"` for the pending gate, in both ticks and both states.
- **Missing the concrete rearm recovery:**
  - Node and python `review` refusals say only "…the gate is being revised (regate pending, by al: why) — rearm first; a fresh pass of the revised criteria is owed before any verdict." There is no `regate <gate> --rearm --artifact` command and no mention of a DIFFERENT actor.
  - The same holds for the node and python constraints refusals ("— rearm first; constraints are authored against…").
  - Race outputs run by me:
    - node, refuted=true: `HB-EXEC STOP: review_error — GATE_R: could not record the refusal (review fail refused … rearm first; …)`
    - node, refuted=false: `HB-EXEC STOP: review_error — GATE_R: review pass rejected by validation: review pass refused … rearm first; …`
    - py, refuted=false: `HB-EXEC STOP: review_error — … rearm first; …`
  - Only the py refuted=true path (refuse-guard) prints `(hb regate GATE_R --rearm --artifact <findings-file>)` with "a DIFFERENT actor rearms". The other race escalations are labelled `review_error`, not `regate_pending`, and carry no `--rearm` path.

G4: VIOLATED — the review and constraints refusals on both runtimes, and the node race escalations (both verdicts) plus the python refuted=false escalation, name the gate but not `regate <gate> --rearm --artifact <findings-file>` or a DIFFERENT actor. Example: `HB-EXEC STOP: review_error — GATE_R: could not record the refusal (review fail refused on GATE_R: … rearm first; …)`.

## Other observations (not constraint violations)
- With a gate blocked and then regated, the tick wakes `gate_blocked` rather than `regate_pending_waiting`. It is bounded by the existing `gate_blocked_waiting_human` breaker and the executors stop. The advice text ("re-run gate.sh") leads to an exit-3 refusal.
- `doctor` reports "healthy" while a regate is pending.
- The shell suite does not cover the node constraints guard at all, and the python `--all` check asserts only a nonzero exit, so a crash would satisfy it.

## Verdict
Not clean. The perimeter works for properly declared records. The proof is not: the node constraints guard is untested, the exit-3 escalation guard is unproven, and the selftest strip of gate.sh passes on a parse crash.

On the constraints: P2, P3, G1, G3 and G4 are VIOLATED; P1, P4 and G2 are NOT-REPRODUCED.

**REFUTED** (and the harness verdict for the advertised criteria is UNSOUND)
