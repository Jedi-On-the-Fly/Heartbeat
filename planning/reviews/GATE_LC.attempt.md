# GATE_LC — checkpoint lifecycle: tag only on reviewed acceptance

**Distinct actor:** reviewer agent. **Verdict: SOUND.**

- Core behavior (own throwaway projects, git enabled), node ≡ python: review-gated gate → det pass =
  review_pending + NO tag; `hb review pass` → tag on the reviewed HEAD; non-review gate → tag at det pass.
- Edge cases: `review fail` → no tag; refute→re-run-gate → still deferred; HB_NO_GIT / HB_GIT_AUTOCOMMIT=0
  honored (no commit/tag); non-git-repo → no crash, no tag.
- No regression: node 321/0 (T24/T26/restore-points + T103 in GROUPS-PASSED), python 91, parity OK.
- Proof teeth: mutating each of the 4 files (gate.sh/gate.py/hb.js/cli.py) turns gate-review-checkpoint.sh
  RED in the correct direction; reverted.
- Invariant: `git reset --hard GATE_x` lands on the reviewed commit (contains .hb/reviews/GATE_x.md).
