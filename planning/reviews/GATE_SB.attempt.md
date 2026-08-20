# Adversarial refutation attempt — Phase SB ("Sourcing bridge")

**Actor:** adversarial reviewer (distinct from the implementer).
**Claim under test:** two deterministic research-adapter bridges ship, node ≡ python, backed by wired
proofs — `research-context` (renders ONE section's grounded claims for the writer, byte-identical) and
`stamp-evidence` (computes sha256 of stored source bytes into evidence.json so `ground-check` gets STALE
teeth). Proofs `research-context.sh` (RESEARCH-CONTEXT-OK) / `stamp-evidence.sh` (STAMP-EVIDENCE-OK),
wired as T112/T113. How-to: `docs/howto/source-and-ground-research.md`.

I tried to break each of the seven points below. Every command was run against the real repo.

---

## 1. Section isolation — COULD NOT REFUTE

`research-context.js` filters `Object.keys(claims).sort().filter(id => claims[id].section === section)`
(line 20) and iterates only those. Observed:

- `... method` → renders only `c_m1` (method claim + its excerpt), nothing from background.
- `... background` → renders `c_bg1` then `c_bg2` (sorted), each with text/source-url/excerpt; the
  method claim `c_m1` and its `METHOD-ONLY-EXCERPT` marker are absent.
- `... zzz` (unknown section) → header + `  (none)`.
- **Sorting** is real (`.sort()`), so c_bg1 precedes c_bg2 deterministically.
- **Missing/absent source doesn't crash:** a claim citing `source: "NOPE"` (not in `sources`) renders
  `source NOPE ` (empty url); a claim with NO `source` field renders `source (none) ` — both runtimes,
  rc=0, no exception. `sources[c.source] || {}` / `.get(...) or {}` absorb the miss.

**Is the exclusion assertion real or would a render-everything provider still pass?** I mutation-tested
it: I removed the `.filter(... === section)` clause so the provider renders EVERY section's claims. The
proof caught it immediately — `FAIL: method-section claim leaked into background` (proof lines 21-22
grep for `METHOD-ONLY-EXCERPT` / `c_m1` and hard-fail if present). The exclusion assertion has teeth; a
render-everything provider does NOT pass.

## 2. node ≡ python byte-identity — COULD NOT REFUTE

`cmp`/`diff` of node vs `python3 -m heartbeat.adapters.research.research_context` output:

- `background`, `method`, `zzz` (the `(none)` case) → all byte-identical (`cmp` confirms, not just
  `diff`).
- Unicode is exercised by the fixture: `100°C`, `0°C`, and the `»` excerpt prefix — byte-identical.
- **Locale/encoding trap:** ran the Python side under `LC_ALL=C LANG=C` with output to a **pipe** (not a
  tty — the real trap where Python would otherwise pick ascii for stdout). Still byte-identical to node;
  rc=0. Python 3.11.2 defaults stdout to UTF-8 (PEP 540), and the file is opened `encoding="utf-8"`.
- Mutation test: changing node's `»` to `>` made the proof fail (`FAIL: c_bg1 excerpt missing`), i.e.
  the byte-identity assertion (`[ "$out" = "$py" ]` plus the literal `»` grep) is enforced.

## 3. stamp honesty + STALE teeth — COULD NOT REFUTE

`stamp-evidence` sets `sha256 = sha256(readFileSync(<dir>/<id>.txt))` for each source whose file exists.

- **Honest sha over REAL bytes:** stamped sha for s1 == `sha256sum sources/s1.txt` exactly. Confirmed.
- **Overwrites a bogus pre-existing sha:** I seeded `evidence.json` with `sha256 = "deadbeef"×8`, ran
  the real stamper — the bogus value was OVERWRITTEN with the correct file sha; `deadbeef` is gone;
  `ground-check` then reports `grounded=1 issues=0`.
- **STALE teeth:** after stamping, ground-check reports GROUNDED; appending `TAMPERED` to a copy of the
  source flips ground-check to `STALE` (sha mismatch). ground-check computes sha BEFORE the excerpt
  check (ground-check.js line 39-42), so an edit surfaces as STALE even if the excerpt still matches.
- **Could a no-op / constant-sha stamper pass `stamp-evidence.sh`?** I tested all three:
  - *No-op* (records nothing): FAILS at proof line 21 (`no 64-hex sha stamped`). Mutation-tested the
    real file to a no-op — proof caught it.
  - *Constant zero sha*: FAILS at proof line 22 (`stamped a constant zero sha`).
  - *Constant NONZERO sha* (sha of empty string — passes lines 21/22): FAILS at proof lines 26-28,
    because ground-check re-derives the true sha and reports `grounded=0` + `STALE`, so `grep -q
    grounded=1` fails. All three fake stampers are rejected.
- **Does stamp mask ground-check's STALE detection (wrongly wired into the check path)?** No.
  `grep stamp` in `ground-check.js` / `ground_check.py` → no reference. ground-check re-derives the sha
  independently; stamp is a separate at-store-time step. Re-stamping after an edit re-baselines the sha
  (correct, documented behavior), but ground-check never calls stamp, so it cannot silently launder a
  stale source.

## 4. node ≡ python stamped map — COULD NOT REFUTE

The proof canonicalizes both maps with `json.dumps(..., sort_keys=True, ensure_ascii=True)` and compares
strings. On the actual fixture the two stamped outputs are in fact **raw byte-identical** (single ASCII
sha, no unicode), so canon is redundant here but sound. Concern about canon *hiding* a divergence: sort
+ ascii-escape could mask key-ORDER-only or unicode-escaping differences, but a genuine value/type/shape
divergence still surfaces (different string). For a "same map" claim this comparison is adequate. No
divergence found.

## 5. No core imports — COULD NOT REFUTE

- `research-context.js`: `require('fs')` only.
- `stamp-evidence.js`: `require('fs')`, `'path'`, `'crypto'` — stdlib only.
- `research_context.py`: `import json, sys`.
- `stamp_evidence.py`: `import hashlib, json, os, sys`.

No import of anything under `heartbeat` core. (Minor note vs the claim's "hashlib/json/os/sys":
`research_context.py` legitimately needs only `json`+`sys` — `research-context.js` only `fs` — because
rendering needs no hashing/fs-walk. Fewer imports, not more; not an overclaim.)

## 6. Overclaim in the how-to — COULD NOT REFUTE

`source-and-ground-research.md` is honest:

- A "determinism boundary" table explicitly marks **Fetch → Gated? No — non-deterministic, by design**;
  Stamp/Ground/Context are Yes.
- Section "It verifies grounding, not truth": *"None of this makes a claim true... HeartBeat does not
  fetch for you and does not fact-check; it makes the sourcing you did reproducible and hard to fake."*
- Correctly warns *"never re-stamp at check time, or a later edit could never be caught"* — matches the
  code (stamp and check are separate).
- Cross-referenced docs all exist: `ground-research-claims.md`, `feed-code-context-to-stage-b.md`,
  `gated-docs/SKILL.md`, `planning/research-adapter-scope.md`. No broken links.
- Registered in `howto-list.md` as T112/T113.

No claim the code doesn't back.

## 7. Suite reality — COULD NOT REFUTE

- **Node** `bash tests/run-tests.sh`: `RESULT: 331 passed, 0 failed`, `✅ ALL GREEN`. **T112 and T113
  appear in the `GROUPS-PASSED:` line** (verified by grep — they end the list `... T111 T112 T113`), and
  both `✓ T112.1` and `✓ T113.1` show as passing checks, not merely printed headers.
- **Python** `cd py && PYTHONPATH=src python3 -m pytest -q`: `96 passed`.
- **Parity** `bash tests/parity.sh`: `✅ PARITY OK — node ≡ python`.
- No red.

Mutation-tests above (removed section filter; broke `»`; no-op stamper) each turned the relevant proof
red, and each proof returned to green on restore — the gates are behavioral, not hollow. Working-tree
left clean (mutations reverted; only the intended SB additions remain untracked/registered).

---

## Verdict

I could not find a way to break any of the seven points while keeping the gate green. Section isolation,
byte-identity (incl. unicode and C-locale piped output), stamp honesty, STALE teeth, the fake-stamper
rejections, node≡python parity, stdlib-only imports, and how-to honesty all hold. Both proofs have real
teeth (mutation-confirmed) and are wired into GROUPS-PASSED as T112/T113. All three suites green.

Phase SB holds up.

VERDICT: COULD NOT REFUTE
