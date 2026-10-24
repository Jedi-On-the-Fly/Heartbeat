# Plan refutation — Wave 3 "discovery" (DS1 / DS2), ROUND 7 (final narrow confirm)

Refuter: round-7 verification of the round-6 folds (F27, M1) against
/home/curtism/Drums/lab/heartbeat/.hb/dag.json. Tree at **7cc9595** (same commit rounds
4–6 probed), `git status` clean; `.hb/dag.json` is untracked, so the diff-read is against
round 6's verbatim quotes (ds-plan-refutation6.md). Repo tree and live `.hb/` untouched;
lint/audit ran against a COPY in mktemp (removed after).

## 1. F27 — GATE_DS2 P1's subjects carry both files. LANDED.

The subjects array, verbatim (dag.json, GATE_DS2 → review → constraints → P1):

    "subjects": [
      "plugin/skills/heartbeat/SKILL.md",
      "docs/howto/plan-to-the-horizon.md",
      "docs/dev-tests.md",
      "docs/howto/re-verify-completed-gates.md",
      "docs/howto/block-pushes-on-failing-gates.md",
      "docs/howto/park-a-phase.md",
      "docs/dev-plugin.md",
      "docs/dev-python.md"
    ]

The first six are round 6's prior six, same order; `docs/dev-plugin.md` and
`docs/dev-python.md` are appended — exactly the two paths R6-F27 required. Both files
exist in the repo. The claim now has subject coverage for every file whose rows' truth
it pins (dev-tests' T179 row, dev-plugin's parked-pending-regate sentence, dev-python's
park row). The F5/F17/F24/F25/F27 class is closed at every constraint.

## 2. M1 — the `_meta.design` clause. LANDED, and the new wording is true.

The clause, verbatim (end of `_meta.design`):

    "so GATE_DS2 pins prose-check over the 11 named docs (parity-notes.md is owned by
    ds1c; no suite prose-checks it — its truth is held by GATE_DS1's review)."

Checked against the repo today:

- **"owned by ds1c"** — ds1c's description: "Append the 'replan contract' paragraph to
  planning/parity-notes.md". True.
- **"no suite prose-checks it"** — T93.1 (tests/run-tests.sh, grp T93) globs
  `find "$D"/docs -name "*.md"` plus root `*.md` minus CLAUDE.md; planning/ is outside
  it. A repo-wide grep of tests/, py/tests/ and docs/howto/gate-examples/ finds exactly
  one file referencing parity-notes: doc-fixture-count.sh (T137.1), which checks the
  audit-fixture COUNT stated in the doc against what parity.sh iterates — a currency
  check, not a prose check. True. (This is the honest replacement for round 5's false
  "checked by the suites' existing prose floor".)
- **"its truth is held by GATE_DS1's review"** — GATE_DS1's review prompt (d) requires
  "desc-only and timeout_s-only → each must NOT drift and parity-notes records the
  limit", and P2's claim pins "(the recorded honest limit)". GATE_DS1 is the exit gate
  of the phase containing ds1c. True.

## 3. The folds introduced nothing else

**Diff-read vs round 6's quotes.** Three textual deltas, no more:
1. GATE_DS2 P1 subjects: +2 entries (above). The claim text is byte-identical to the
   round-6-verified F26 claim; the violation line unchanged.
2. `_meta.design`: only the final parenthetical changed; the "11 named docs" half and
   everything before it unchanged.
3. `_meta.refutation_rounds`: the round-6 ledger entry appended — the fold's own
   bookkeeping (every round 1–6 now has an entry), and its findings text accurately
   describes F27 and M1. Not a defect.

Everything else matches round 6's verified text verbatim where quoted (P3's nine
subjects, ds2c's re-spec clause, ds1a/ds1b's l.203/l.232 naming, "in ds1b's change",
the PROTOCOL.md regeneration note, ds2w's 11-path cmd with `^ALL-PROSE-OK:11`).

**Coherence.** P1's claim/subjects now correspond one-to-one: SKILL.md + how-to
(anchoring + prose), the three re-specified how-tos, dev-tests.md (T184 row + T179 row
+ prose), dev-plugin.md and dev-python.md (the two re-specified rows). The design
clause parses as one sentence and no longer asserts suite coverage it doesn't have.
Envelope untouched: subjects are not the measured claim; the claim stays at the
round-6-measured 85 words, within the 141-word house maximum.

