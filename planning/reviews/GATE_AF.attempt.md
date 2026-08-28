# GATE_AF — Refuter round-3 attempt (adversarial)

Phase AF: "Skill-format resolver input" — the shared frontmatter/skill parser
(`parse_skill` in `py/src/heartbeat/refuter_profiles.py`, `parseSkill` in
`plugin/templates/refuter_profiles.js`) and its proof
`docs/howto/gate-examples/refuter-skill-format.sh`.

Actor: refuter (did NOT do the work). Round-3 focus: verify the two round-2
remediations — (a) MAX_SAFE_INTEGER range-check closing the `int` vs `parseInt`
`panel > 2^53` divergence, and (b) the parity-notes wording — actually hold, and
re-hunt for any surviving node-vs-python parser divergence.

Anchors:
- py panel guard: `refuter_profiles.py` lines 97–105 (strict-digit + `abs(iv) > 9007199254740991` reject).
- node panel guard: `refuter_profiles.js` lines 76–86 (strict-digit + BigInt range-check lines 82–84).
- proof: `refuter-skill-format.sh` bigpanel 276–278, badpanel 271–273.
- claim: `planning/parity-notes.md` line 18.

Method: for each case write a `.md`, resolve through BOTH runtimes via real
`resolve(hbdir,name)` (node require given an ABSOLUTE path), compare accept/reject
and the exact `verdict.panel` value.

---

## 1. Panel boundary parity — BOTH runtimes, real resolve()

| Input                | Python                     | Node                       | Parity |
|----------------------|----------------------------|----------------------------|--------|
| `0`                  | ACCEPT 0                   | ACCEPT 0                   | AGREE  |
| `3`                  | ACCEPT 3                   | ACCEPT 3                   | AGREE  |
| `-3`                 | ACCEPT -3                  | ACCEPT -3                  | AGREE  |
| `+3`                 | REJECT                     | REJECT                     | AGREE  |
| `03`                 | ACCEPT 3                   | ACCEPT 3                   | AGREE  |
| `9007199254740991`   | ACCEPT 9007199254740991    | ACCEPT 9007199254740991    | AGREE  |
| `9007199254740992`   | REJECT                     | REJECT                     | AGREE  |
| `-9007199254740991`  | ACCEPT -9007199254740991   | ACCEPT -9007199254740991   | AGREE  |
| `-9007199254740992`  | REJECT                     | REJECT                     | AGREE  |
| `notanint`           | REJECT                     | REJECT                     | AGREE  |
| `(empty)`            | REJECT                     | REJECT                     | AGREE  |

All 11 agree on accept/reject and, when accepted, on the exact integer value. The
MAX_SAFE_INTEGER edge is exact and symmetric: `9007199254740991` accepted,
`...992` rejected, mirror on the negative side. The round-2 divergence
(`9007199254740993` → py 9007199254740993 vs node 9007199254740992) is CLOSED:
both now REJECT it before reaching `int`/`parseInt`. `+3` rejected because the
digit guard tolerates only a leading `-`. **No divergence found.**

## 2. Proof teeth are load-bearing (node range-check)

Removed ONLY the node BigInt range-check block (`refuter_profiles.js` lines 82–84)
in a scratch edit of the working file, ran the proof:

    FAIL: node did NOT reject an out-of-safe-range panel (int vs parseInt precision divergence)
    EXIT=1

RED exactly on the bigpanel assertion. Restored the block verbatim (present
exactly once; file byte-identical to pre-edit). Clean re-run:
`REFUTER-SKILL-OK`; `--selftest SELFTEST-OK`; `--seeding SEEDING-SAFE-OK`.
The range-check teeth are load-bearing.

## 3. Adversarial non-panel / encoding re-sweep — all AGREE

17 byte-exact fixtures through both runtimes, all identical:

- Unicode digits arabic-indic `٣`, fullwidth `３`: **both REJECT** — the ASCII
  `'0'<=c<='9'` guard fires before Python's unicode-aware `int()` could accept
  them (a real trap, handled).
- `--3`, `3-`, lone `-`, `0x10`, `1_000`, `3.0`, `1e3`, `3 5` (internal space):
  both REJECT.
- Quoted `"3"`: both ACCEPT 3 (one quote layer stripped).
- Tab after colon (`panel:\t7`): both ACCEPT 7.
- Duplicate `panel:` key: both take last (=2).
- `refute_if: all` passthrough: both ACCEPT panel=3, refute_if=all.
- Spaces around key/colon, empty-key line, CRLF+big-value (both reject on range):
  all AGREE.

No non-panel divergence surfaced.

## 4. Suites + overclaim check

- Node: `379 passed, 0 failed` — ALL GREEN.
- Python: `96 passed`.
- Parity: `PARITY OK — node ≡ python` (incl. `skill-format:asfolder`).
- `parity-notes.md` line 18 now reads: panel "validated identically (strict
  digits, and rejected above MAX_SAFE_INTEGER so the accepted range is where node
  `parseInt` == python `int`)". This matches observed behavior exactly. The
  round-2 overclaim ("no lenient node `parseInt`") is gone; the wording is now
  accurate and scoped. **No overclaim.**

## Tree hygiene

Scratch node revert restored byte-identically (range-check present exactly once).
All `/tmp` scratch dirs removed. The AF working-tree state
(`refuter_profiles.js`/`.py` modified; `refuter-skill-format.sh` untracked) is the
pre-existing uncommitted phase-AF work, not introduced by this review.

---

## Verdict

Both round-2 remediations hold. The `panel > 2^53` `int` vs `parseInt` divergence
is closed in BOTH runtimes by a symmetric MAX_SAFE_INTEGER reject, verified exact
at the boundary (…991 accept / …992 reject, both signs). The proof's range-check
is load-bearing (RED when the node check is removed). No surviving node-vs-python
parser divergence found across boundary, encoding, and structural adversarial
inputs. The parity-notes claim is accurate. Suites and proof all green.

VERDICT: SOUND
