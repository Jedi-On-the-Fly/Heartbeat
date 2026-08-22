# Refutation attempt — phase RV ("Review integrity")

Refuter: adversarial reviewer (HB_ACTOR distinct from the doer). Stripped env: `unset PYTHONPATH`;
confirmed `claude` was ON PATH in this environment, so I took care that neither the editable `hb`
install nor an on-PATH `claude` masked a failure (the proof builds its own claude-free bin for the
node degrade case, so it does not depend on claude being absent — a prior false-green trap avoided).

Phase anchor: RV — "a degraded refuter can never become a review pass (routes to review_error), a
genuine review isn't discarded, and the verdict parse is robust — both runtimes." Fix lives in
`py/src/heartbeat/backends/*.py` (sentinel `{"error":…}` on degrade/except), `py/src/heartbeat/executor.py:329`
(non-bool `refuted` → review_error), `plugin/templates/executors/claude-exec.sh` (degrade sentinel +
final-token verdict + real findings on CLEAR), and the proof `docs/howto/gate-examples/refute-integrity.sh`
(T119). Tests: `py/tests/test_backends_frameworks.py`.

## 1. Teeth on the proof (mutation testing, on temp copies; real tree untouched)

Baseline: `refute-integrity.sh` → `REFUTE-INTEGRITY-OK`, exit 0 (GREEN).

Copied the full tree to a temp dir and reverted each fix in isolation, re-running the proof:

- (a) `agno.py` refute degrade → `{"refuted": False, "findings": "agno unavailable …"}`
  → RED: `agno: fail-open (refuted=False on degrade)` / `FAIL: py: a framework backend fails open on degrade`.
- (b) `claude-exec.sh` degrade → `{"refuted":false,"findings":"…could not run the refuter"}`
  → RED: `FAIL: node: claude-exec.sh fails open on degrade (bool refuted:false when claude absent)`.
- (c) `claude-exec.sh` CLEAR path → canned `{"refuted":false,"findings":"reviewer could not refute"}`
  → RED: `FAIL: node: CLEAR findings too short (25) — the reviewer's real text was discarded (dead-end)`.
- (d) `claude-exec.sh` verdict → `grep -q 'REFUTED'` (grep-anywhere)
  → RED: `FAIL: node: verdict parse fooled by the word REFUTED in prose (scored a CLEAR as a refutation)`.

All four mutations flip the proof RED with the correct, specific message. The proof has teeth.

## 2. The actual fail-open is closed end to end

Python (`executor.py` review path), two independent constructions of a review-gated project:
- Refuter = ABSENT framework backend (`HB_REFUTE_BACKEND=smolagents`; verified absent in this env).
  Driver STOPS at `review_error`; NO `review_passed` event; NO `GP0` git tag (git repo initialized so a
  tag *could* have been created — it was not).
- Refuter = script stub emitting `{"error":"… unavailable …"}` (via `HB_REFUTE_CMD`). Same result:
  `review_error`, no `review_passed`.

Node (`hb-exec.js` review path): real `plugin/templates/executors/claude-exec.sh` as the refuter, run
under a claude-free PATH (wrapper strips claude, driver keeps a full PATH so tick.sh has `date` etc.).
Refuter emits the `{"error":…}` sentinel → `hb-exec.js:352` `typeof refuted !== 'boolean'` →
`HB-EXEC STOP: review_error — GR0: backend returned no verdict`; NO `review_passed`; NO `GR0` tag.

The routing on both sides (py `executor.py:329`, node `hb-exec.js:352`) treats a non-bool `refuted` as
"could not run" → escalate, never fail open. Confirmed all py backends (agno, autogen, claude, codex,
crewai, langgraph, ollama, openai_agents, opencode, pydanticai, smolagents) return `{"error":…}` on
BOTH the import-degrade and runtime-exception paths — grep for a surviving fail-open bool returned NONE.

## 3. No new fail-CLOSED regression

- Node genuine CLEAR: claude stub emitting a substantive (≥40-char) CLEAR reply → driver completes,
  `review_passed` emitted, phase R0 completed, `GR0` tag created, and the persisted
  `reviews/GR0.attempt.md` carries the reviewer's ACTUAL text (not the old canned string). The ≥40 guard
  is cleared by real findings.
- Python genuine CLEAR (`refuted:false` + ≥40 findings via cmd stub) → rc 0, `review_passed`, phase done.
- Python `refuted:true` → `review_failed`, no `review_passed`, rc 1.

Both runtimes preserve the genuine-pass and genuine-fail behavior.

## 4. Tests re-assert safety, not deleted

`git diff py/tests/test_backends_frameworks.py`: five degrade assertions were CHANGED (not removed) from
`r.get("refuted") is False` to `not isinstance(r.get("refuted"), bool)` (+ `"error" in r or "findings" in r`),
i.e. they now assert the sentinel and would fail if a backend fell back to a fail-open bool. No test was
deleted; the test count did not drop. This is a tightening, not a weakening.

## 5. Suites (stripped env)

- `unset PYTHONPATH; HB_NO_GIT=1 bash tests/run-tests.sh` → RESULT: 337 passed, 0 failed; T119 present in
  GROUPS-PASSED (T119.1 → REFUTE-INTEGRITY-OK).
- `cd py && PYTHONPATH=src python3 -m pytest -q` → 96 passed. (PYTHONPATH is needed for pytest import
  only; the backend/executor behavior was independently exercised above without it masking anything.)
- `bash tests/parity.sh` → PARITY OK — node ≡ python.

Tree left clean: all mutations were done on temp copies; `git status --short` shows only the fix's own
pre-existing uncommitted changes; no stray temp test files remain.

## Conclusion

Every claim of phase RV holds under adversarial checking: the proof has teeth (4/4 mutations go RED),
the fail-open is closed end to end in both runtimes (review_error, no pass, no tag with an absent/errored
refuter), no fail-CLOSED regression (genuine CLEAR still passes, refuted:true still fails), the tests
were tightened rather than deleted, and all three suites are green in a stripped environment. I could not
find a hole.

VERDICT: COULD NOT REFUTE
