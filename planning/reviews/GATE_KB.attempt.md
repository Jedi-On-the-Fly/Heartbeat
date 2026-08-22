# GATE_KB — refutation attempt (phase KB "Kernel correctness")

Actor: adversarial reviewer (HB_ACTOR distinct from the implementer).
Env: stripped — `env -u PYTHONPATH`, `HB_NO_GIT=1` on suites, `PYTHONHASHSEED=random` on the determinism proof, git shadowed off PATH on the gitless proof. All teeth-mutations were done on `mktemp -d` copies of the tree; the real tree was left clean (verified `git diff --stat` = only the four fixes + four proofs + suite wiring).

Phase KB claims four kernel fixes, each with a runnable proof wired into the node suite:
- C1/KB2 — `extractPaths` precision (hb-lint.js + lint.py) → T126 `rot-lint-precision.sh`
- C3/KB3 — deterministic state projection (state.py `sorted()`) → T127 `state-determinism.sh`
- C4/KB4 — git-optional gate pass (gate.py `shutil.which`) → T128 `gate-gitless.sh`
- C8/KB5 — gate_blocked circuit breaker (tick.sh + tick.py) → T129 `gate-blocked-breaker.sh`

## What holds (confirmed, not rubber-stamped)

**Suites, stripped.** `env -u PYTHONPATH HB_NO_GIT=1 bash tests/run-tests.sh` → **347 passed, 0 failed**, `GROUPS-PASSED` lists T126 T127 T128 T129 (and T6/T7/T8, T11/T21, T27/T30, T31/T26, T32, T43/T82/T83). pytest → **96 passed**. `tests/parity.sh` → PARITY OK. `hb-audit` of `planning/critical-fixes-2.dag.json` → 0 warnings.

**Teeth — each fix is load-bearing (revert on a temp copy → proof RED):**
- C1: removed the abspath + extension guards → `rot-lint-precision.sh` FAILS ("sed pattern treated as a path; absolute path treated as a produced artifact").
- C3: `sorted()` → `list(set())` → `state-determinism.sh` FAILS (byte-differing state.json across two `PYTHONHASHSEED=random` rebuilds — real cross-process nondeterminism).
- C4: removed `shutil.which('git')` guard → `gate-gitless.sh` FAILS with the exact `FileNotFoundError: 'git'` at gate.py line 80 (the rev-parse commit site). Proof strips *only* git (python still runs); fixed code records `commit=None` (JSON null), not a crash.
- C8: removed the breaker → `gate-blocked-breaker.sh` FAILS ("gate_blocked re-woke 9/9 ticks with no terminal signal").

**Breaker correctness.** Counter (`.gate-blocked-ticks`) grows 1..N while blocked, is `rm`'d when the gate clears (both runtimes) so a later block starts fresh. Terminal reason is `gate_blocked_waiting_human` via `sleep_out`/`_sleep` → **`wakeAgent:false`** (genuinely stops waking, not a relabel). tick.sh and tick.py both flip to the terminal at the *same* bound (tick 5 with `GATE_BLOCKED_MAX=5`), wake=false thereafter — parity holds, T82/T83 green. `.gate-blocked-ticks` is gitignored in **both** bootstrap.sh and scaffold.py. `gate_blocked_waiting_human` is absent from PROTOCOL in both runtimes — consistent with every other `*_waiting*` sleep reason (only wake reasons carry an injected action), so the omission is by design, not a gap.

**C1 does NOT over-narrow the extensioned case.** A real deleted `tests/x.js` (has extension) of a completed phase still trips gate_rot end-to-end via `hb.js doctor` ("gate no longer reproducible", doctor rc=1). The existing dangling/rot fixtures (T21 `ghost.spec.js`/`src/app.js`, T27/T30) use extensioned paths and stay green.

## Why KB is NOT done — the C1 fix trades false-positives for false-NEGATIVES (both runtimes)

KB2's own written spec: *"require a relative path with a file extension **or trailing slash**."* The implementation does neither escape hatch correctly. In both `hb-lint.js` and `lint.py` the basename is computed as `p.rstrip('/').split('/')[-1]` **before** the test `!/\.[A-Za-z0-9]+$/.test(base)` — so the trailing slash is stripped away and every extensionless token is dropped, including trailing-slash directories the spec said to keep.

