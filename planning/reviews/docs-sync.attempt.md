# Adversarial review — reference docs synced to research adapter + T116 doc-coverage proof

Actor: adversarial reviewer (refute, don't confirm). Repo: /home/hamid/Téléchargements/heartbeat.
Change under review: adapters.md "Research — the third domain" + codegraph-coverage; research rows in
dev-plugin.md / dev-python.md; T103–T116 in dev-tests.md; new `adapters-doc-coverage.sh` wired as T116.

## 1. Doc accuracy vs code (no overclaim) — SOUND

Read the three research tools against the new adapters.md section (`docs/adapters.md:122-154`):

- **Determinism boundary** — "the fetch is on-demand and non-gated, everything downstream of the stored
  snapshot is deterministic and gates." Matches: `ground-check.js` reads only stored `<id>.txt` files,
  no network; the header explicitly draws this boundary. TRUE.
- **grounding ≠ truth** — adapters.md "It verifies grounding, not truth." Backed verbatim by
  `ground-check.js:11` and enforced by the T114 red-team (`ground-check-redteam.sh`): two GROUNDED-BUT-WRONG
  claims (`c_drift`, `c_context`) are asserted NOT flagged. TRUE.
- **4 ground-check issue classes** — doc lists FABRICATED-QUOTE / UNGROUNDED / MISSING-SOURCE / STALE.
  `grep` on ground-check.js returns exactly those four. Exact match.
- **stamp = sha of stored bytes** — `stamp-evidence.js:24` hashes `fs.readFileSync(file)` (stored bytes).
  Doc "records each source's sha256 from the stored bytes." TRUE. sha-before-excerpt ordering (so an
  edited-but-still-containing source surfaces STALE) is real (`ground-check.js:39-42`) and separately
  proven by T113/redteam's `c_stale`.
- **research-context renders only one section** — `research-context.js:20` filters
  `claims[id].section === section`. TRUE; T112 asserts "only its section's claims."
- **node ≡ python** — each research tool has a parity assertion: T111 (ground-check byte-identical),
  T112/T113 (node≡python), T115 (scale byte-identical). Py twins exist
  (`py/src/heartbeat/adapters/research/{ground_check,stamp_evidence,research_context}.py`).
- **codegraph-coverage addition** — adapters.md:94-97 ("resolved-symbol count + GRAPH-BLIND list, T106")
  and dev-python row (`codegraph_coverage`) — py module `codegraph_coverage.py` exists; grp title T106 =
  "per-task symbol coverage + GRAPH-BLIND list (node ≡ python)". Accurate.
- **T110–T116 rows vs grp titles** — cross-checked every row against `tests/run-tests.sh` grp lines
  1358–1386. All match (scale numbers 60/200, grounded=160/issues=40 identical between adapters.md:147,
  dev-tests, and the T115 assertion string). No overclaim found.

Minor note (not a defect): dev-tests T111 names `ground-check-parity.sh` while the adapters.md section
links `ground-check.sh` and labels it "node ≡ python T111". Both files exist and both are the right
references for their context (the prose links the tool's own proof; the test row names the parity proof).
Not misleading.

## 2. Links & filenames resolve — SOUND

All six proof links in the new adapters.md section resolve on disk: stamp-evidence.sh, ground-check.sh,
research-context.sh, ground-check-redteam.sh, research-scale-parity.sh, code-coverage.sh. The
research-grounding SKILL.md link resolves, as do the two howto guides
(ground-research-claims.md, source-and-ground-research.md).

prose-check.sh run on all four edited docs → each `PROSE-OK` / `ALL-PROSE-OK:1`, exit 0.

## 3. T116 coverage proof has TEETH — SOUND (with one documented weakness)

Clean run → `ADAPTERS-DOC-OK`, exit 0. It is filesystem-derived (globs `plugin/adapters/*/` and
`*.js`), no hardcoded tool list. Three teeth mutations, each restored:

- **A. Remove a tool mention** — `sed 's/stamp-evidence/…/'` in adapters.md →
  `FAIL: adapter tool 'stamp-evidence' (research) is shipped but not named`, exit 1. RED.
- **B. Ship an undocumented tool** — `plugin/adapters/research/zzz-newtool.js` →
  `FAIL: adapter tool 'zzz-newtool' (research) is shipped but not named`, exit 1. RED.
- **C. Ship an undocumented domain** — `plugin/adapters/zzznewdomain/foo.js` → two FAILs (domain +
  tool), exit 1. RED.

All mutations reverted; adapters.md restored byte-identical (md5 confirmed, 14 `deplint` / 3
`stamp-evidence` occurrences back).

**Weakness (substring false-pass, latent, not a live inaccuracy):** the check is `grep -q "$n"` on the
bare tool basename. Because `deplint` is a substring of `deplint-accept`, stripping ALL standalone
`deplint` documentation while keeping `deplint-accept` still passes GREEN (verified: perl-replaced every
`deplint` not followed by `-accept`, leaving only `deplint-accept`; proof returned `ADAPTERS-DOC-OK`
exit 0). Same theoretical hole for the domain names `code`/`docs`/`research`, which are substrings of
ordinary prose words, so a domain would "pass" on an incidental match rather than genuine documentation.
This does NOT make any current claim false — every one of the 12 tools is genuinely documented in prose
(each single-match tool, e.g. `codegraph-coverage`, `codegraph-map`, `docs-map`, appears as a real
`` `x.js` `` prose mention, not merely inside a link path). But the gate is weaker than its task title
("every shipped tool is named") implies: it would not catch a future regression where `deplint.js`
becomes undocumented while `deplint-accept` remains. A word-boundary match (e.g. `grep -qE "\b$n\b"` or
requiring the `` `$n.js` `` form) would close it. Judged a hardening opportunity, not a blocker — the
proof does go RED for every realistic drift (new undocumented tool, new domain, deleted mention).

## 4. Coverage completeness — SOUND

12 shipped tools enumerated from the filesystem: code(7) = codegraph-context, codegraph-coverage,
codegraph-discover, codegraph-exclude-hb, codegraph-map, deplint-accept, deplint; docs(2) = docs-context,
docs-map; research(3) = ground-check, research-context, stamp-evidence. Each basename + all three domain
names confirmed present in adapters.md by grep. skill-integrity.sh independently reports "3 adapters, 12
wired proof reference(s), 0 findings." Scope (guarding only adapters.md) is correct: adapters.md is the
single reference-doc claim about which adapters/tools exist; the dev-plugin/dev-python listings are prose
and already covered by the whole-docs prose gate (T93). Guarding adapters.md is the right, honest scope
for the stated claim.

## 5. Suites — SOUND

- Node: `bash tests/run-tests.sh` → **334 passed, 0 failed, ALL GREEN**. `GROUPS-PASSED` contains both
  **T93** (whole-docs prose gate) and **T116** (through T116, contiguous).
- Python: `cd py && PYTHONPATH=src pytest -q` → **96 passed**.
- Parity: `bash tests/parity.sh` → **PARITY OK — node ≡ python**.
- Self-audit: `docs/howto/gate-examples/self-audit.sh` → `SELF-AUDIT-OK:68/66 (parity:ok)`, exit 0.
- Skill-integrity: `docs/howto/gate-examples/skill-integrity.sh` → `SKILL-INTEGRITY-OK: 3 adapters, 12
  wired proof reference(s), 0 findings`, exit 0.

Working tree left clean: only the intended change set (`M` adapters.md, dev-plugin.md, dev-python.md,
dev-tests.md, run-tests.sh; `??` adapters-doc-coverage.sh). All mutation temp files removed; adapters.md
md5-verified restored.

## Verdict per point
1. Doc accuracy — SOUND (no overclaim; every claim code-backed)
2. Links & prose — SOUND (all resolve; prose-check clean)
3. T116 teeth — SOUND, with one latent substring-match weakness noted (not a live defect; hardening
   opportunity via word-boundary match)
4. Coverage completeness — SOUND (all 12 tools + 3 domains documented; correct scope)
5. Suites — SOUND (node 334/0 incl. T93+T116, py 96, parity, self-audit, skill-integrity all green)

The docs are accurately synced to the shipped research adapter and codegraph-coverage, every link
resolves, and the new anti-drift proof has real teeth against realistic drift. The one substring
weakness is worth a follow-up hardening but does not falsify any current claim or the gate's stated job.

VERDICT: SOUND
