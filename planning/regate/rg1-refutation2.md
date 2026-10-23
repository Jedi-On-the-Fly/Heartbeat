# RG1 round 2 refutation

All work was in mktemp fixtures and in copies of the repo made with `tar --exclude=.git --exclude=.hb`. Nothing in the repo tree or its .hb/ was modified.

## Round-1 fixes, re-run
- **Proof and selftest.** `bash tests/regate-fail-closed.sh` printed REGATE-FAIL-CLOSED-OK. `--selftest` printed REGATE-FAIL-CLOSED-SELFTEST-OK.
- **P2 race.**
  - 4 node and 4 python declares (8 racers, mixed runtimes), repeated 6 times: exactly 1 `gate_regated` event each time. The cross-runtime lock holds.
  - Every loser's message names the pending declare ("already has a pending regate (by al1: r1)").
- **Independent strip matrix.**
  - I copied the repo 14 times, deleted one guard from each copy with sed, and ran the whole proof against it.
  - Every copy still parsed (bash -n / node --check / py_compile) and went RED with a check naming the bypass.
  - Guards stripped: hb.js review, hb.js anchor, gate.sh single-gate, gate.sh sweep count, gate.sh parked annotation, gate.py single-gate, gate.py --all lines, review_policy, constraints.py, tick.sh, tick.py, executor refuted-branch, hb-exec exit3, hb-exec review-fail-wrap.
  - Examples of the failure messages:
    - "gate.sh single-gate refusal exit=0 (want 3)"
    - "--all sweep exit 0 over a pending regate"
    - "python --all did not print the counted-FAILING regate line"
    - "a review event landed while the regate was pending"
  - Stripping only line 479 of executor.py (the python gate-path guard, leaving the run_gate call on line 478) turns pytest `gate_path` red for the right reason: "executor swallowed the gate-path refusal".
- **Malformed markers.**
  - Records tried: `[]`, `{}`, `"yes"`, `null`, `false`, `0`, `{pending:"false"}`, `{pending:0}`, `{pending:null}`, `{pending:true}`.
  - Every one gave gate.sh single = 3, gate.sh --check = 3, python hb gate = 3, and no criterion ran (the side-effect flag was never created).
  - The `--all` sweep exited 1 and no gate/review event landed.
  - Only `{pending:false}` clears; that is the rearm state.
  - Node and python review pass/fail/free all refuse, for both a gate id and a phase id. `accept_review` driven directly via python -c refuses all 6 combinations (rc 1).
  - Phase-id bypass: NOT reproduced.
  - `hb diagnose` on either runtime ran no criterion. `hb anchor` refuses. Constraints refuse on both runtimes. Node constraints is guarded after the "no plan-time constraints" check, which is correct.
- **Mid-review race.** I ran my own fixtures: 2 runtimes by 2 verdicts, with the backend declaring the regate itself.
  - No review_passed, review_failed or free_review event landed in any of them. The only review_* line is `review_wake`, written before the declare.
  - Output for the 4 runs:
    - node, refuted=true: `HB-EXEC STOP: review_error — GATE_R: could not record the refusal (review fail refused on GATE_R: … node .hb/hb.js regate GATE_R --rearm --artifact <findings-file>…)`
    - node, refuted=false: `HB-EXEC STOP: review_error — … review pass refused on GATE_R … regate GATE_R --rearm --artifact …`
    - py, refuted=true: `HB-EXEC STOP: regate_pending — GATE_R was revised mid-review … (hb regate GATE_R --rearm --artifact <findings-file>)`
    - py, refuted=false: `HB-EXEC STOP: review_error — … hb regate GATE_R --rearm --artifact …`
  - All four name the gate, a DIFFERENT actor and the exact rearm command. The `review_error` label on three of them is cosmetic; the recovery text is present.
- **Ticks.** Both ticks emit `{"wakeAgent":false,"data":{"reason":"regate_pending_waiting","gate":"GATE_A"}}` from the gate_pending state and from the review_pending state.
- **Lint.** Thirteen records were fed to both lints. Node and python gave identical rc and identical messages on every one.
  - Malformed records are non-empty errors: wrong type, `{}`, empty reason, prev_criteria not a list, `at` not a string.
  - A fully well-formed record lints clean.
  - Side note: `{pending:false}` with no other fields evaluates (the perimeter clears) but lint errors on the missing reason. This is safe and inconsistent in the harmless direction.
- **G2.** Verified on a fixture with no regate: unknown gate = 2, no argument = 2, a criterion that `exit 3`s = 1, a criterion that exits 3 via python = 1, a signal-killed criterion = 1, `--check` = 1 or 2, `--all` = 0 or 1. Exit 3 appears only on the pending refusal. gate.sh has a single `exit 3`, on line 315.

## Defects found

