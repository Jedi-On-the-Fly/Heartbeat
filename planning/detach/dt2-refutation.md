# GATE_DT2 refutation — whole-feature + docs review of the detach wave

Refuter: adversarial reviewer (strong read; unbound profile). All probes ran in mktemp fixtures
and repo COPIES; the repo tree and its live `.hb/` were never touched. Fixture pattern: the
detach-surfacing two-phase dag (P → GATE_P → D → GATE_D), bootstrapped per fixture.

## Suites (integration floor)

| Suite | Result |
|---|---|
| `bash tests/detach-surfacing.sh` | MARKER/CLEAR/QUIET/DOCTOR/AUDIT-OK → `DETACH-SURFACING-OK`, exit 0 |
| `bash tests/detach-surfacing.sh --selftest` | `DETACH-SURFACING-SELFTEST-OK`, exit 0 |
| `bash tests/detach.sh` (+ `--selftest`) | `DETACH-OK` / `DETACH-SELFTEST-OK`, exit 0 |
| `bash tests/regate-surfacing.sh` (+ `--selftest`) | `REGATE-SURFACING-OK` / `REGATE-SURFACING-SELFTEST-OK`, exit 0 (report code touched again — unregressed) |
| `cd py && PYTHONPATH=src .venv/bin/python -m pytest -q` (full) | 171 passed |
| `bash tests/parity.sh` | `✅ PARITY OK — node ≡ python` (incl. detach:lint-malformed, detach:lint-reserved, detach:cross with the changed-base and reattach assertions) |
| `bash tests/run-tests.sh` (full node suite) | 472 passed, 0 failed, exit 0 — ALL GREEN; GROUPS-RAN 183, GROUPS-SKIPPED 0; T183.1/T183.2 registered and green, T182/T183 in GROUPS-PASSED |

Env-hygiene header: `diff` of the `Env hygiene:`…`unset HB_DIR PROJECT_DIR GATE G DAG_FILE EVENTS_FILE`
block between `tests/detach.sh` (wave 1) and `tests/detach-surfacing.sh` → HEADERS-IDENTICAL (verbatim).

## Criteria sanity (falsification checklist)

- dt2x/dt2y: the markers (`DETACH-SURFACING-OK`, `DETACH-SURFACING-SELFTEST-OK`) print only as the
  LAST line after every case/strip ran; `fail()` exits 1 before any marker; `…SELFTEST-OK` does not
  contain the substring `DETACH-SURFACING-OK`. A red run cannot match.
