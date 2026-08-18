# Refutation attempt — Phase RR (Verifiable-reward + model-regression), GATE_RR

Actor: skeptical reviewer (different actor than the implementer).
Target: phase `RR` of `planning/parity-oracle-reward.dag.json` — Python-only reward + regression
analysis tooling (`py/src/heartbeat/bench.py`, `py/src/heartbeat/cli.py`).
Anchor: gate `GATE_RR` (rrc1–rrc6), proof `docs/howto/gate-examples/reward-regression.sh`.

I tried to prove the gate could go green while the real work is broken. It cannot. Findings per claim:

## 1. `reward` is a labeled per-evaluation record tied to the LOG verdict, not a self-report
`reward_records` (bench.py:50) emits one record per `gate_passed`/`gate_failed` event, with
`passed = (e == "gate_passed")`. It reads ONLY the event name; it ignores any backend-supplied
keys. Adversarial log with `gate_failed` carrying `backend_says:"SUCCESS"`, `result:"ok"`,
`exit_code:0` — both the pure fn AND the real CLI (`hb reward --dir … --json`) returned
`passed: false`. Not a count: two gate events → two records with distinct labels. REFUTED-FAIL.

## 2. `phase` is derived from the dag; unknown gate → null, no crash
`phase = st.phase_by_gate_exit(dag, gate)` (state.py:75) scans phases for a matching `gate_exit`
and returns `None` otherwise. The event carries no phase. Tested a gate that is no phase's
gate_exit (`GX`) and an event with a missing `gate` key → both returned `phase: None`, `gate:
None`, no exception. Clean null, not a fabrication. REFUTED-FAIL.

## 3. `regressions` is directional and both constants die
Tested worse / equal / better / missing-baseline: `{w:True, e:False, b:False}`, missing baseline →
`[]` (bench.py:88–90). Also a mixed candidate (more gates but more task_failures) → correctly
`regressed:True` (OR over three axes: fewer gates OR fewer phases OR more failures). A
constant-TRUE impl fails rrc5 (must clear the equal candidate); a constant-FALSE impl fails rrc4
(must flag the worse one). rrc4 + rrc5 together pin both directions — no vacuous answer survives.
REFUTED-FAIL.

## 4. Purity
`reward_records` and `regressions` performed no disk writes (filesystem snapshot unchanged), did
not mutate their inputs (deep-copy compare), and their source contains no `executor` / `open(` /
`write`. `rewards(hbdir)` only reads log+dag then calls the pure core. No backend re-run. REFUTED-FAIL.

## 5. Backward compat of `hb bench --json`
Real runs: `bench --backend x=true --json` (no `--baseline`) → a plain JSON **list** of cards with
`label` (cli.py:253, the backward-compat branch). Adding `--baseline` → a `{scorecards,
regressions}` object only when requested. Old shape preserved. REFUTED-FAIL.

## 6. The proof asserts with teeth — no silent no-op
`bash docs/howto/gate-examples/reward-regression.sh` → `REWARD-REGRESSION-OK`, exit 0. `set -u`;
each embedded `python3 - <<PY` block is guarded with `|| { echo FAIL…; exit 1; }`, so a failing
assert propagates. Mutation-tested IN PLACE (so `BASH_SOURCE/../../..` resolves to the repo root):
- reward count 2→99 → FAIL "reward records wrong", exit 1
- worse `is True`→`is False` → FAIL "regression comparator wrong", exit 1
- phase `P0`→`PZ` → FAIL, exit 1
- G0 `passed is True`→`is False` → FAIL, exit 1
- equal `is False`→`is True` → FAIL, exit 1

Every mutation flips the marker off with a correct label and non-zero exit. (Note: copying the
script to `/tmp` and mutating there produces a misleading "hb reward errored" because ROOT
resolves to `/` and PYTHONPATH breaks — a harness artifact of that method, not a script bug;
in-place mutation is the valid test and it behaves correctly.)

## Gate + suite state
- Full GATE_RR criteria rrc1, rrc2, rrc3, rrc6 run as the gate would: all PASS. rrc4/rrc5 covered
  by the constant-impl analysis above.
- `node plugin/templates/hb-audit.js planning/parity-oracle-reward.dag.json` → "0 warning(s)", no
  hollow gates.
- T76 wired in `tests/run-tests.sh` (T76.1 marker, T76.2 `reward --help`, T76.3 `bench --baseline`).
- `planning/parity-notes.md:71` records the intentional python-only divergence.

Minor, non-blocking observations (not holes in the gate):
- No dedicated `pytest` case for `bench.reward_records`/`regressions`; coverage rides entirely on
  the node-suite proof (T76). Acceptable given the proof has teeth, but a python unit test would be
  belt-and-suspenders.
- `hb bench --baseline` end-to-end is exercised only via `--help`; the regression-verdict JSON
  shape is validated by the pure-fn tests, not an integration run of a real bench. Fine because the
  comparator is pure and independently proven.

VERDICT: COULD NOT REFUTE
