# Refutation attempt — Phase PO ("parity as a differential-testing oracle")

Reviewer: skeptical second actor (not the implementer). Goal: prove PO could pass its
gate while the real work is broken — i.e. that the fuzz oracle can print
`FUZZ-PARITY-OK` / `SELFTEST-CAUGHT` without actually testing meaningful parity.

Files under test:
- `tests/gen-parity-case.py`
- `tests/parity-fuzz.sh`
- `py/src/heartbeat/report.py` (the rounding fix)
- `tests/run-tests.sh` (T75 wiring)

## What I ran

```
bash tests/parity-fuzz.sh 8            -> FUZZ-PARITY-OK:8, exit 0
bash tests/parity-fuzz.sh --selftest   -> SELFTEST-CLEAN-OK + SELFTEST-CAUGHT:lint, exit 0
bash tests/parity.sh                   -> PARITY OK, exit 0
python3 tests/gen-parity-case.py <s> - (many seeds), md5sum
```

## Claim-by-claim

### Claim 1 — fuzzer really compares both runtimes? HOLDS.
`run_case` in `tests/parity-fuzz.sh` diffs all seven surfaces (audit, lint, state, next,
ready, report, diagnose), each `[ "$n" = "$p" ] || { echo <surface>; return; }`. I injected an
off-by-one into a mutant copy of `report.py` and pointed the fuzzer at it via `HB_PY_SRC`:
it reported `✗ seed 0 diverged on: report` and exited 1. Surfaces are genuinely diffed.

### Claim 3 — determinism, no time/random leak? HOLDS.
Same seed → byte-identical output (`seed 5` three times, `seed 6` twice: identical md5).
`grep -iE "time|random|datetime|clock|uuid|urandom|getpid"` finds only the docstring/comment,
no import or call. Generator depends only on the seed. Good.

### Claim 4 — --selftest genuinely needs the mutant? HOLDS.
The mutant runtime is really exercised: `run_case` recomputes `PY` from the current
`HB_PY_SRC` on every call (dynamic scope reaches `a_py`/`l_py`). I neutered the injected
mutation (removed the appended `ZZZ-...` error) in a repo-local copy and re-ran `--selftest`:
it printed `SELFTEST-ESCAPED` and exited 1. So `SELFTEST-CAUGHT` cannot be printed without a
real divergence. Teeth confirmed.

### Claim 5 — rounding fix correct + parity.sh green? PARTIAL / see hole below.
`tests/parity.sh` is green. Node: `Math.round(100*done/total)`. Python (fixed):
`int(done/total*100 + 0.5)`. Over the generator's *actual* (done,total) space (only 10 distinct
pairs) these agree, so the fix is fine for what the suite touches. BUT the two formulas are NOT
equivalent in general (see Hole 3): e.g. done=23,total=40 → node 58, python 57. That pair is
outside the generator's reach, so the oracle can't see it.

### Claim 6 — T75 wired and would go red on divergence? HOLDS.
`tests/run-tests.sh:1054-1064` defines T75.1/.2/.3, gated only on python3+node presence
(skipped, not faked, when absent). The mutant-report.py run above makes the fuzzer exit 1,
so T75.1 would go red on a real divergence.

## HOLES FOUND (Claim 2 — case variety — FAILS)

### Hole 1 (SEVERITY: HIGH) — the generator produces almost no distinct cases.
The "seeded generator of structurally-varied cases" is the entire premise of PO, but it barely
varies:

```
distinct md5 among default N=12 seeds (0..11):   5
distinct md5 among seeds 0..31:                  5
distinct md5 among seeds 0..999:                10
```

Seeds 0, 1, 5, 9 are byte-identical; 2, 6, 10 identical; 3, 7, 11 identical. The default
`parity-fuzz.sh 12` (what T75.1 runs) effectively tests 5 cases, and no amount of extra seeds
gets past ~10. This is a textbook **LCG-low-bits** bug: `rand(n)` uses `self.s % n`, and the low
bits of a power-of-two-modulus LCG are near-constant. `rand(4)` cycles `2,3,0,1` with period 4 —
so every structural size is a pure function of `seed mod 4`:

```
seed 0..11 rand(4) sequences: all are one of {2,3,0,1 rotations}, repeating with period 4
```

### Hole 2 (SEVERITY: HIGH) — whole behavioral surfaces are NEVER generated.
`chance()` = `rand(2)` = the LCG low bit, which strictly alternates T,F,T,F…. At the fixed call
sites it therefore always lands the same way. Measured across 2000 seeds:

```
review gate ever generated:   False   # gates never get a "review" block
task_started events emitted:  0       # in-flight/started frontier never produced
task_failed events emitted:   1758
```