- dt2d: a greps-only currency floor, but honestly LABELED as such ("the review's P2 does the deep
  read") — and the deep read below found the docs substantive, with one overclaim (P2).
- dt2p: the three greps hit real executable case labels in tests/parity.sh (`detach:cross` l.199,
  `detach:lint-malformed` l.150, `detach:changed-base` l.202 — the changed-base assertion inside
  detach:cross, as parity-notes says) AND the criterion runs the full parity suite: not stub-matchable.
- dt2n/dt2q: run the real suites. Real runtime exercised throughout; nothing mocked.

## P1 — surfacing loud/correct/text-only/non-invasive (manual, independent of the proof script)

- Detached fixture, both runtimes, one phase line:
  node: `▶️  D dependent — 0/1  [gate: GATE_D]  ⟂ detached from GATE_P (by alice: volumes were replaced)`
  python: same marker text. Gate, actor, reason all present.
- `--json`: `grep -i "detached from|⟂"` on both runtimes' JSON → no match (rc=1). Structural check:
  hb-report.js exits at the `asJson` branch (l.133) BEFORE the text render, and its `phases` array is a
  derived projection (`{id,title,done,total,status,gate_exit,parked}`) — raw detach fields cannot leak.
- Reattach: marker gone on both runtimes (grep rc=1).
- Never-detached: QUIET-OK (proof) — no "detach" in either report.
- Doctor live detach: NOTE (`⚠ D is detached from GATE_P … re-audit before relying on the order`),
  exit 0 on both runtimes with the note as the only finding (node: "healthy (1 note(s))").
- Anchor-missing suffix, direction A (both fixtures: no event at all; reattached-then-fields-restored
  fail-open), direction B (re-lock): DOCTOR-OK in the proof; divergence fixtures rebuilt manually for
  the G2 strip runs — original doctors exit 0 on all of them.
- Audit ruleset untouched: independently replicated — detached vs field-stripped fixture,
  `node hb-audit.js` outputs byte-identical, `hb audit` (python) outputs byte-identical. (hb-audit.js
  is also not in the phase diff at all.)

**P1 holds — not reproduced.**

## P2 — docs deep read (skeptic mode, every command run verbatim)

Everything below was executed against mktemp fixtures, node AND python:

- Verbs + refusal ladder: no-args usage, missing reason, missing/`unknown` `HB_ACTOR`, unknown id,
  already-null `gate_entry` (P), already-detached (with the reattach routing), completed phase
  (`detach: P is already complete — a satisfied dependency has nothing to unlock`), unsafe id
  (`../evil` → "not usable as an anchor file name") — all exactly as documented, both runtimes.
  Python arg style `--reason` vs node trailing words: as documented (the park/regate precedent).
- Reattach brick: `detached_from` pointing at a gate that is defined but no phase's `gate_exit` →
  refused with the documented "would lock D forever (the lint 'phase locked forever' brick)" on both
  runtimes; deleting the gate flips the message to "no longer defined". Round-trip restore verified.
- Gate-id trap: on an A→B→C chain, `detach GATE_B` (meaning to cut C's entry) detached B from GATE_A
  — the WRONG phase, exactly the documented trap.
- Weasel warning arms: live `gate_failed` warns; `review_failed` followed by a later `gate_passed`
  (the refuted steady state) still warns; a clean detach does not warn — identical warning text on
  both runtimes. (Full matrix: WEASEL-OK in tests/detach.sh.)
- Parked detach succeeds and unlocks nothing until `unpark` (ready list checked before/after);
  det-passed/review-owed phase (GATE_D passed, review pending, phase not complete) detaches — both
  as documented.
- Doctrine line: present in dev-plugin.md as a PROHIBITION — "THE DOCTRINE: never detach to escape a
  blocked or revising predecessor gate — that is auto-weaken by topology" — not softened into permission.
- Report marker + doctor notes are in the RUNTIME docs (dev-plugin.md Detach paragraph + doctor row;
  dev-python.md verb row), not just dev-tests.md — the regate-wave P2 lesson is answered.
- dev-tests.md: T182/T183 rows present and accurate against the scripts.
- parity-notes: the three cases exist in tests/parity.sh; the regex-`$` story is accurate — both
  lints use exact equality + `startsWith`/`startswith`, no regex (hb-lint.js l.150, lint.py l.124).
- Backticked `hb` sweep over all four changed docs: every `hb <sub>` phrase (audit, bench, changed,
  constraints, detach, diagnose, doctor, done, evidence, exec, fail, gate, init, mcp-serve, next,
  park, protocol, ready, reattach, rebuild, refute-prompt, refuters, regate, report, review, reward,
  start) names a registered python subcommand (add_parser list + the start/done/fail/heartbeat loop).
- Named symbols in dev-python.md all exist: `cli._detach_warn`, `lint._check_detach`,
  `anchors.write_anchor(…, extra=…)`, `anchors.changed()` with the stamp check, `report.render`.

### FINDING (P2): dev-plugin.md documents a doctor loudness that does not exist — the stamp-mismatch arm

dev-plugin.md (Detach paragraph, l.152): "…STAMPED with `detached_at` **(a stamp-mismatched or
missing anchor reads as missing: `_start` fallback, said aloud by doctor)**".

Reproduction (both runtimes): detach D in a fixture, then edit `.hb/anchors/_detach_D.json`'s
`detached_at` to `1999-01-01T00:00:00Z` (a stale/late write — exactly the state the stamp exists
to catch):

- `node .hb/hb.js changed GATE_D` → `hb changed: no entry anchor '_start' for GATE_D …` — the base
  DID widen to `_start` (python `hb changed` identical). The "reads as missing: _start fallback"
  half is true.
- `node .hb/hb.js doctor` → `⚠ D is detached from GATE_P (…) — … re-audit before relying on the
  order` — **no suffix, nothing about the widening**. Python doctor identical. The doctor's suffix
  keys on anchor EXISTENCE only (`readAnchor(…) ? '' : ' (no detach anchor — change reports widen
  to _start)'`, hb.js l.419; `_anch.read_anchor(…)`, doctor.py l.158); neither doctor function
  contains any `detached_at`/stamp comparison (grep: zero hits in both doctor bodies).

So in the stamp-mismatch state the system silently widens change reports while the doc tells the
operator doctor would say so — loudness claimed, not shipped. The hb.js source comment
(l.893–895) scopes "doctor's live-detach note says so" to the anchor-WRITE-FAILURE (missing) case;
the doc hoisted it over the stamp-mismatch case too. The shipped code matches the DT2 spec/P1
("the anchor-missing suffix when it applies") — the DOC overclaims, which is precisely the
charter's "a documented … behavior that does not exist in code is a finding", and it touches the
wave's own doctrine that the loudness IS the feature.

Minimal repair: either (a) scope the doc parenthetical — "…reads as missing: `_start` fallback;
a MISSING anchor is said aloud by doctor" — or (b) make both doctors compare the anchor's
`detached_at` to the phase's and extend the suffix (then mirror node ≡ python and add the fixture
to tests/detach-surfacing.sh).

