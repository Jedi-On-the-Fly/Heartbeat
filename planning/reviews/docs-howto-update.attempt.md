# Refutation attempt — how-to updates for the CI PATH fix

Actor: `HB_ACTOR=docs-refuter`. Skeptical review of three how-to edits that document the
`pre-push-selfcontained.sh` (T122) portability fix (hardcoded `CLEAN=/usr/bin:/bin` → derived
`CLEAN` via `dirname "$(command -v node)"`), plus the new T143 prose-integrity group.

Docs under review:
- `docs/howto/block-pushes-on-failing-gates.md`
- `docs/howto/writing-behavioral-gates.md`
- `docs/howto/run-heartbeat-in-ci.md`

Proof of record: `docs/howto/gate-examples/pre-push-selfcontained.sh`.

---

## Attempt 1 — Accuracy vs code (looking for overclaims)

Read the proof `pre-push-selfcontained.sh`:
- **CLEAN is derived, not hardcoded.** Line 22:
  `CLEAN="$(dirname "$(command -v node)"):$(dirname "$(command -v git)"):/usr/bin:/bin"`.
  The old hardcode is described only in the explanatory comment (lines 19–20). ✅ matches the docs.
- **Node hook runs the gate re-verify.** The proof invokes `.git/hooks/pre-push` under the clean PATH
  (lines 33–36) and asserts it blocks on the fresh failing seed; the installed node hook body runs
  `gate.sh --all` (as stated in `block-pushes` lines 12, 47, 54). ✅
- **Python hook skips-with-message when `hb` absent.** Lines 42–44: rc must be 0, and stdout must match
  `grep -qiE 'hb|heartbeat'` — i.e. skip (exit 0) with a visible message, not an import-error block. ✅
  matches `block-pushes` lines 54–55 and the `writing-behavioral-gates` subsection.
- **T122 marker.** `echo "PRE-PUSH-SELFCONTAINED-OK"` at line 46 (and on every clean-skip path,
  lines 17, 25, 26). ✅ matches `block-pushes` line 44.
- **Skip-cleanly claim.** `writing-behavioral-gates` says "if the environment genuinely can't reproduce
  the condition … skip cleanly rather than fail" — proof lines 25–26 do exactly that (hb on PATH / system
  python3 imports heartbeat → print marker, exit 0). ✅
- **Causal claim** ("bootstrap step failed" under `/usr/bin:/bin` on CI): bootstrap at line 30 runs under
  `$CLEAN`; with node not in `/usr/bin` there is no node on that PATH, so bootstrap fails. Accurate. ✅

No overclaim found. Every statement in the three edits is supported by the proof.

## Attempt 2 — Links + anchors resolve

- Anchor target exists: `grep -n "^### Environment portability" writing-behavioral-gates.md` → line 81.
  GitHub slug of `### Environment portability` = `environment-portability`.
- Both references use exactly `writing-behavioral-gates.md#environment-portability`
  (`block-pushes` line 58; `run-heartbeat-in-ci` line 36). Slug matches exactly. ✅
- prose-check over the trio prints `ALL-PROSE-OK:3` (command run; output below). ✅

```
$ bash docs/howto/gate-examples/prose-check.sh block-pushes… writing-behavioral-gates… run-heartbeat-in-ci…
PROSE-OK:block-pushes-on-failing-gates.md
PROSE-OK:writing-behavioral-gates.md
PROSE-OK:run-heartbeat-in-ci.md
ALL-PROSE-OK:3
```

**Caveat (not a defect in the docs, but a doc-of-the-test overclaim):** `prose-check.sh` does NOT verify
anchors — line 33 strips the fragment (`base="${t%%#*}"`) and only checks the target *file* exists.
So the `#environment-portability` slug is validated here by hand, not by the gate. `docs/dev-tests.md`
line 162 describes T143 as checking "links **+ anchors** resolve" — that overstates prose-check, which
resolves link *files* only. The anchor does in fact resolve, so no link is broken, but the dev-doc
sentence claims a capability the checker doesn't have. Minor; flagged.

