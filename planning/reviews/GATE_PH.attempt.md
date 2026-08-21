# Refutation attempt — Phase PH: "Blocking pre-push hook — a bootstrap feature, both runtimes"

**Actor:** adversarial reviewer (distinct from the implementer).
**Claim under test:** both bootstraps (node `plugin/bootstrap.sh`, python `py/src/heartbeat/scaffold.py::_git_init`) install a non-destructive `.git/hooks/pre-push` that re-verifies every gate and BLOCKS the push on any failing gate; skippable via `HB_NO_HOOK` / `git push --no-verify`; installs on fresh AND existing repos; behavioral node≡python parity. Proofs T117 (`pre-push-hook.sh` → PRE-PUSH-HOOK-OK) + T118 (`pre-push-hook-parity.sh` → PRE-PUSH-PARITY-OK).

Method: read both install sites, ran the proofs, then **mutated hook bodies in mktemp copies of the repo** to check the proofs have teeth, and independently bootstrapped throwaway node/python projects to observe end-to-end behavior. No mutation touched the real tree (all in `mktemp -d`).

## 1. Teeth — the decisive test (PASS: proofs bite)

Mutated a temp copy of `bootstrap.sh` so the emitted pre-push hook body is unconditional `exit 0` (non-blocking), ran T117:
```
MUTATED node hook -> always exit 0
FAIL: hook did NOT block when gate.sh --all failed   (exit 1)
```
Mutated the emitted node hook to drop the `HB_NO_HOOK` bypass line, ran T117:
```
FAIL: HB_NO_HOOK=1 did not bypass the hook           (exit 1)
```
T117 goes RED for a non-blocking hook and for a hook that ignores `HB_NO_HOOK`. **T117 has teeth.**

T118 (parity) — mutated the NODE hook to `exit 0`:
```
FAIL: .../node: gate re-verify fails (ge=1) but the hook allowed the push (he=0)  (exit 1)
```
T118 bites on the node side.

## 2. Real behavior, end to end (PASS)

Fresh node project (`bootstrap.sh`, `HB_NO_GIT`/`HB_NO_HOOK` unset): hook installed, executable. With the **real** seed gate (template `GATE_P1` fails a fresh `gate.sh --all`, ge=1): hook exits 1 and prints "✗ HeartBeat gate guard: push blocked". `HB_NO_HOOK=1` → exit 0. Pre-seeded pre-push (SENTINEL) survives re-bootstrap. Existing repo (`git init` then bootstrap) → hook installs.

Python project (`hb init`): hook installed. Seed gate is `true` (passes) → hook allows (he=0) — correct. To exercise the **block** path I broke the gate (`criteria[0].cmd="false"`): `gate --all` → ge=1, hook → he=1 (blocks), `HB_NO_HOOK=1` → he=0. Python non-clobber, existing-repo install, and idempotent re-init (hook md5 unchanged) all confirmed independently.

## 3. pre-push, not pre-commit (PASS)

Grep for any auto-push across `plugin/` and `py/src/` returns nothing — HeartBeat never pushes, so the hook only fires on a human `git push`. Auto-commit paths (`hb.js`, `gate.sh`/`gate.py`, `hb-exec.js`/`executor.py`, both bootstrap init commits) all use `--no-verify`, so they never trip the pre-commit rot hook. `pre-push` and `pre-commit` are separate files — no collision with the node-only rot pre-commit hook or with `HB_GIT_AUTOCOMMIT`.

## 4. Parity is behavioral & honest — with one caveat (see below)

`pre-push-hook-parity.sh` bootstraps a node project AND a python `hb init` project and asserts (via `check_runtime`) the hook's exit **matches** the real gate-reverify's exit — exit-match, not byte-equality — plus an `HB_NO_HOOK` bypass check. Runtime-specific bodies (node `gate.sh --all`, python `hb gate --all`) are correctly handled. `parity-notes.md` (lines 69–75) honestly records: behavioral (not byte) parity, the runtime-specific body, the differing seed outcome, and that the rot **pre-commit** hook is node-only (pre-existing divergence).

