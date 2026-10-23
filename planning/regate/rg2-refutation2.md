# RG2 refutation, round 2 (fixtures under /tmp/rf2; repo tree untouched)

## Suites (shipped tree)
regate-rearm.sh: MATRIX/SUCCESS/STALE/CYCLE/DOCTOR/DIAGNOSE/RESUME/TRUTH-OK, REGATE-REARM-OK; --selftest REGATE-REARM-SELFTEST-OK;
regate-fail-closed.sh + --selftest OK; pytest -k regate (py/.venv) 23 passed; parity.sh PARITY OK. All green.

## Round-1 fixes verified by running
- U+FEFF / U+0085 / U+001F / NBSP / ZWSP / U+2028 / VT+FF boundary artifacts: node and py now give the SAME verdict on identical bytes (ASCII trim; the non-ASCII chars count as content, both runtimes). 39 chars + CRLF refused by both.
- Hand-clear (pending=false), deleted marker, cleared + fabricated rearm record (zero sha), marker removed with plant: node AND py `review pass` refused ("event log attests an UNANSWERED revision"); doctor flags cleared marker / fabricated record / missing marker. No verdict accepted without a gate_rearmed event via the CLI.
- Legit path not over-refused: rearm on node|py x review on node|py, all four combos, review pass accepted after fresh pass + constraints; second declare->rearm cycle (changed criteria) works; double declare refused; both doctors healthy.
- Caveat (not an exploit in the model): a forged `gate_rearmed` EVENT appended by hand to events.jsonl plus a matching stored file/sha and dag record is accepted by doctor and the guard (log forgery is outside the "log is truth" threat model; same as forging any event).
- Design observation: regate/rearm on an ALREADY ACCEPTED gate leaves review_passed standing (projection unchanged); after the fresh det pass no review is owed ("not awaiting review"), so the revised criteria are never re-reviewed. Pre-existing projection semantics; doctor's STALE problem clears on the fresh pass. Noted, not counted.

## NEW defect (reproduced): thin boundary still diverges on astral characters
substantiveLen (hb.js:814) counts UTF-16 code units (JS .length); substantive_len (state.py:219) counts code points. Any non-BMP char (emoji) counts 2 in node, 1 in python.
Fixture: 30 ASCII chars + 5x U+1F600 (e_emoji), same bytes, rearm on pending GATE_B by bob:
  node -> "rearm GATE_B (by bob): evidence stored" (rc 0, counted 40)
  py   -> "regate --rearm: artifact evidence.md is too thin (35 chars)" (rc 1)
`review pass` with the same bytes: node proceeds past the thin check (refuses later on missing answer lines); python: "artifact f.md is too thin (35 chars)". Doctor thin checks and recorded artifact_chars use the same two functions, so they diverge identically. Invalid-UTF-8 probes (truncated sequences, 0xff) agreed. tests/regate-rearm.sh `truth` and parity.sh never use a non-BMP char. The round-1 fix claimed "same bytes, same verdict" for every artifact thin check; it holds only for BMP text.
Fix: count code points in JS (Array.from / [...str].length) or UTF-16 units in py, and add an astral case to the truth case.

## Per-id answers
P1: VIOLATED — 30 ASCII + 5x U+1F600 evidence: `HB_ACTOR=bob hb regate GATE_B --rearm --artifact evidence.md` node accepts (rc 0), python refuses "too thin (35 chars)"; the refusal matrix otherwise holds (suite MATRIX-OK + my re-runs).
P2: NOT-REPRODUCED — stale-pass/verdict refusals, hand-clear, fabricated record, marker-delete variants all refused on node and py (t2/t4 probes); TRUTH-OK, STALE-OK, CYCLE-OK green.
P3: NOT-REPRODUCED — doctor flags cleared marker, fabricated record, missing marker, rot; pending note present; DOCTOR-OK/DIAGNOSE-OK green; round 1 verified diagnose routing.
P4: VIOLATED — same fixture bytes (astral-char artifact) decided differently by node (accept) and python (refuse), doctor thin check and artifact_chars diverge likewise; parity.sh passes only because it has no non-BMP case.
G1: NOT-REPRODUCED — round 1 triple-sha agreement + SUCCESS-OK green; not re-attacked beyond rearm runs (doctor clean after rearm in t4, both runtimes).
G2: NOT-REPRODUCED — round 1 races (6-way node, 6-way py, mixed) unchanged; the audit moved inside the lock; sequential repeat refused (double declare / no-pending probes).
G3: NOT-REPRODUCED — round 1 13-order comparison; CYCLE-OK green; cycle logic untouched by the fixes (hb.js reviewCycle single start scan seen).
G4: NOT-REPRODUCED — bash tests/regate-rearm.sh --selftest prints REGATE-REARM-SELFTEST-OK incl. new s10 (log-truth strip).

## Verdict
REFUTED