Concrete, parity-consistent evidence (fixed code, real tree):
- `extractPaths("test -d dist/")` → `[]` in **both** node and python (spec said `dist/` should be TRACKED). Trailing-slash escape hatch was never implemented.
- `Dockerfile`, `Makefile`, `LICENSE`, `bin/hb`, `dist/`, `build/` → all `[]`. Any extensionless artifact is now silently un-tracked.

**End-to-end regression (the decisive one).** A completed phase whose gate criterion is `grep -q ARG tests/frameworks/Dockerfile`, gate passed, then the Dockerfile deleted (a genuine rot):

```
gate passed. Now DELETE the extensionless Dockerfile (a genuine rot).
=== doctor (fixed lint) ===
✓ hb doctor: healthy   (doctor rc=0)
```

Doctor reports **HEALTHY** on a completed phase whose gate is now unreproducible. Before C1, a deleted artifact of a completed phase tripped gate_rot; after C1, any *extensionless* one is invisible. This is precisely the kernel-correctness failure mode KB was chartered to fix (incorrect gate_rot state) — flipped from over-firing to under-firing.

`tests/frameworks/Dockerfile` is not hypothetical: it exists in this repo and is referenced by a real gate criterion in `planning/howto-framework-dockers.dag.json` (GATE_FH0/fh0c3). A repo-wide scan of every `planning/*.dag.json` gate criterion found the new guard drops 107 tokens; most are legitimately-dropped `cd`/`grep -r` directory args (the intended win), but the set also includes genuine extensionless artifacts and real directory artifacts (`tests/fixtures`, `plugin/adapters/code/fixtures`, `plugin/adapters/research/fixtures/{redteam,evidence,unstamped}`, `tests/frameworks/Dockerfile`) that a rot check should still track.

**The proof under-specifies its own fix.** `rot-lint-precision.sh` (T126) asserts the genuine-artifact case only with `tests/e2e/x.spec.js` (extensioned). It never asserts an extensionless real artifact still trips rot, so the proof passes green while the false-negative it introduces goes uncaught. Per AGENTS.md rule 3, a gate must assert behavior; this one leaves the regression it created untested.