## Attempt 3 — T143 has teeth

T143 definition (`tests/run-tests.sh` lines 1554–1556): runs `prose-check.sh` on the three files and
`grep -q "ALL-PROSE-OK:3"` — a real behavioral assertion, not a filename grep.

Teeth proof — scratch-broke a link in `run-heartbeat-in-ci.md`
(`escalate-instead-of-retry.md` → `escalate-DOES-NOT-EXIST.md`), reran prose-check on the trio:

```
PROSE-OK:block-pushes-on-failing-gates.md
PROSE-OK:writing-behavioral-gates.md
  broken link in docs/howto/run-heartbeat-in-ci.md: escalate-DOES-NOT-EXIST.md
PROSE-FAIL:docs/howto/run-heartbeat-in-ci.md
exit=1
```

No `ALL-PROSE-OK:3` → the `grep -q` guard would fail → T143 goes red. Reverted byte-exact; rerun printed
`ALL-PROSE-OK:3`. The scratch edit was reverted from a backup copy; `git diff` on the three docs is
unchanged from the reviewed edit. ✅ T143 bites.

## Attempt 4 — Stale / contradictory claims

- **T117/T118 descriptions in `block-pushes` lines 42–44** match the proofs: markers
  `PRE-PUSH-HOOK-OK` (`pre-push-hook.sh:44`), `PRE-PUSH-PARITY-OK` (`pre-push-hook-parity.sh:61`),
  `PRE-PUSH-SELFCONTAINED-OK` (`pre-push-selfcontained.sh:46`), and suite groups T117/T118/T122
  (`tests/run-tests.sh` 1406–1415, 1442–1447). No contradiction. ✅
- **Parity write-lock / behavioral-parity:** `block-pushes` continues to frame the two hooks as
  *behavioral* parity ("each calls its own gate tool", not byte-identical), consistent with
  `parity-notes.md`. The new prose adds no parity claim that conflicts. ✅
- **`run-heartbeat-in-ci.md` gotcha stays in scope:** the section is about the CI runner's toolchain
  layout (`hostedtoolcache` vs `/usr/bin`) affecting a gate/proof that hardcodes a path — directly
  relevant to running HeartBeat/gates in CI. It cross-links the catalogue rather than duplicating it.
  No misleading claim. ✅
- **Redundancy observation (not a contradiction):** T79.1 (`tests/run-tests.sh` 1114–1117) already gates
  **every** `docs/howto/*.md` through the identical `prose-check.sh` (count-matched glob), so all three
  edited docs are already prose-gated. T143 is a *targeted duplicate* of coverage T79 already provides.
  It is not wrong (it still bites and names the specific lesson) and does not contradict T79 — but it is
  redundant surface. Flagged as a design note, not a defect.

## Attempt 5 — Full node suite

`HB_NO_GIT=1 bash tests/run-tests.sh 2>&1 | tail -3`:

```
  RESULT: 363 passed, 0 failed
✅ ALL GREEN
```

T122.1, T142.1/T142.2, T143.1 all `✓`; T122/T142/T143 all present in `GROUPS-PASSED`. ✅

---

## Verdict

Every substantive claim in the three edits is supported by the proof; the anchor and all added
links/paths resolve; prose-check prints `ALL-PROSE-OK:3`; T143 has real teeth (proven by breaking a link);
no contradiction with parity-notes or the existing T117/T118 prose; full suite 363 GREEN.

Two non-blocking notes, neither refuting correctness or introducing an overclaim in the reviewed docs
themselves:
1. `docs/dev-tests.md:162` says T143 checks "links + anchors resolve" — prose-check validates link files
   only, not anchors (it strips `#frag`). The anchor happens to resolve; the description overstates the
   checker.
2. T143 duplicates prose coverage T79.1 already provides over the whole `docs/howto/` glob.

Neither is a defect in the three reviewed how-to edits. I cannot refute their correctness or find an
overclaim within them.

VERDICT: SOUND