Consequences the oracle silently never tests, on ANY seed:
- **review-blocked parity**: `pending_reviews`, `review_passed` events, review-gated `next`
  (a `type:"review"` next task). The whole review path — a core shared surface, with its own
  parity fixture `state:review-owed` in parity.sh — is untouched by the fuzzer.
- **`task_started` projection**: the "started/in-flight" state is never in a generated case,
  so `state`/`next`/`ready`/`diagnose` are never differentially tested against an in-flight task.

So the oracle's coverage claim ("explore the shared input space") is false: it explores a tiny,
fixed corner and structurally cannot reach review or started states.

### Hole 3 (SEVERITY: MEDIUM) — the rounding fix is not actually equivalent to node, and the
oracle can't detect it. `int(done/total*100 + 0.5)` differs from `Math.round(100*done/total)`
at a genuine half-integer FP case:

```
done=23,total=40:  node Math.round(100*23/40)=58 ; python int(23/40*100+0.5)=57
  (23/40*100 == 57.49999999999999 in both; JS Math.round -> 58, python +0.5 -> 57.9999.. -> 57)
```

This is exactly the class of bug PO was created to catch, and PO claims to have fixed a
"report-rounding divergence" — but the fix trades one rounding mismatch for another that only
hides because the generator's total task count maxes at 4x4=16 and yields only 10 (done,total)
pairs, none of which hit a half-integer boundary. A correct fix would mirror node's expression
exactly (`round half up on 100*done/total`, same operand order) or share a rounding helper.

## Why this defeats the gate's intent
PO's value is "many varied well-formed cases as a mutual oracle." Holes 1-2 mean the fuzzer is,
in practice, ~5-10 fixed fixtures that never touch the review or started paths — not materially
stronger than the existing `tests/parity.sh`, and it cannot surface the very class of
divergence (Hole 3) the phase advertises fixing. The gate (`FUZZ-PARITY-OK` / T75 green) passes
while the "differential-testing oracle" is effectively hollow: green regardless of whether
review/started parity is broken, because those inputs are never generated.

## Suggested fixes (for the implementer)
- Use high bits, not low bits: e.g. `rand(n) = (self.next() >> 16) % n`, or a hash-based mixer.
  Verify: distinct cases across N=12 seeds should be ~N, and review/started must both appear.
- Assert coverage in the generator's own selftest: over the fuzzed seed set, at least one
  review gate and one `task_started` must be produced (else the oracle is silently narrow).
- Make report percent share one rounding expression across runtimes (same operand order,
  half-up), and add the 23/40-style pair to the generator's reachable space.

---

# RE-CHECK #2 — second skeptical actor, after the claimed fixes

Different actor than the implementer. Goal: confirm the three holes above are genuinely
closed and hunt for new ones. All commands below run from repo root on 2026-08-09.

## The three prior holes — re-verified

### Hole 1 (variety) — CLOSED.
```
for s in $(seq 0 39); do python3 tests/gen-parity-case.py $s - | md5sum; done | sort -u | wc -l
  -> 40        # 40 DISTINCT cases across 40 seeds (was 5)
```
The generator now uses xorshift32 drawing from high bits (`rand(n)=(next()>>13)%n`,
`chance()=((next()>>16)&1)==0`). Determinism preserved: seeds 5/17/33 each byte-identical
across two runs (identical md5). No time/random import. Good.

### Hole 3 (rounding) — CLOSED, and I brute-forced it.
```
python3 -c "d,t=23,40;print(int(100*d/t+0.5))"  -> 58
node -e "console.log(Math.round(100*23/40))"      -> 58   # now agree
```
Brute force over EVERY (done,total) with 1<=total<=64, 0<=done<=total (2080 pairs), comparing
python `int(100*done/total+0.5)` vs node `Math.round(100*done/total)`:
```
mismatches: 0
```
The fix `int(100*done/total+0.5)` (same operand order as node, `100*done` first) is exact over
the whole ≤64 space. A real report divergence is caught: I mutated a `HB_PY_SRC` copy's percent
to `+1` and ran `parity-fuzz.sh 12` -> `✗ seed 0 diverged on: report`, exit 1.

### Hole 2 (surface coverage) — PARTIALLY CLOSED. STILL A HOLE (see below).
`task_started`/in-flight IS now generated and differentially tested:
```
seeds 0..39 with task_started: 19 ; with review gate in DAG: 30 ; with task_failed: 16
in-flight started (started task not yet done): 19 seeds  # state/next/ready/diagnose see it
```
So the *started/in-flight* half of prior Hole 2 is genuinely fixed. BUT the *review-owed* half
is NOT.

