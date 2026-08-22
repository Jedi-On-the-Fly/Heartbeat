# GATE_HN — refutation attempt (phase HN "Honesty & coverage")

Actor: adversarial reviewer (HB_ACTOR distinct from the implementer).
Env: all teeth-mutations done on the real tree but restored immediately (or on `/tmp` backups); final `git status` verified clean — only the shipped HN changes remain (`tests/run-tests.sh`, `docs/dev-tests.md`, `planning/parity-notes.md` modified; three new `docs/howto/gate-examples/*.sh` proofs). Suites run with `HB_NO_GIT=1`.

Phase HN claims three honesty/coverage fixes, each proof-gated in the node suite:
- H1 — coverage floor: `_coverage_check` marks a mostly-skipped run INCOMPLETE (exit 3) → T135 `coverage-floor.sh`
- H2 — every `planning/*.dag.json` lint-clean + 0-hollow → T136 `example-dags-gated.sh`
- H3/H4 — audit-fixture count in docs derived from `parity.sh` (4→5 corrected) → T137 `doc-fixture-count.sh`

## What holds (confirmed with teeth, not rubber-stamped)

**H1 proof has teeth.** Mutated `_coverage_check` in run-tests.sh to `return 0` (no-op) → `coverage-floor.sh` went RED with the exact intended message ("a mostly-skipped run was NOT flagged incomplete (ALL-GREEN can still lie)"), exit 1. Restored → COVERAGE-FLOOR-OK. The proof sources the real helper from run-tests.sh via `eval "$(grep ...)"` and asserts both directions (low-skip 100/2 → rc 0; high-skip 30/40 → nonzero + loud message) plus that run-tests actually WIRES it (`GROUPS-SKIPPED` emitted, `_coverage_check`/`COVER` referenced). It does not grep its own success token — not self-satisfying. The INCOMPLETE/exit-3 branch is reachable: with `FAIL=0` and `COVER_INCOMPLETE=1` the exit path prints INCOMPLETE and returns 3.

**Full env reads ALL GREEN, no false incomplete.** `HB_NO_GIT=1 bash tests/run-tests.sh` → 355 passed / 0 failed, `GROUPS-RAN: 137  GROUPS-SKIPPED: 0` (0 < floor 20), `✅ ALL GREEN`, exit 0. T135/T136/T137 all present in `GROUPS-PASSED`. Adding `_GCHECKS` to `ok`/`ko` did not break the GROUPS-PASSED marker or any group.

**The "ALL GREEN can lie" scenario is killed.** On a genuinely python-absent box (PATH rebuilt with every tool symlinked except python*/python3*), the suite reports `GROUPS-SKIPPED: 61` and prints `⚠ COVERAGE-INCOMPLETE: 61 groups skipped (> floor 20)`. Critically, the run does **not** read "✅ ALL GREEN" — this is the core claim of the phase and it holds.

**H2 has teeth and correct scope.** Dropped a hollow DAG (`gate cmd:"true"`) into `planning/` → `example-dags-gated.sh` went RED naming the file; removed → green, reporting `EXAMPLE-DAGS-GATED-OK (54 DAGs)` — it covers ALL 54, not a subset. It correctly does NOT scan the deliberately-hollow audit-fixtures: those live in `planning/audit-fixtures/*.json` (subdir, and `.json` not `.dag.json`), so the `planning/*.dag.json` glob never matches them (verified: `hb-audit` flags `hollow.json` as hollow, yet the glob yields 0 matches under `audit-fixtures/`).

**H3/H4 count is derived, not hardcoded.** Mutated `parity-notes.md` line 22 to "4 fixtures" → RED ("does not state 5 audit fixtures"); restored → green. Added a 6th entry (`extra_new`) to `parity.sh`'s `for f in hollow existence nondeterministic good side-effect` loop → the proof then derived `n=6` and demanded the docs say 6 (RED: "does not state 6 audit fixtures"); restored → `DOC-FIXTURE-COUNT-OK (n=5)`. The number is genuinely pulled from parity.sh's loop. The 5 fixtures exist and match: hollow, existence, nondeterministic, good, side-effect.

**No regression.** Node 355/0 ALL GREEN; Python `pytest` 96 passed; `parity.sh` PARITY OK (node ≡ python). Tree left clean.

## Gaps found (not sufficient to refute)

1. **H1 mechanism is masked on a real stripped box (partial).** The phase frames H1 as: a stripped run ends INCOMPLETE / exit 3. In practice, on a python3-absent box the headline is `❌ FAILURES` (exit 1), *not* `❌ INCOMPLETE` (exit 3) — because 6 gate-example proofs (T101, T112–T115, T129) invoke `python3` internally *without* the suite's `command -v python3` guard, so they `ko` (fail) rather than skip. A failing check still sets `_GCHECKS`, so those groups count as RAN, and the coverage floor's own verdict is overridden by the earlier `FAIL != 0` exit branch. The floor's warning still prints, and the run is still non-green — so the load-bearing honesty property ("ALL GREEN cannot lie") holds — but the specific INCOMPLETE/exit-3 outcome is only observed when those 6 python deps happen to be satisfied. The floor is a real, teeth-y secondary signal, not the primary gate it's framed as. Minor: the guarded python groups (T37+) skip cleanly and *do* feed the floor.

2. **A residual honesty inaccuracy in the very phase about honesty.** The H3/H4 fix corrected the *numeric* "4→5" claims (parity-notes.md ×2, dev-tests.md line 187) but left `docs/dev-tests.md` line 208's enumerated list stale: `planning/audit-fixtures/{hollow,existence,nondeterministic,good}.json` still names only 4 fixtures — `side-effect` is missing. The DOC-FIXTURE-COUNT proof cannot catch this, since its regex only matches numeric "N fixtures" claims, not the brace-enumeration. So a doc still under-states the fixture set, and the phase's own gate is blind to it.

## Conclusion

Every teeth-mutation behaved as the phase intends: H1's no-op helper turns the proof red, the full env stays ALL GREEN with no false incomplete, a stripped box does not read green, H2 catches an injected hollow DAG across all 54 example DAGs while correctly excluding the hollow audit-fixtures, and the doc fixture count is genuinely derived from parity.sh (RED at "4", RED when a 6th is added). All three suites are green and the tree is clean.

The two gaps are real but do not falsify the phase's core claim (a stripped/incomplete run cannot silently read "✅ ALL GREEN"): gap 1 is a framing/mechanism mismatch where the run is still non-green via a different exit branch, and gap 2 is a one-word stale enumeration the numeric proof was never designed to cover. Neither is a hole that lets a dishonest green through. I could not refute the phase.

VERDICT: COULD NOT REFUTE
