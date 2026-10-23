# RG2 refutation (all work in mktemp fixtures under /tmp/rf; repo tree untouched)

## Suites (shipped tree)
- bash tests/regate-rearm.sh -> MATRIX/SUCCESS/STALE/CYCLE/DOCTOR/DIAGNOSE/RESUME-OK, REGATE-REARM-OK; --selftest -> REGATE-REARM-SELFTEST-OK
- bash tests/regate-fail-closed.sh (+ --selftest) -> REGATE-FAIL-CLOSED-OK / -SELFTEST-OK
- pytest -k regate -> 21 passed; bash tests/parity.sh -> PARITY OK (node == python)
All green. The defects below are ones the green suites do not catch.

## Findings (reproduced)
F1 (P1/P4) Thin-artifact bar differs per runtime. Node trims with JS String.trim (strips U+FEFF, not U+0085/U+001C-1F); Python uses str.strip (the reverse). Same fixture bytes, rearm on a pending GATE_B:
  - 39 visible chars + U+FEFF: node "too thin (39 chars)"; PYTHON ACCEPTS (rearm stored).
  - 30 chars + 12x U+0085: PYTHON "too thin (30)"; NODE ACCEPTS. Same with 12x U+001F.
  So python accepts a 39-trimmed-char artifact (node's definition) and node accepts a 30-char one (python's). doctor's thin check (hb.js:387 / doctor.py:129) uses the same two trims, so the doctor lines diverge too. parity.sh has no case at this boundary.
F2 (side, exploitable) Hand-clearing the regate bypasses the entire rearm bar and nothing notices. Fixture: b1 done, GATE_B det-passed, `regate GATE_B` declared (alice), criteria edited, then python rewrote dag.json gates.GATE_B.regate.pending=false by hand. Result: gate.sh evaluates again, `hb review GATE_B pass --artifact rv.md` ACCEPTED, 0 gate_rearmed events, no reviews/GATE_B.regate.md; node doctor, python doctor, node hb-lint and python lint all say healthy. doctor's marker-sync (hb.js:399 / doctor.py:140) only fires when the dag marker is ABSENT; marker present with pending:false and an unanswered gate_regated in the log is silent. Different actor, evidence, audit, sha pin: all skipped by one JSON edit.
F3 (bar weakness) Evidence need not be fresh or a refuter's attempt: `--artifact .hb/reviews/GATE_B.regate.md` (the previous rearm's own evidence) and `--artifact .hb/dag.json` were both accepted on later rearms (anchor = the gate id appears). Each rearm overwrites the single reviews/<G>.regate.md, so older gate_rearmed pins can no longer be re-verified (doctor checks only the last event).
F4 (minor) Audit runs on a dag read BEFORE the write lock (hb.js:1392, cli.py:201); the in-lock re-read only rechecks pending, then writes dag2 — a criteria edit landing between audit and lock is rearmed unaudited. Not timed/reproduced, reasoned from code.
F5 (minor) python executor refuted-branch writes review_failed via st.mutate directly (executor.py ~546, refuse() ~311), guarded by regate_blocks (pending) but not stale_rearm; a declare+rearm completing during a refuter dispatch could land a review_failed in the stale window. Not reproduced.
F6 (cosmetic) Node rearm re-encodes the artifact via utf8 string (invalid bytes become U+FFFD) while python stores raw bytes; the pin still matches the stored bytes in each runtime, so G1 holds.

