# Refutation attempt — phase RP ("Panel verdict policy"), round 2

Actor: adversarial refuter (did NOT do this work). Repo: /home/hamid/Téléchargements/heartbeat

## Claim under test

Round 1 found a real hole: on the panel PASS path, per-panelist findings were joined with
an unconditional `[panelist i/N] ` prefix, so N empty-findings panelists produced a
prefix-only ~48-char string that cleared the ≥40-char substance floor → an evidence-free
pass got certified (Rule 6 violation) in BOTH runtimes; the single-verdict path correctly
blocked the identical refuter.

Author's fix: only a panelist whose findings are non-empty after strip/trim contributes a
labelled `[panelist i/N] <text>` entry, so boilerplate prefixes can never satisfy the floor.
A new proof scenario `ec` ({"refuted":false,"findings":""}) asserts an all-clear-but-
evidence-free panel does NOT pass on both runtimes.

## What I verified (real commands, both runtimes)

Fix confirmed present in both runtimes:
- `py/src/heartbeat/executor.py:353-357` — `fi = (ri.get("findings") or "").strip(); if fi: findings.append(f"[panelist {i+1}/{panel_n}] {fi}")`
- `plugin/templates/hb-exec.js:371-374` — `const fi = (ri.json.findings || '').trim(); if (fi) findings.push(...)`
The <40-char floor + artifact-persist + distinct-actor pass block (executor.py:371-392,
hb-exec.js:389-397) is shared with the single-verdict path and is unchanged by the fix.

Drove the REAL executor (`hbpy exec run` and `node hb-exec.js run`) with a deterministic
stub backend (no model/network), panel:3 refute_if=majority, one temp project per case:

1. **ORIGINAL EXPLOIT reproduced against current code** — all three panelists return
   `{"refuted":false,"findings":""}` (ec,ec,ec). Result: **OPEN (phase not completed) in
   BOTH py and node.** Aggregate is clear but the joined findings string is empty → the
   <40 floor blocks with `review_error … no substantive findings`. The round-1 hole is
   closed on both sides.

2. **Partial evidence** — (real,ef,ef), majority ⇒ clear. Result: **DONE in both**; the
   stored `GATE_P0.attempt.md` contains ONLY the one real `[panelist 1/3] …` entry (no
   empty-panelist prefixes). Sensible and honest: there IS substance, so a pass is correct
   and the artifact reflects real evidence. The distinct-actor pass path (accept_review /
   hbAs(refuterActor)) is exercised end-to-end and accepts.

   **Sub-threshold single finding** — one 5-char finding + two empty (short,ef,ef): joined
   `[panelist 1/3] 12345` ≈ 20 chars < 40 → **OPEN in both.** No sneak-through.

3. **REFUTED path / aggregation unchanged** — any 1/3 true ⇒ OPEN (refuted); all 3/3 true
   ⇒ OPEN; majority with a non-bool panelist (fail-closed) ⇒ OPEN. All correct in both
   runtimes. `aggregate_verdict`/`aggregateVerdict` are byte-parity (`parity.sh
   panel-aggregate` ✓) and untouched by the fix.

4. **Teeth are load-bearing** — reverted the fix (restored the unconditional prefix) in
   BOTH `executor.py` and `hb-exec.js`, re-ran `refuter-panel.sh`: **RED**, failing exactly
   on line 115 (`ec,ec,ec must NOT certify an evidence-free pass`), py first. Restored both
   files byte-exactly (`diff -q` clean) → proof GREEN again (REFUTER-PANEL-OK). The `ec`
   scenario genuinely guards the round-1 hole; without it the regression goes undetected.

5. **Proof timing / hermeticity** — `refuter-panel.sh` runs in **4.26s** (< 5s
   GATE_TIMEOUT_S budget, though not with a wide margin). Hermetic: unsets HB_DIR/DAG_FILE/
   EVENTS_FILE/HB_REFUTER, works in `mktemp -d` with `trap … EXIT`, HB_NO_GIT=1, leaves no
   stray files in the repo tree.

6. **Parity of the whitespace edge** — panelists returning `{"findings":"   "}` (ws,ws,ws):
   **OPEN in both.** py `.strip()` and node `.trim()` collapse whitespace-only to empty
   identically, so a padded-whitespace finding cannot satisfy the floor on either side. No
   divergence.

7. **Distinct-actor on a panel pass** — the panel pass reuses the single-path block that
   sets `HB_ACTOR = worker:refuter` (executor.py:272,382 / hb-exec.js:278,397), distinct
   from the worker actor that executed the task; review_policy's self-review guard is
   satisfied by construction, and scenario 2a's DONE confirms the pass was accepted through
   it, not around it.

Suites all green with the fix in place: node `tests/run-tests.sh` = 374 passed / 0 failed
(incl. T148.1/T148.2), python `pytest` = 96 passed, `tests/parity.sh` = node ≡ python.

## Remaining observations (not certification holes)

- **Sub-40 substantive finding + prefix crosses the floor.** A single panelist with a
  ~30-char REAL finding gets a 15-char `[panelist i/N] ` label → joined 45 chars → passes,
  where the same 30-char finding on the single-verdict path would be blocked at <40
  (verified DONE in both runtimes). I do NOT count this as a hole: it is a real panelist
  producing real (if terse) evidence, the label is legitimate provenance, and the stored
  artifact is genuine — materially unlike the round-1 empty-prefix padding. The 40-char
  floor is a coarse anti-rubber-stamp heuristic, not a semantic quality bar. Worth a
  one-line note only if the author wants the panel floor to apply to per-panelist text
  rather than to the labelled aggregate.
- **Doc scope (not an overclaim).** `docs/dev-tests.md` T148 (line 167) and
  `planning/parity-notes.md` (line 19) describe majority/any/all aggregation + fail-closed
  but do not mention the evidence-free-pass guard the new `ec` scenario now enforces.
  Neither claims a guarantee the code lacks (no overclaim); they just under-describe the
  proof's expanded coverage. The proof's own header (lines 113-115) documents it.

## Verdict

The round-1 hole is genuinely closed in both runtimes. The fix is minimal and does not
touch the refuted path or the aggregation contract; fail-closed and distinct-actor still
hold; the new `ec` teeth are load-bearing (RED on revert, GREEN on restore); the proof is
hermetic and within the gate budget; py `strip()` and node `trim()` stay in parity on
whitespace-only findings. The only notes are a benign heuristic edge (a genuinely
substantive but terse single finding + its provenance label) and a minor doc-scope gap —
neither is a certification hole.

VERDICT: SOUND