**Lint + audit, both runtimes, mktemp copy.**
- Node: `✓ DAG valid (0 warning(s))` rc 0; `✓ gates look behavioural (0 warning(s))` rc 0.
- Python (heartbeat.cli): identical text, rc 0 / rc 0.
- Parity-idiom JSON projections byte-identical: audit `[0,0,[]]` ≡ `[0,0,[]]`,
  lint `[]` ≡ `[]`.

## 4. Checklist — F1–F27 / M1 against the operative dag text

- F1 spec-first tripwire rescope — ds1a (drift RED TODAY spec) + ds1b (implement). RESOLVED.
- F2 rebuild modulo last_updated — ds1a append case + GATE_DS1 P1 claim. RESOLVED.
- F3 ds2z outcome criterion — present in GATE_DS2 criteria. RESOLVED.
- F4 ds2w covers ds2c-touched docs — all 11 in ds2w's cmd. RESOLVED (widened by F21).
- F5 subjects carry the runtime files claims pin — GATE_DS1 P1/P2 subjects. RESOLVED.
- F6 unstarted-silence on PROBLEMS/exit, never zero notes — ds1a + P2 claim. RESOLVED.
- F7 T162.5/.6 pre-existing flake — recorded, explicitly not wave scope; no dag text owed. CLOSED.
- F8 consecutive-pin (launder-proof) — ds1b CORE "any ADJACENT difference"; ds1a launder case. RESOLVED.
- F9 bare/import passes never pins — ds1a + ds1b (staleRearm precedent). RESOLVED.
- F10 identity = ordered (id,cmd) byte-exact; removal drifts; desc/timeout_s honest limit — ds1a/ds1b/P2/ds1c/ds2b. RESOLVED.
- F11 severity doctor PROBLEM exit 1 — ds1a/ds1b/P2. RESOLVED.
- F12 sweep counts drifted FAILING; tick wakes — ds1b SWEEP/TICK; reason-key half superseded by F16's new key, carried in text. RESOLVED.
- F13 absolution (completed cycle cures) — ds1a (cure) + ds1b (ii). RESOLVED.
- F14 sweep exclusion + pending-regate precedent + re-specified checks — ds1b SWEEP (six checks, F21-widened). RESOLVED.
- F15 park silences nothing — ds1a/ds1b/P3 (drift AND pending regate). RESOLVED.
- F16 new key criteria_drift, honest action text — ds1b TICK ("never reuse unsanctioned_drift"). RESOLVED.
- F17 py twins in subjects — doctor.py in P2; gate.py/tick.py in P3 post-split. RESOLVED.
- F18 staleness owners — ds1c (parity-notes), ds2b (tripwire section), ds2c (how-tos + dev tables), ds2w:11. RESOLVED.
- F19 sanction/absolution gate-scoped — "FOR THAT GATE" in ds1b (i)/(ii); ds1a cross-gate case. RESOLVED.
- F20 cycle-anchored absolution — all four sites (ds1a, ds1b, P2, prompt (e)); round 5 verified. RESOLVED.
- F21 sixth check + four doc surfaces + ALL-PROSE-OK:11 + criteria-pinned walk — ds1a/ds1b/ds2w/ds2c. RESOLVED.
- F22 fourth protocol surface + two stop-lists — ds1b (hb-exec.js table, heartbeat-detect.sh, mcp_server.py) + P3. RESOLVED.
- F23 P2 split, teeth renumbered P4 — GATE_DS1 carries P1–P4. RESOLVED.
- F24 GATE_DS2 P1 gains the rewritten how-tos — claim + subjects carry all three. RESOLVED.
- F25 P3 subjects gain the three check-hosting files — nine subjects present. RESOLVED.
- F26 ds2c re-specifies the three rows; P1 owns their truth — ds2c clause + P1 claim. RESOLVED.
- F27 P1 subjects gain dev-plugin.md + dev-python.md — verified in §1. RESOLVED.
- M1 `_meta.design` prose-floor clause honest — verified true in §2. RESOLVED.
- Round-4 minors (ds2w desc honest; HB_ACTOR limit in ds1c + ds2b) and round-5 minors
  a–d — all present in the operative text. RESOLVED.

No prior finding remains unresolved in the dag text.

---

Both round-6 folds landed exactly as specified, the reworded design clause is true
against the repo today, the folds introduced no new defect, lint and audit are clean and
byte-identical across both runtimes on a mktemp copy, and every finding from rounds 1–6
is resolved in the operative text. The wave has converged.

SOUND