### 1. Node dag writes are not serialised with declare, so a concurrent `hb park` silently erases a declared regate (new fail-open race)
- Where: `plugin/templates/hb.js` `case 'park'`. It does `readDag()` at roughly line 1316 and `writeFileSync(DAG, …)` at roughly line 1328, with no write lock. The lock covers only the later event append.
- The declare takes the lock only against other declares. A park that read the dag before the regate landed then overwrites dag.json without the marker.
- Result: the audit event `gate_regated` exists, the declare printed "now REFUSES evaluation", but `gates.GATE_A.regate` is absent and the gate evaluates. The perimeter is disarmed with no signal.
- Repro, node regate racing `hb.js park B retire` on a two-phase fixture, 40 trials:
  `lost marker with event present: 2/40`.
- Python park vs python regate: 0/40 (not reproduced there).
- It needs a concurrent park, so the window is small. But the claim "check-then-write under ONE write lock" holds only for declare-vs-declare, and the failure is silent and fail-open.
- Fix direction: take `withWlock` around park/unpark's read-modify-write on both runtimes, or re-read inside the lock.

### 2. Gate blocked, then regate: the tick still wakes `gate_blocked` (observation, not a bypass)
- This is the most likely real scenario, because dead premises make the gate fail first.
- `bash .hb/tick.sh` and `hb tick` both return `wakeAgent:true, reason:gate_blocked`, with the action text "re-run gate.sh". That text leads to an exit-3 refusal.
- It is bounded by the existing breaker and the executors stop. It is not a bypass and I do not count it as exploitable.

## Judgement on the two documented residuals

### G3 (exotic numbers)
- Reproduced: node declare turns `big=12345678901234567890` into `12345678901234567000` and `timeout=1.0` into `1`, in both the live criteria and `prev_criteria`.
- Pre-existing: `hb.js park` on the same dag does the same (`"timeout": 1`).
- Judgement: the scoping is honest. The snapshot and the live criteria stay equal to each other, ordinary values are faithful, and the cause is the node JSON writer.
- Two caveats:
  - parity-notes does not yet record it. `grep -in "bigint|exotic|1.0" planning/parity-notes.md` found nothing, and rg3c is still future work.
  - G3's violated-if literally includes "retypes fields", so as written it cannot hold for the node runtime. Either G3 is narrowed to JSON-faithful values or the limit is recorded; I answer VIOLATED, low severity, accepted-as-documented once recorded.

### Spec-first RED evidence
- It cannot be shown from commit order, because heartbeat autocommits only at gate acceptance.
- The strip matrix above, plus the selftest's m1–m11, is real substitute evidence: every guard removal turns a named check red for the right reason. I judge it sufficient.
- Selftest gaps (my own strips covered them and the proof caught each): there is no m-case for the node review guard, the anchor guard or the gate.sh sweep lines.

## Per-id answers
P1: NOT-REPRODUCED — every malformed or pending marker gave gate.sh = 3, --check = 3, python hb gate = 3, --all = 1, no criterion ran, hb diagnose ran nothing, node and python review pass/fail/free (gate id and phase id) and a direct `accept_review` all refused, constraints refused, and no gate_* or review_* verdict event landed.
P2: NOT-REPRODUCED — the declare-vs-declare race held across 6 mixed-runtime trials (exactly 1 event each), with reason, HB_ACTOR, second-declare and phase-id handling as claimed. Side finding: a concurrent node `hb park` erases the marker (Defect 1).
P3: NOT-REPRODUCED — the 4 mid-review race runs, the shim, and both ticks (from both states) matched the claim; the strips of exit3, the wrap, the refuted-branch, the tick guards and the gate-path guard each flipped a named check red for the right reason.
P4: NOT-REPRODUCED — 13 records gave identical non-empty lint errors on both runtimes, a well-formed record linted clean, and the strips of the lint and tick guards flipped the matching checks.
G1: NOT-REPRODUCED — all 14 guard strips left a parsing script and reopened the guarded behaviour; the proof went red naming the bypass, not a crash.
G2: NOT-REPRODUCED — exit 3 is emitted only on line 315; unknown gate, no argument, failing criteria (including ones that exit 3), --check and --all all gave 1 or 2 (or 0 for --all) on non-regated fixtures.
G3: VIOLATED — low severity, dag-wide node JSON limit: with `big=12345678901234567890` and `timeout=1.0`, a node declare gives `prev_criteria` big=12345678901234567000 and timeout=1; `hb.js park` mangles the same dag the same way. The scoping is honest but not yet written into parity-notes.
G4: NOT-REPRODUCED — refused declares leave dag and events untouched with cause-naming messages; every review, constraints, anchor, gate.sh, executor and tick surface names the gate and the `regate <gate> --rearm --artifact <findings-file>` command (plus a DIFFERENT actor where text exists); the sleep JSON carries `gate`.

## Verdict
The round-1 holes are closed and the fixes have teeth. Two things remain: a new reproduced fail-open race (park erasing a declared regate, 2/40) and G3, which is violated as written (accepted as documented once recorded).

**REFUTED** (harness verdict: UNSOUND)