## G1 — the two loud markers compose (manual composed fixture)

Fixture: `regate D` (pending on GATE_D, by bob) + `detach D` (by alice).

- One unbroken line per runtime (grep -c = 1), regate BEFORE detach on both
  (node indices 41 < 104; python 40 < 103):
  `D dependent — 0/1  [gate: GATE_D]  ⛔ revised — rearm pending (by bob: criteria premises changed)  ⟂ detached from GATE_P (by alice: volumes were replaced)`
- Full payloads: both actor+reason pairs present on the line, both runtimes.
- `--json` in the composed state: grep for both markers' text (and both glyphs) → no match, both runtimes.
- Independent clearing: `reattach D` → ⛔ intact, ⟂ gone (both runtimes); hand-removing only
  `gates.GATE_D.regate` on a copy → ⟂ intact, ⛔ gone (both runtimes). Single-state fixtures show
  only their own marker (these clears are those fixtures).

**G1 holds — not reproduced.**

## G2 — strip-clean guard classes (copies only)

Marked-line inventory: `detach-guard: report` = exactly the emit/decide lines (hb-report.js l.144
detachNote + l.149 call; report.py l.85 `_dp` fetch + l.86 marker append). `detach-guard: doctor` =
exactly the three notes per doctor (hb.js l.419–421; doctor.py l.158–160). The structural lines
(evsD/liveD scan, `live_d` build, `from . import anchors`, `phases_raw`, loop headers, `let dn`)
carry NO guard marker — verified by grep.

Strips (sed '/detach-guard: report/d', '/detach-guard: doctor/d' on COPIES):
- Parse: `node --check` passes on both stripped node files; stripped report.py + doctor.py import
  cleanly (`import heartbeat.report, heartbeat.doctor` on the stripped src copy).
- Behavior on a composed fixture (regate pending + detach + state drift): stripped renderers emit
  no ⟂ (grep rc=1, both runtimes); stripped report == original report minus exactly the marker
  substring (python equality check: True, both runtimes); stripped doctors exit 0 with zero detach
  output on the live fixture AND all three divergence fixtures (A1 no-event, A2 fail-open restore,
  B re-lock), both runtimes; non-detach findings (the drift note + the regate pending note)
  byte-for-byte unchanged by the strip (list equality: True, both runtimes).
- `--selftest` printed its OK with none of the violation conditions holding.