## What held
- Race (G2): 6 concurrent rearms (distinct artifacts) on node: rcs 1 1 1 0 1 1; on python: same; 4-way mixed node/python race: exactly one rc 0. Each: 1 gate_rearmed event, 1 dag rearm record, sha256sum(stored file) == event sha == dag sha. Losers: "no pending regate". Sequential second rearm refused (also case-varied/space-padded actors).
- G1: node and python, plus BOM/CRLF/invalid-utf8 artifact: stored-bytes hash == event == dag on each runtime; doctor clean immediately after (both). One-byte overwrite, emptied and deleted evidence each flagged by both doctors; pending shows as a note (healthy exit); restored file clears.
- Matrix: no pending, unset HB_ACTOR, ALICE/" alice "/Alice vs declarer alice, missing file, 9-char, citing nothing, hollow revision ('true' gate): all refused on both runtimes with pending untouched, no event, no stored file (suite + my probes).
- Stale-pass laundering (P2): det pass recorded, declare, edit, valid rearm: node `review pass|fail|free` on GATE_B and phase id B, python CLI, and accept_review called directly: all refused, 0 review events. `hb import` (node) after rearm wrote bare gate_passed (actor unknown, no criteria/runtime): verdicts still refused (node and python); an accepted reviewed gate with rearm newer than last provenanced pass: both doctors flag STALE, import does not clear it, a fresh `gate.sh` (node- or python-written pass, cross-runtime) clears it. Evaluation truly runs after rearm (revised criterion executed).
- G3: synthetic event orders CVR CRV VCR RCV VRC RVC CRC CVC (+ other-gate rearm and review_passed noise): py review_cycle_full.start == _cycle_start, review_cycle.recorded agrees with review_cycle_full, node reviewCycle.start/recorded identical on all 13 sequences. grep shows constraints.py has the single start scan (line 40); hb.js 667 the single node one.
- Diagnose (P3): bare, gate_blocked and review_stuck each print the --rearm recovery when pending (stale gate_failed / review_failed planted); in the post-rearm stale window it routes to "re-run the gate", never to a refused verdict; marker-divergence fixture flagged (suite).
- G4: --selftest prints REGATE-REARM-SELFTEST-OK; all 7 marker names present in hb.js, cli.py, doctor.py, review_policy.py, constraints.py, hb-exec.js, executor.py.
- Executors in the stale window: RESUME-OK for both (suite); not re-derived.

## Per-id answers
P1: VIOLATED — python accepts a 39-trimmed-char artifact (39 chars + U+FEFF) that node refuses; node accepts a 30-char + 12x U+0085 artifact python refuses (Fixture f39bom / f30nel; `HB_ACTOR=bob hb regate GATE_B --rearm --artifact ev.md` -> py "🔁 rearm GATE_B", node "too thin (39 chars)").
P2: NOT-REPRODUCED — stale verdicts (pass/fail/free, node CLI, py CLI, direct accept_review, phase-id alias) all refused; import's bare pass neither unlocks nor clears doctor; fresh node/python pass unlocks; pre-declare constraint set not consulted (order probe).
P3: NOT-REPRODUCED — pending note, rot (missing/empty/1-byte), stale-accepted, marker-sync, explicit+inferred diagnose and gate_blocked/review_stuck routing all behave on both runtimes. (Side finding F2: a hand-set pending:false with marker present is silent in doctor/lint — outside the listed states, reported under the triage rule.)
P4: VIOLATED — same fixture bytes decided differently by the two runtimes at the thin-artifact boundary (F1), with doctor's thin check diverging likewise; parity.sh passes only because it never probes that boundary.
G1: NOT-REPRODUCED — triple sha agreement on node and python incl. BOM/CRLF/invalid-UTF-8 input; doctor clean right after rearm on both.
G2: NOT-REPRODUCED — 6-way node, 6-way python and 4-way mixed races: exactly one winner, one event, one dag record, stored sha == pin; sequential repeat refused.
G3: NOT-REPRODUCED — 13 event orders compared py vs node, single start computation in each runtime.
G4: NOT-REPRODUCED — bash tests/regate-rearm.sh --selftest prints REGATE-REARM-SELFTEST-OK on the shipped tree; markers present.

## Verdict
UNSOUND (REFUTED): F1 is a reproduced parity/bar violation (P1, P4) and F2 is an exploitable side finding (one hand edit of regate.pending skips the whole rearm bar, silent in doctor and lint, review pass then accepted).
