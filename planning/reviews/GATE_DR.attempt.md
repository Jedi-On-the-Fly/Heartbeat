# GATE_DR — adversarial refutation attempt (refuter: dr-refuter2)

Actor: `HB_ACTOR=dr-refuter2`. I did none of this work. Goal: refute that Phase DR
of critical-fixes-2 is genuinely done, with special focus on whether the PRIOR
refuter's found hole (hollow write-lock proof that only grepped the append-only
`events.jsonl` and passed even with the lock gutted) is REALLY fixed.

## 1. The wlock fix — attacked hardest

Read `docs/howto/gate-examples/wlock-tested.sh`. The proof now runs **two
concurrent workers through the REAL primitive**, each doing read → forced 150ms
overlap → increment → write of a shared counter file. Serialized ⇒ counter==2; a
no-op lock ⇒ both read 0, both write 1 ⇒ counter==1 (lost update).

Real primitives (mkdir-based mutual exclusion) confirmed:
- node `withWlock` — `plugin/templates/hb.js:207` (`fs.mkdirSync(WLOCK)` spin, 5s deadline, finally rm).
- python `with_wlock` — `py/src/heartbeat/state.py:193` (`wlock.mkdir()` spin, finally rmtree).

Both are exercised via the real export:
- `plugin/templates/hb.js:572` `module.exports = { ..., withWlock }` — the newly-added export. The node worker does `const hb = require(process.env.HBJS); hb.withWlock(...)` — it calls the real one, not a reimplementation.
- python worker does `from heartbeat import state as st; st.with_wlock(...)`.

### Gutting the locks (must go RED)

python gutted — inserted `return fn()` as first line of `with_wlock` body:
```
$ bash docs/howto/gate-examples/wlock-tested.sh 2>&1 | tail -1
FAIL: py: with_wlock did not serialize the RMW — counter=1 (expected 2; a lost update means the lock is a no-op)
```

node gutted — inserted `return fn();` as first line of `withWlock` body:
```
$ bash docs/howto/gate-examples/wlock-tested.sh 2>&1 | tail -1
FAIL: node: withWlock did not serialize the RMW — counter=1 (expected 2; a lost update means the lock is a no-op)
```

Both gutting attacks produce counter=1 DETERMINISTICALLY — the exact lost-update
signature. The proof is no longer hollow: unlike the prior events.jsonl grep, it
fails when the lock is a no-op. (The node stage runs first and aborts on failure,
so I confirmed the python stage independently by reverting node and re-running
with only python gutted.) Both mutations reverted.

### Flakiness — 10 runs on unmodified code
```
$ for i in $(seq 10); do bash docs/howto/gate-examples/wlock-tested.sh 2>&1 | tail -1; done
WLOCK-TESTED-OK   (×10)
```
10/10 green — not flaky. The 150ms forced overlap window is far wider than the
RMW critical section, so an unlocked run cannot serialize by luck (both readers
observe 0 before either writes) — confirmed by the deterministic counter=1 on
gutting. The lock is fast (mkdir), so the locked path stays well under the 5s
deadline; no false RED observed.

Wired into the node suite as T139.1 (seen in `tests/run-tests.sh` output).

## 2. Single-source anti-drift (single-source.sh → SINGLE-SOURCE-OK)

- `plugin/templates/hb-exec.js:27` `const { nonBehavioral } = require('./hb-audit.js');` — imports, no fork.
- `plugin/templates/hb-audit.js:149` exports the canonical `nonBehavioral`.
- Proof prints SINGLE-SOURCE-OK on unmodified code.

Attacked: added a forked `function nonBehavioral(cmd){return false;}` to hb-exec.js:
```
$ bash docs/howto/gate-examples/single-source.sh 2>&1 | tail -1
FAIL: hb-exec.js still DEFINES its own nonBehavioral (forked — import hb-audit's instead)
```
Goes RED on a fork. Reverted. R3 half (SKILL.md reason table == protocol.py keys)
passes as part of the same green proof.

## 3. Fixtures moved

`tests/fixtures/audit/` (existence, good, hollow, nondeterministic, side-effect)
and `tests/fixtures/parity/` (broken.json) exist. `planning/parity-notes.md:22`
now references `tests/fixtures/parity/broken.json`. Stale-ref sweep:
```
$ grep -rn 'audit-fixtures\|parity-fixtures' --include='*.sh' --include='*.py' \
    --include='*.js' --include='*.md' . | grep -v 'tests/fixtures' \
    | grep -v 'planning/reviews/' | grep -v 'GATE_.*\.attempt\.md'
(no output)
```
No stale references left.

## 4. Review policy single-sourced (accept_review)

`py/src/heartbeat/review_policy.py::accept_review` is the one source. Callers:
- `cli.py:170` → `review_policy.accept_review(...)`
- `executor.py:348-352` → `from . import review_policy` / `review_policy.accept_review(...)`
- `mcp_server.py:152-153` → `from . import review_policy` / `review_policy.accept_review(...)`

No `cli.main(["review"` scrape remains anywhere in `py/src/heartbeat/`.

All four security properties preserved in accept_review:
- <40-char rejection — `review_policy.py:53`.
- phase-citation requirement — `review_policy.py:56-71` (anchors from gate/phase/task ids + criteria paths; rejects if artifact cites nothing real).
- distinct-actor check — `review_policy.py:72-80` (rejects if reviewer HB_ACTOR is among the phase's task_done actors).
- git snapshot on pass — `review_policy.py:92` `_gate._git_snapshot(hb, gate)`.

Review tests: `cd py && PYTHONPATH=src python3 -m pytest -q -k review` → **14 passed, 82 deselected**.

## 5. All three suites (real counts)

- `HB_NO_GIT=1 bash tests/run-tests.sh` → **RESULT: 357 passed, 0 failed — ALL GREEN** (T139.1 present).
- `cd py && PYTHONPATH=src python3 -m pytest -q` → **96 passed**.
- `bash tests/parity.sh` → **PARITY OK — node ≡ python**.

## Conclusion

The prior hole is genuinely fixed: the wlock proof now drives the real primitive
through a concurrent RMW and goes RED (deterministic counter=1) when either lock
is gutted, and is non-flaky over 10 runs. Single-source, fixture move, and
accept_review single-sourcing all hold up, including going RED under a fork
injection. All three suites green at expected counts (357 / 96 / PARITY OK). I
mutated and reverted node+python locks and hb-exec; tree left clean. I could not
refute.

VERDICT: SOUND