Observation (teeth gap, no current effect — everything above holds today): the selftest's python
halves (detach-surfacing.sh l.145–146, l.151–152) strip the module and grep the output with stderr
suppressed, but unlike the node halves (which `node --check` the stripped file) they never assert
the stripped module still imports. If a future edit made the guard strip break the import, the
marker/note would vanish because the PROGRAM crashed and the selftest would still print
`DETACH-SURFACING-SELFTEST-OK` — a red-for-the-wrong-reason the node side already defends against.
Worth a one-line `python3 -c "import …"` check per python strip in the rework.

**G2 holds — not reproduced.**

## G3 — additive-only on untouched projects (HEAD byte-compare)

`git show HEAD:` versions of all four files, run against the SAME never-detached fixtures as the
working-tree versions (HEAD node files placed inside identically-named fixture copies so sibling
requires and the dirname-derived project name match; HEAD python files swapped into a copied
py/src tree):

- Fixture 1 (rich: task done, gate_failed + provenanced gate_passed, review_failed/review_passed
  with models, stale_lock_broken incident, Sev-1 artifact-rot problem → doctor exit 1): report
  text, report --json (modulo the run-local `"generated"` timestamp line, which differs between
  any two runs of the SAME version), doctor output + exit — byte-IDENTICAL, both runtimes.
- Fixture 2 (regate pending + state drift, never-detached): all six comparisons byte-IDENTICAL.

**G3 holds — not reproduced.**

## Constraints-as-claims check

The G constraints strengthen P1/P2 in the plan's own direction (compose with the regate wave,
strip-clean discipline, additive-only diff); none contradicts the phase's tasks or pins incidental
implementation. The phase's change list matches `git status` exactly.

## Answers

P1: NOT-REPRODUCED — marker loud/one-line with gate+actor+reason on both runtimes, grep of both runtimes' --json empty, gone after reattach, absent on never-detached; doctor notes exit 0 on live/anchor-missing/A-both/B fixtures; audit byte-identical detached vs stripped on both runtimes (independently replicated).
P2: VIOLATED — dev-plugin.md l.152 documents "(a stamp-mismatched or missing anchor reads as missing: `_start` fallback, said aloud by doctor)", but on a stamp-mismatched anchor (edit `_detach_D.json` detached_at → 1999-01-01) both runtimes' `hb changed` silently widen to `_start` while both doctors print the live-detach note with NO suffix — the suffix keys on anchor existence only (hb.js l.419, doctor.py l.158; zero stamp/detached_at checks in either doctor). A documented doctor behavior that does not exist in code; every other documented verb, flag, refusal, warning arm, trap, marker, note, doctrine line and backticked subcommand checked out verbatim.
G1: NOT-REPRODUCED — composed fixture renders one unbroken line, regate before detach with full payloads on both runtimes (marker indices 41<104 node, 40<103 python); clearing only detach left ⛔, clearing only regate left ⟂; composed --json free of both marker texts on both runtimes.
G2: NOT-REPRODUCED — the report/doctor guard strips on copies parse (node --check) and import (python), emit zero detach output, exit 0 on all divergence fixtures, and leave the drift + regate findings and every other report line byte-unchanged; the marked-line inventory is exactly the emit/decide lines with no guard on structural lines. (Noted for rework, no current effect: the selftest's python halves lack the import-check the node halves have.)
G3: NOT-REPRODUCED — HEAD vs working-tree runs of all four files on a rich never-detached fixture and a regate-pending fixture are byte-identical for report text, report --json (minus the per-run "generated" timestamp) and doctor output+exit on both runtimes.

## Verdict

One real finding: P2 — the runtime doc claims doctor loudness on the stamp-mismatch arm that the
shipped doctors do not have (reproduced on both runtimes). The mechanism, surfacing, composition,
strip discipline and additive-only diff all held against every probe; the docs are otherwise
verbatim-accurate. Fix is small (scope the doc sentence, or ship the stamp-check note + fixture),
but a doc that promises loudness the system does not emit is exactly what this gate exists to catch.

UNSOUND
REFUTED
