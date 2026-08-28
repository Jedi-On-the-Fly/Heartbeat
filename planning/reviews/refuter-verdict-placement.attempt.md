# Adversarial refutation — `refuter-verdict-placement.sh` (T149)

**Proof under test:** `docs/howto/gate-examples/refuter-verdict-placement.sh`
**Claim:** a refuter panel's `verdict` is read ONLY from the resolved refuter **profile**; a
`verdict` placed on the gate's `review` block is silently inert. Counting refute dispatches through a
stub backend: `verdict{panel:3}` on the profile ⇒ 3 dispatches; the same `verdict` on the gate's
review ⇒ 1 (the single-verdict path). Both runtimes. Prints `REFUTER-VERDICT-PLACEMENT-OK`;
`--selftest` prints `SELFTEST-OK`.

I did not write this proof. I attacked it with real mutations and instrumentation, restoring
everything.

## Baseline
- `bash docs/howto/gate-examples/refuter-verdict-placement.sh` → `REFUTER-VERDICT-PLACEMENT-OK`, exit 0, ~2.6s.
- `--selftest` → `SELFTEST-OK`, exit 0.

## 1. RED-ability (the critical test) — PASS
Mechanism confirmed by reading the code: the executor reads the verdict config from the resolved
profile only —
- node `plugin/templates/hb-exec.js:357` `const verdictCfg = (prof && prof.verdict) || {};`
- py `py/src/heartbeat/executor.py:340` `verdict_cfg = (prof.get("verdict") if prof else None) or {}`

`prof` comes from `gateProfile(HB_DIR, rv)` / `gate_profile(hbdir, rv_block)`, which resolves
`review.profile` (a NAME) → profile JSON. The gate's `review.verdict` is never consulted. So the
proof's claim maps to a real, single code point in each runtime.

Mutation applied (make the executor ALSO honour a gate/review-level verdict):
- node: `... || (rv && rv.verdict) || {};`
- py:   `... or rv_block.get("verdict") or {};`

Results (the plugin file is a template; the proof re-bootstraps a project each call, so the mutated
template is picked up on every fresh `$p/.hb/hb-exec.js`):
- Both mutated → `FAIL: py: ... got 3, want 1`, exit 1 (Python checked first, gate count went 1→3).
- Restored py, kept node mutated → `FAIL: node: ... got 3, want 1`, exit 1.

So the proof goes RED **independently in each runtime** under the exact regression it guards. No
`OK` marker printed in either RED case.

Restore: `cp` from byte backups; md5 of both files matches the pre-mutation originals
(`hb-exec.js 3e483c76…`, `executor.py 03b70cb0…`). Re-run → `REFUTER-VERDICT-PLACEMENT-OK`, exit 0.
`git status` shows the two executor files with an EMPTY diff (fully restored).

## 2. Is the dispatch COUNT real? — PASS
The stub appends one literal `x` line to `$STUB_COUNTER` on every `refute` call and nothing on
`execute`. The proof counts with `grep -c x "$p/counter"`. I reproduced profile mode in isolation and
dumped the counter: three `x$` lines, `count=3`. Not a constant — it is a genuine per-dispatch tally.
Gate mode = 1 in the baseline and jumps to 3 only under the mutation (see §1), confirming the count
tracks real backend invocations in both directions.

## 3. Does `--selftest` have teeth? — PASS
`check_counts` = `[ $1 -gt 1 ] && [ $2 -eq 1 ]`. Exercised directly:
- `(3,1)` accepted (correct reading),
- `(1,1)` rejected (profile-inert: the `>1` clause has teeth),
- `(3,3)` rejected (gate-honoured: the `==1` clause has teeth).

The selftest asserts a correct `(3,1)` is accepted AND that both `(1,1)` and `(3,3)` are rejected.
Dropping the `$1 -gt 1` clause would let `(1,1)` pass → selftest's second assertion fails; dropping
`$2 -eq 1` would let `(3,3)` pass → third assertion fails. Both failure modes are caught.

## 4. Hermetic & deterministic — PASS
- Unsets `HB_DIR DAG_FILE EVENTS_FILE HB_REFUTER` up front. Verified load-bearing: running with all
  four exported to bogus values still yields `REFUTER-VERDICT-PLACEMENT-OK`, exit 0. (The `HB_REFUTER`
  unset matters — a set `HB_REFUTER` would make `gateProfile` return non-null even for the
  profile-less gate DAG and defeat the gate-mode=1 arm; the proof correctly clears it.)
- Cleanup: `trap 'rm -rf "$work"' EXIT` plus per-call `rm -rf "$p"`. After a full run `git status`
  tracked-change count is unchanged (5, all belonging to the proof's own delivery), no stray
  `/tmp/tmp.*` left by this proof.
- Deterministic: no `curl/wget/date/sleep/RANDOM/http` tokens. Two runs 2.64s / 2.62s — stable, well
  under 5s.

## 5. Overclaim? — NO
Header and the T149 dev-tests row both say exactly what is checked: profile-`verdict` drives 3, the
same misplaced on the gate drives 1 (single path), both runtimes, goes RED if a gate-level verdict is
ever honoured, `--selftest` proves the 1-vs-N assertion load-bearing. All four are demonstrated above.
No claim exceeds what the proof exercises.

## 6. Wiring — PASS
- `tests/run-tests.sh:1602-1605`: T149.1 runs the proof and pipes its stdout straight into
  `grep -q "REFUTER-VERDICT-PLACEMENT-OK"` (marker asserted on the same piped command — a crash with
  no marker fails the check). T149.2 runs `--selftest` and greps `SELFTEST-OK`. Guarded by
  `command -v python3` with an explicit skip message.
- `docs/dev-tests.md:168`: exactly one `| T149 |` row (index coverage green).

## Notes
- The `M` files in `git status` (`docs/dev-tests.md`, `docs/howto/howto-list.md`,
  `docs/howto/tune-refuter-sensitivity.md`, `tests/run-tests.sh`) and the untracked proof are the
  new-proof's own delivery, pre-existing before this review. My only mutations were to
  `hb-exec.js` and `executor.py`, both restored byte-for-byte (empty diff).

## Conclusion
The proof is honest and load-bearing: it goes RED in BOTH runtimes under the precise regression it
guards, counts real backend dispatches, has a selftest whose two teeth are each necessary, is
hermetic and deterministic under 5s, is wired to assert its marker, and does not overclaim.

VERDICT: SOUND