Impact: no live effect *today* (the repo's own `.hb/dag.json` has `completed_phases: []`, so nothing is in the rot surface yet). But the kernel now cannot detect rot of any extensionless artifact in any completed phase — a correctness hole in the exact subsystem KB2 claims to have fixed, present identically in both runtimes, and contradicting KB2's stated acceptance ("or trailing slash").

## Minimal remedy (for the implementer, not applied here)
Honor the spec's second clause: treat a token as an artifact if the (un-stripped) token ends in `/` OR the basename has an extension. Then add a proof line asserting a deleted extensionless/dir artifact of a completed phase still trips gate_rot end-to-end, in both runtimes.

VERDICT: REFUTED

---

# GATE_KB — RE-REVIEW after the C1 fix change (adversarial reviewer, stripped env)

The prior REFUTED verdict stood on one reason: the C1 `extractPaths` fix required a file **extension** on the basename, so extensionless artifacts (Dockerfile, Makefile, bin/hb, dist/) were silently un-tracked — a deleted `tests/frameworks/Dockerfile` in a **completed** phase left `hb doctor` HEALTHY (false-negative). The fix was changed: both `hb-lint.js` and `lint.py` now exclude only (a) absolute paths (leading `/`) and (b) tokens whose FIRST path segment is a single letter (`^[A-Za-z]/` — the sed `s/a/b/` / `y/a/b/` shape). Extensionless multi-segment artifacts are kept. I tried to break it four ways.

## 1. The false-negative is CLOSED — end-to-end, both runtimes

Built a throwaway `.hb` tree: one phase P1, `gate_exit G1`, criterion `grep -q ARG tests/frameworks/Dockerfile`; event log `task_started → task_done → gate_passed` so the projection marks **P1 completed** (`completed_phases:[P1]`, verified via `hb rebuild`).

- **node** (`hb.js doctor`): Dockerfile present → `✓ healthy, rc=0`; **delete it** → `✗ G1 [c1] → missing tests/frameworks/Dockerfile (phase P1 DONE — gate no longer reproducible)`, `rc=1`.
- **python** (`doctor.doctor` / `has_rot`): present → `problems: []`, `has_rot: False`; **delete it** → `problems: ['G1 [c1] → missing tests/frameworks/Dockerfile (phase P1 DONE — gate no longer reproducible)']`, `has_rot: True`.

Both runtimes now trip gate_rot on a deleted extensionless artifact of a completed phase. The exact case from the prior refutation is fixed. Confirmed at unit level too: `extractPaths("grep -q ARG tests/frameworks/Dockerfile")` → `['tests/frameworks/Dockerfile']` in **both** node and python; `bin/hb`, `dist/`, `tests/fixtures` likewise kept. The real repo gate that referenced it (`planning/howto-framework-dockers.dag.json` GATE_FH0/fh0c3) is now tracked.

## 2. The original C1 bugs STAY fixed — mutate-check + teeth

- Real tree: `extractPaths("sed -i 's/a/b/g' f.txt")` → `[]` (both runtimes); `extractPaths("/usr/bin/node --version")` → `[]` (both). `cat /usr/bin/node`, `sed s/a/b/ file` → `[]`. Not flagged as rot.
- `rot-lint-precision.sh` (T126) runs GREEN (`ROT-LINT-PRECISION-OK`), and now carries the guard line asserting `docker build -f tests/frameworks/Dockerfile .` → the extensionless artifact IS tracked (line 16).
- **Teeth (on a mktemp copy):** delete ONLY the `^[A-Za-z]/` guard line → `extractPaths("sed -i 's/a/b/g' f.txt")` → `['s/a/b/g']` and the proof goes **RED**: `FAIL: sed pattern treated as a path`. So the single-letter guard is load-bearing for the sed case (the abspath guard independently covers `/usr/...`, and reverting it alone also reddens the proof). The proof is teeth-y for the guard it now enforces.

## 3. No new over/under-firing — `^[A-Za-z]/` is not too broad

Scanned every gate criterion `cmd` in all 55 `planning/*.dag.json` (plus `.hb/dag.json`, `plugin/templates/dag.json`) for path-like tokens the guard drops (single-char first segment). **Result: zero.** No real artifact path in the repo's own DAGs starts with a single-letter directory, so the guard drops nothing legitimate; the sed/`y` shell constructs it removes are exactly the intended targets (the corpus does contain `s/...` sed patterns, correctly filtered). Residual theoretical risk: an artifact literally at `a/b/Dockerfile` (first segment one char) would be dropped — but no such path exists in this repo, and it is an accepted, documented trade in the code comment. **Parity:** ran node's `extractPaths` and python's `extract_paths` over all **434** real gate criteria — **0 mismatches**. Node ≡ python on the rule (same exclusions, same kept set), consistent with the fixed-fixture parity suite.

## 4. Nothing else regressed

- `HB_NO_GIT=1 bash tests/run-tests.sh` → **347 passed, 0 failed**; `GROUPS-PASSED` includes T126 T127 T128 T129 and the rot tests T21 T27 T30.
- `HB_NO_GIT=1 PYTHONPATH=src pytest -q` → **96 passed**.
- `tests/parity.sh` → **PARITY OK — node ≡ python**.
- The other three KB fixes unchanged and green: `state-determinism.sh` (C3, `PYTHONHASHSEED=random`) → STATE-DETERMINISM-OK; `gate-gitless.sh` (C4) → GATE-GITLESS-OK; `gate-blocked-breaker.sh` (C8) → GATE-BLOCKED-BREAKER-OK.

All teeth-mutations were on `mktemp -d` copies; the real tree is clean (`git diff` on the lint files = only the +6/+7 guard additions; no `GUARD REMOVED` leftovers). Temp dirs removed.

## Conclusion

The one reason the prior verdict rested on is resolved: the extensionless-artifact false-negative is closed end-to-end in both runtimes, the original C1 over-firing (sed/abspath) stays fixed with a teeth-y proof, the new guard drops nothing real in the repo's DAGs, node and python agree on all 434 criteria, and all suites + the other three KB proofs are green. I could not find a hole.

VERDICT: COULD NOT REFUTE