**Caveat (weakness, not a refutation): T118's python branch is not fully load-bearing.** Because the python seed gate is `true` (always passes, ge=0), `check_runtime` only ever exercises the *allow* direction on python. I confirmed this: mutating the python hook to always `exit 0` → **T118 still passes GREEN**; mutating the python hook to ignore `HB_NO_HOOK` → **T118 still passes GREEN**. So T118 does not, by itself, prove the *python* hook blocks-on-failure or honors HB_NO_HOOK — the node side alone carries the "blocks iff fails" teeth. I verified the python *feature* is nonetheless correct by hand (§2: broke the gate → he=1; HB_NO_HOOK → he=0). This is a proof-coverage gap on the python leg, and parity-notes frames the `true`-seed fact as merely "why parity is behavioral" without flagging that it neuters the python teeth. Worth tightening (e.g., the parity proof could stub/break a python gate to force ge=1), but it does not make the claim false: both hooks are installed and both behave correctly.

## 5. Non-clobber & idempotence (PASS)

Both sites guard `if [ ! -e "$PPHOOK" ]` (node, bootstrap.sh:150) / `if not hook.exists()` (python, scaffold.py:85) — install only when absent. In BOTH runtimes the install is **outside** the fresh-init-only path: node's block (bootstrap.sh:147–166) has its own `rev-parse --is-inside-work-tree` guard that fires for fresh OR existing repos; python's `_git_init` was refactored so the `if not already:` block only does init+commit, and the hook install runs unconditionally after it (scaffold.py:83–88). Re-running does not duplicate or clobber (confirmed: python re-init hook md5 unchanged; SENTINEL survives on both runtimes).

## 6. Suites (ALL GREEN)

- `HB_NO_GIT=1 bash tests/run-tests.sh` → **336 passed, 0 failed**; T117 and T118 present in GROUPS-PASSED.
- `cd py && PYTHONPATH=src python3 -m pytest -q` → **96 passed**.
- `bash tests/parity.sh` → **PARITY OK — node ≡ python**.
- `node plugin/templates/hb-audit.js planning/self-audit.dag.json` → 0 warnings (behavioral).
- `prose-check.sh docs/howto/block-pushes-on-failing-gates.md` → PROSE-OK. How-to is listed in `docs/howto/howto-list.md` (line 44, tagged T117/T118) and honestly explains why pre-push (auto-commit fires on every gate pass; push is the escape boundary) and the opt-outs (`git push --no-verify`, `HB_NO_HOOK=1`, `HB_NO_GIT=1`).

## Verdict rationale

Every load-bearing claim survives adversarial testing: both bootstraps install a non-destructive, blocking, HB_NO_HOOK/`--no-verify`-skippable pre-push hook on fresh and existing repos; the node side's block/allow/bypass teeth are proven by mutation; the python hook's block/allow/bypass behavior is confirmed end-to-end by hand; no auto-push exists; hooks don't collide; suites, parity, audit, and prose all green; parity + rot divergence honestly recorded. The one real weakness — T118's python leg never exercises the block/HB_NO_HOOK directions (masked by the `true` seed gate), so a hollow python hook would pass T118 — is a **proof-coverage gap worth fixing**, but the underlying phase behavior is present and correct, so it does not refute the claim.

**Files:** `plugin/bootstrap.sh` (147–166), `py/src/heartbeat/scaffold.py` (29–44, 65–90), `docs/howto/gate-examples/pre-push-hook.sh`, `docs/howto/gate-examples/pre-push-hook-parity.sh`, `docs/howto/block-pushes-on-failing-gates.md`, `planning/parity-notes.md` (69–75), `docs/howto/howto-list.md` (44).

VERDICT: COULD NOT REFUTE