## NEW / REMAINING HOLE — review-owed parity is still never tested (SEVERITY: HIGH)

The prior Hole 2 named TWO untested surfaces: `task_started` AND the review path
("`pending_reviews`, review_passed events, review-gated `next` — a `type:"review"` next task").
The started surface is fixed; **the review-owed surface is still structurally unreachable.**

Root cause (tests/gen-parity-case.py:84-85): whenever a completed phase's gate is review-blocked,
the generator *immediately* appends `review_passed`. And the frontier phase (phases[n_done]) is
never completed — it only ever gets a `task_started`/`task_failed` on its FIRST task
(lines 86-92). So a review is never left owed, and a phase's tasks are never all-done with the
gate still pending.

Measured, projecting each generated case through the python port:
```
seeds 0..39   : pending_reviews non-empty -> 0 ;  gate-pending phase -> (implied 0)
seeds 0..999  : pending_reviews non-empty -> 0 ;  gate-pending phase -> 0
```
`next`-type distribution across 40 seeds (via the CLI the fuzzer uses):
```
task: 26   all_done: 10   deadlock: 4     # NEVER type:"gate", NEVER type:"review"
```

Consequences — two shared surfaces the oracle green-lights without ever exercising:
- **review-owed state**: `pending_reviews` is compared by the fuzzer (parity-fuzz.sh:45) but is
  empty on every generated case, so a node<->python disagreement on review projection would not
  be caught. `tests/parity.sh` has a dedicated `state:review-owed` fixture precisely because this
  is a real shared surface; the fuzzer never reaches it.
- **`type:"gate"` and `type:"review"` next**: the fuzzer's `next` normalizer (line 49) captures
  `d.type` and `d.gate`, so it *could* see them — but no generated case ever produces a
  gate-pending or review-owed frontier, so the gate-blocked and review-blocked branches of the
  resolver are never differentially tested. Only `task`/`all_done`/`deadlock` are.

