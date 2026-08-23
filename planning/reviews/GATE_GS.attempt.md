# GATE_GS refutation attempt — git-snapshot-on-acceptance cross-runtime parity (v1.28 Phase GS)

Actor: `HB_ACTOR=gs-refuter2` (distinct from the implementer). I did NOT do this work.
Target claim: the git-snapshot-on-acceptance is a cross-runtime behavioral PAIR — node's inline
snapshot in `hb.js review` ≡ python's `gate._git_snapshot` (via `review_policy.accept_review`) — and
`docs/howto/gate-examples/git-snapshot-parity.sh` (T141) proves that driving `hb review GATE_P0 pass`
in BOTH runtimes commits + force-tags GATE_P0, with a missing tag going RED. Recorded in parity-notes.md.

A prior plan-refutation demanded the proof (a) test the REVIEW-ACCEPTANCE path (not the on-pass branch),
(b) unset HB_NO_GIT/HB_NO_HOOK, and (c) contain an internal negative (tag-absence → RED) assertion.

## 1. The proof drives the REAL review-acceptance path in both runtimes, git env unset, asserts tag exists

`docs/howto/gate-examples/git-snapshot-parity.sh`:
- NODE (lines 24–30): `node .hb/hb.js review GATE_P0 pass --artifact att.md` — the review-acceptance CLI,
  not the deterministic on-pass branch. Wrapped in `run(){ env -u HB_NO_GIT -u HB_NO_HOOK "$@"; }` (line 18),
  so the git guard is unset.
- PYTHON (lines 34–40): `python3 -m heartbeat.cli review GATE_P0 pass --artifact att.md`, same `env -u` wrapper.
- Both assert the tag EXISTS (`git tag -l | grep -qx GATE_P0`) AND resolves to a commit
  (`git rev-parse "GATE_P0^{commit}"`). Lines 29–30 (node), 39–40 (py).

Source confirms the pair:
- `plugin/templates/hb.js` `case 'review'` (line 465 records `review_passed`, then lines 468–479 do
  `git add -A` + commit + `git tag -f gate`), guarded by `!process.env.HB_NO_GIT`.
- `py/src/heartbeat/review_policy.py:92` calls `_gate._git_snapshot(hb, gate)` at review acceptance.
- `py/src/heartbeat/gate.py:113–128` `_git_snapshot`: HB_NO_GIT early-return (114), add/commit, `tag -f` (128).
- `gate.py:86–90`: on deterministic pass, a *review*-gated phase does NOT snapshot (deferred to acceptance) —
  matching hb.js. The on-pass branch is genuinely not the tested path; acceptance is.

Baseline: `bash git-snapshot-parity.sh` → `GIT-SNAPSHOT-PARITY-OK` (exit 0).

## 2. Teeth in BOTH directions — each gutting turns the proof RED, naming the right runtime

- Gutted node `hb.js` line 477 (`tag -f` → no-op): proof → `FAIL: node: review acceptance did NOT create the GATE_P0 tag`. Reverted.
- Gutted python `gate.py` line 128 (`_git(pd,"tag","-f",gate_id)` → `pass`): proof → `FAIL: py: review acceptance did NOT create the GATE_P0 tag`. Reverted.
- After each revert, baseline returns to `GIT-SNAPSHOT-PARITY-OK`. Neither gutting left the proof green.
  `git diff` on hb.js/gate.py after revert cycles: empty (clean).

The proof therefore has real teeth against BOTH implementations independently — it is not asserting one
side while blind to the other.

## 3. The review pass is real, not a rubber-stamp

Shrinking the artifact to a tiny `ART='x'` (in place, then restored) → `FAIL: node: review pass was rejected`.
So the proof genuinely traverses `accept_review`/`hb.js review` guards: the ≥40-char threshold
(`review_policy.py:53`, and node's citation logic) fires and the run goes RED. If the acceptance were a
stub, an empty artifact would still "pass" and tag — it does not. The distinct-actor guard is present in
both (`review_policy.py:72–80`, `hb.js:453–461`); the proof uses `HB_ACTOR=gs-refuter` on a freshly
bootstrapped project with no `task_done` by that actor, so the distinct-actor check is satisfied honestly,
not bypassed. Restore verified clean (`diff` = empty).

## 4. Determinism — 10× runs

`for i in $(seq 10); do bash git-snapshot-parity.sh 2>&1 | tail -1; done` → `GIT-SNAPSHOT-PARITY-OK` ×10.
No flakiness.

## 5. No tag bleed between runtimes

Separate temp subdirs: `pn="$tmp/n"`, `pp="$tmp/p"` (line 23/33), each independently `git init`'d.
`/tmp` is not a git repo (`git -C /tmp rev-parse` → "not a git repository"), so each init makes a real
independent repo. Instrumented a run:
- node toplevel `…/tmp.XXXX/n`, GATE_P0 → `9cb5aa15…`
- py   toplevel `…/tmp.XXXX/p`, GATE_P0 → `17225694…`
Distinct toplevels, distinct commit SHAs. Each runtime's tag came from its own code path; no shared repo,
no bleed.

## 6. parity-notes honesty

`planning/parity-notes.md:66–71`: one bullet, "git-snapshot on review acceptance is a cross-runtime pair",
frames node's inline `hb.js review` ≡ python's `gate._git_snapshot` (via `review_policy.accept_review`),
force-tag the gate id in both, held by behavioral parity proof **T141** (`git-snapshot-parity.sh`), missing
tag is RED. The claim "cannot be code-shared across bash and Python, so it is held by a behavioral parity
proof" is accurate — hb.js (JS) and gate.py (Python) are separate implementations with no shared library.
Wired: `docs/dev-tests.md:160` (T141) and `tests/run-tests.sh:1540–1544` (T141.1 → GIT-SNAPSHOT-PARITY-OK).

## 7. Full suites

- `HB_NO_GIT=1 bash tests/run-tests.sh` → `RESULT: 360 passed, 0 failed` / `✅ ALL GREEN`.
- `bash tests/parity.sh` → `✅ PARITY OK — node ≡ python`.

## Findings / caveats

- The proof relocated to `/tmp` breaks only because `ROOT` is computed via `BASH_SOURCE` path arithmetic
  (line 10) — a property of the file's location, not a correctness flaw. Run in place, it is correct.
- No refutation found. Every teeth injection is caught in the right direction; the acceptance path, git-env
  unset, and negative tag-absence assertion all hold; determinism and isolation confirmed; docs accurate.

All mutations reverted; working tree contains only the pre-existing Phase-GS changes and this attempt file.

VERDICT: SOUND
