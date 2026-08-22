# GATE_RB — adversarial refutation attempt

**Phase RB — "Robustness & cross-runtime parity."** Actor: adversarial reviewer (distinct from author).
Claim under test: three robustness/parity fixes are done and each is backed by a proof that has teeth.

All work was done in a **stripped environment** (`unset PYTHONPATH HB_NO_GIT HB_NO_HOOK`) with the
editable `hb`/`~/.local/bin` kept off the clean PATH where the tests demand it, so no editable
install or leaked env could mask a failure. Mutation-teeth were exercised on a **temp copy** of the
subtree (`py/`, `plugin/`, `docs/`); the real working tree was verified untouched afterward.

## Fixes examined
- **Event-log safety** — `py/src/heartbeat/scaffold.py`: `events.jsonl` and `executor.json` now written
  only `if force or not <path>.exists()` (dag.json already was). Proof: `init-preserves-log.sh` (T120).
- **Gate shell parity** — `py/src/heartbeat/gate.py` `_run_cmd`: criteria run under
  `[shutil.which("bash") or "/bin/sh", "-c", cmd]` (was `shell=True` → dash) with
  `stdout=PIPE, stderr=STDOUT` (was DEVNULL); `eval_gate` appends a failing criterion's output.
  Proof: `gate-shell-parity.sh` (T121).
- **Pre-push hook honesty** — `_PRE_PUSH_HOOK` skips (exit 0, visible message) when `hb` is absent
  instead of falling back to `python3 -m heartbeat.cli` (which import-errors → false block).
  Proofs: `pre-push-selfcontained.sh` (T122) + updated `pre-push-hook-parity.sh` (T118).

## 1. Teeth — do the proofs go RED when the fix is reverted? (mutations on a temp copy)

| Mutation (temp copy) | Proof | Result |
|---|---|---|
| (a) `events.jsonl` guard → unconditional `log.write_text(...)` | init-preserves-log.sh | **RED** — "re-init WITHOUT --force wiped the event log" |
| (b1) `_run_cmd` → `shell=True` (dash) | gate-shell-parity.sh | **RED** — "python gate blocked a `[[ ]]` criterion node accepts" |
| (b2) `_run_cmd` output → `DEVNULL`, return `""` | gate-shell-parity.sh | **RED** — "python gate swallowed the failing criterion's output" |
| (c) py hook → `HB="hb"; command -v hb \|\| HB="python3 -m heartbeat.cli"` fallback | pre-push-selfcontained.sh | **RED** — "hook blocked (rc=1) when hb is absent — must skip" |

Every mutation flips its proof RED. Notes:
- `/bin/sh -> dash` on this host (`ls -l /bin/sh` confirmed), so mutation (b1) is a genuine dash-vs-bash
  divergence, not a no-op — the `[[ ]]` teeth are real.
- (c): under the reverted fallback, the mutated hook runs `python3 -m heartbeat.cli gate` with a system
  python3 that cannot import `heartbeat`; the import error yields a non-zero exit, which the hook reads
  as "a gate no longer verifies" and blocks the push (exit 1). That is exactly the false-green class the
  fix removes: a *missing tool* masquerading as a *failed gate*. T122 catches it; the shipped hook exits
  0 with "hb not on PATH — skipping…".
- T118 stayed GREEN under mutation (c) — **by design**, not a gap: T118 guards the python leg behind
  `command -v hb` and delegates honest-skip to T122 (documented in the proof header and lines 42-46).
  The honesty teeth live in T122, which does bite.

## 2. Event-log safety end to end (stripped env)
`hb init` → append `E2E-SENTINEL` to `events.jsonl` + mutate `executor.json` → `hb init` (no --force):
- sentinel **preserved** (YES), executor.json **preserved** (YES).
- `hb init --force`: sentinel **RESET**, executor.json **RESET** to default.

Both derived-but-authoritative files are preserved on plain re-init and correctly reset by --force.

## 3. Gate shell parity is real (stripped env)
- `[[ 1 = 1 ]]`: node `gate.sh --check` → PASS **and** python `hb gate --check` → PASS (identical verdict).
- A failing criterion (`echo SURFACED-DIAG; false`): `SURFACED-DIAG` reaches `hb gate` output (not swallowed).
- Passing-gate output stays quiet (noisy passing criterion's stdout is *not* spuriously appended — the
  `if not ok and out.strip()` guard). No behavior change for passing gates.
- Bash-absent fallback is **documented** in gate.py (comment: "Fall back to sh only if bash is genuinely
  absent (documented divergence)").

## 4. Pre-push honesty — the false-green that started this (clean PATH, system python3)
Setup verified: `hb` absent from `PATH=/usr/bin:/bin`; system python3 cannot `import heartbeat`.
- **PY hook, hb absent:** exit **0**, message "HeartBeat gate guard: hb not on PATH — skipping…" (not an import-error block).
- **NODE hook, clean PATH, failing seed gate:** exit **1** (blocks) — genuinely self-contained (`gate.sh --all`).
- **T118 no longer relies on PYTHONPATH to compute the expected exit:** the parity oracle (`ge` in
  `check_runtime`) is computed via `hb gate --all` — the *same* invocation the hook uses (line 43), not
  PYTHONPATH. The only PYTHONPATH uses are init setup (line 41) and a separate force-a-failing-gate step
  (line 57) that is not compared against the hook's exit. The prior false-green (expected exit computed
  WITH PYTHONPATH while the hook ran without it) is gone.

## 5. No regressions / suites (stripped env)
- Node: `HB_NO_GIT=1 bash tests/run-tests.sh` → **340 passed, 0 failed**; T118–T122 all in GROUPS-PASSED.
  (Proofs unset HB_NO_GIT internally as required; verified they still pass with it exported by the suite.)
- Python: `cd py && PYTHONPATH=src python3 -m pytest -q` → **96 passed**.
- Parity: `bash tests/parity.sh` → **PARITY OK — node ≡ python**.
- The gate.py change did not break existing gate behavior: seed `true` gate still passes, passing gates
  stay quiet, failing output surfaces only on failure.

## Tree left clean
`git status --short` after all work shows only the three pre-existing uncommitted fixes
(`gate.py`, `scaffold.py`, `pre-push-hook-parity.sh`, plus `tests/run-tests.sh` registrations) and the
three new proof scripts — i.e., exactly the RB change set. My mutations were confined to a temp copy,
now deleted; no mutation touched the real tree.

## Conclusion
Could not find a hole. All four proofs have real teeth (each reverted fix flips its proof RED, on a host
where the dash-vs-bash divergence genuinely reproduces). Event-log safety, gate shell parity, and
pre-push honesty all hold end-to-end in a stripped environment. All three suites are green with no
regression, and T118's PYTHONPATH false-green is genuinely closed.

VERDICT: COULD NOT REFUTE