This is the same class of gap the prior refutation flagged (the oracle "explores a tiny fixed
corner"), only narrower: it's now review-owed + gate-pending rather than review + started. The
generator's own docstring/comment (lines 74-76) claims it completes phases "review passed when
the gate is review-blocked" and varies the frontier — but it never leaves a review OWED, so the
review parity path advertised by PO is green regardless of whether it is broken.

### Suggested fix
Let the frontier (or an intermediate) phase land in a gate-pending or review-owed state on some
seeds: e.g. on a `chance()`, emit all `task_done` for the frontier phase but withhold
`gate_passed` (=> gate-pending, `type:"gate"` next), and on another branch pass the gate but
withhold `review_passed` for a review gate (=> review-owed, `pending_reviews` non-empty,
`type:"review"` next). Then assert in the generator selftest that across the fuzzed seed set at
least one `pending_reviews`-nonempty case and one `type:"gate"`/`type:"review"` next are produced.

## What still HOLDS
- `parity-fuzz.sh --selftest` -> `SELFTEST-CLEAN-OK` + `SELFTEST-CAUGHT:lint`, exit 0.
- `parity-fuzz.sh 40` -> `FUZZ-PARITY-OK:40`, exit 0; a real injected divergence turns it red.
- Determinism intact; T75.1/.2/.3 (run-tests.sh:1054-1064) wired, skip-not-fake when tools absent.

## Bottom line
Holes 1 and 3 are genuinely closed and provably so. Hole 2 is only HALF closed: the in-flight
(`task_started`) surface is now tested, but the review-owed / gate-pending surface — explicitly
named in the prior refutation and covered by parity.sh's own `state:review-owed` fixture — is
still structurally unreachable across 1000 seeds. The oracle's coverage claim remains false for
the review path, so PO's core promise ("differentially test the shared surfaces, including the
review path") is not met.

VERDICT: REFUTED
Remaining hole: the generator never produces a review-owed (`pending_reviews` non-empty,
`type:"review"` next) or gate-pending (`type:"gate"` next) case — 0 across seeds 0..999 — so the
review/gate-blocked resolver + review projection are never differentially tested by the fuzzer,
despite being shared surfaces (parity.sh has a `state:review-owed` fixture for exactly this).

---

# RE-CHECK #3 — FINAL — third skeptical actor, after the frontier-state fix

Different actor than the implementer. Goal: confirm the ONE remaining hole from Re-check #2
(review-owed + gate-pending never generated) is genuinely closed, and hunt for regressions.
The generator (tests/gen-parity-case.py:86-102) was changed to vary the frontier phase's state
via `mode = r.rand(3)`: mode 0 = in-flight (start/fail first task), mode 1 = gate-pending (all
tasks done, no gate_passed), mode 2 = review-owed (all tasks done + gate_passed, no review_passed).
All commands run from repo root.

## The remaining hole — CLOSED. Quantified across 1000 seeds.

Note on naming: the resolver emits `type:"review_pending"` / `type:"gate_pending"` (not
"review"/"gate") — resolver.py:79-80. That is the string the fuzzer's `next` normalizer captures
(parity-fuzz.sh:49, `d.type`). Counts below via the exact CLI the fuzzer uses
(`PYTHONPATH=py/src python3 -m heartbeat.cli next|state --dir`):

```
seeds 0..999 :
  next type review_pending : 105      (was 0)
  next type gate_pending   : 217      (was 0)
  pending_reviews non-empty: 105      (was 0)
  gate-pending phase (tasks all done, phase not completed): 322   (was 0)
  next-type distribution: {all_done:392, deadlock:23, gate_pending:217, none:263, review_pending:105}
seeds 0..11 (T75.1 default): review_pending 1, gate_pending 3, pending_reviews 1, gate-pending-phase 4
seeds 0..39                : review_pending 8, gate_pending 10, pending_reviews 8, gate-pending-phase 18
```

Both surfaces are now reached even in the DEFAULT 12-seed set T75.1 runs. Hole closed.

## Item 2 — the fuzzer COMPARES both runtimes on these cases (not just generates them). HOLDS.

Review-owed seeds in 0..39: {6,13,15,16,20,24,25,39}. Gate-pending seeds in 0..11: {1,4,8}.
The fuzzer's `state` normalizer (parity-fuzz.sh:45) captures `pending_reviews` (field 2); the
`next` normalizer (:49) captures `type` (field 0) and `gate` (field 2). On review-owed seed 6:

```
NODE state -> [...,["G0"],0,"P0"]     PY state -> [...,["G0"],0,"P0"]       (agree)
NODE next  -> ["review_pending","","G0","P0"]   PY next -> same              (agree)
run_case(seed6) -> ""  (empty = all seven surfaces agree)
```

So a review-owed case genuinely flows through run_case and its pending_reviews + next.type are diffed.

## Item 3 — oracle still finds divergences on the review surface. PROVEN via HB_PY_SRC seam.

Throwaway copy of py/src (repo py/src untouched); perturbed state.py:153-154 so the review-owed
gate is dropped from `pending_reviews` (`pending_reviews.append(g)` -> `pass  # MUTANT`). Pointed
the fuzzer at it via HB_PY_SRC:

```
HB_PY_SRC=<mutant> run_case(seed6) -> "state"                 (caught in isolation)
HB_PY_SRC=<mutant> bash tests/parity-fuzz.sh 7:
  ✓ seed 0..5 ;  ✗ seed 6 diverged on: state ;  ❌ FUZZ-PARITY DIVERGENCE ; exit 1
```

The review projection divergence is caught end-to-end, on the review-owed seed, exit 1. Teeth
confirmed on the new surface.

## Item 4 — regressions. NONE.

```
determinism: seeds 6/13/37 each byte-identical across two `gen ... -` runs (same md5)
distinct cases: 40 across 40 seeds (md5 | sort -u | wc -l -> 40)
no leak: grep for import random/time/datetime, urandom, getpid, time./random./datetime. -> none
bash tests/parity-fuzz.sh 40   -> FUZZ-PARITY-OK:40, exit 0
bash tests/parity-fuzz.sh --selftest -> SELFTEST-CLEAN-OK + SELFTEST-CAUGHT:lint, exit 0
bash tests/parity.sh           -> PARITY OK, exit 0
bash tests/run-tests.sh        -> 274 passed, 0 failed (incl. T75.1/.2/.3 green)
cd py && PYTHONPATH=src python3 -m pytest -q -> 72 passed
```

T75.1 (`parity-fuzz.sh 12`) now exercises gate-pending seeds {1,4,8} and review-owed seed 6 and
still returns FUZZ-PARITY-OK, so the newly-reached state/next/ready/diagnose branches all agree.

## Bottom line
The one remaining hole (review-owed / gate-pending never generated, 0 across 1000 seeds) is
genuinely and provably closed: 105 review-owed + 217 gate-pending cases across 1000 seeds, both
present in the default 12-seed run; the fuzzer diffs pending_reviews and next.type on them; an
injected review-projection divergence is caught end-to-end via the HB_PY_SRC seam. No regressions:
determinism, 40-distinct-cases, both suites, parity, parity-fuzz 40, and --selftest all green.

VERDICT: COULD NOT REFUTE
