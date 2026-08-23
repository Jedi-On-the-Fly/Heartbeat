# GATE_VD — refutation attempt (docs-currency / v1.28 version bump + docs sweep)

**Actor:** vd-refuter (HB_ACTOR=vd-refuter) — did NOT perform the VD work.
**Gate:** GATE_VD, phase VD of the v1.28 plan (`planning/v1_28.dag.json`).
**Proof under test:** `docs/howto/gate-examples/docs-currency.sh` (T142), plus T39.4 version consistency.
**Method:** refute, don't confirm. Only SOUND if I cannot refute.

## Claims

Versions bumped to v1.28.0 (plugin + marketplace) and 0.18.0 (py package); docs/how-tos swept
current; `docs-currency.sh` (T142) gates it with positive current-state assertions (false until the
sweep) + negative regression guards + version consistency.

## Attempt 1 — versions bumped + consistent, JSON not damaged

```
$ python3 -c "import json;p=...;m=...;print(p,m)"  → plugin 1.28.0 marketplace 1.28.0
$ grep '^version' py/pyproject.toml               → version = "0.18.0"
```
`git diff HEAD` on all three files: **only the version numbers changed** (plus a cosmetic
`json.dumps` reindent on plugin.json). No keys lost:
- plugin.json keys = `[author, description, keywords, license, name, version]` (all 6 present).
- marketplace top keys = `[description, name, owner, plugins]`; plugin entry = `[description, name, source, version]` — all intact.
- The reindent rewrote the em-dash as `—` (valid JSON) — `'—' in description` is **True** after decode; identical content.
- `json.load` on both files succeeds — **valid JSON**.
- **T39.4 plugin version is consistent with the marketplace entry → ✓ passes.**
NOT REFUTED.

## Attempt 2 — docs-currency has real teeth (both faults)

```
$ bash docs-currency.sh --selftest  → SELFTEST-OK
$ bash docs-currency.sh             → DOCS-CURRENT-OK
```
Destructive teeth check against the REAL docs (backed up to /tmp, reverted after):
- Removed `review_policy` from `docs/dev-python.md` → `FAIL: MISSING-POSITIVE ... review_policy.accept_review` (exit 1). Reverted.
- Replaced `GROUPS-SKIPPED` in `docs/dev-tests.md` → `FAIL: MISSING-POSITIVE ... GROUPS-SKIPPED coverage-floor` (exit 1). Reverted.
Both positive assertions genuinely go RED when the sweep is undone. Tree restored (verified: no residual diff on those two files beyond the legitimate v1.28 sweep). NOT REFUTED.

## Attempt 3 — negative check defeatable / wrongly excludes real surfaces?

The gate excludes `*.dag.json`, `reviews/`, and itself. Independent repo-wide grep for moved-fixture
paths (`planning/audit-fixtures` | `planning/parity-fixtures`):
- `.md/.py/.js/.sh` minus reviews: only 2 hits, **both inside docs-currency.sh itself** (its own grep pattern + the selftest planted fault) — correctly self-excluded.
- All-file-type grep: hits are `critical-fixes-2.dag.json`, `audit-agent.dag.json`, `dag-auditor.dag.json`, `hardening-integration.dag.json`, `v1_28.dag.json` (all `*.dag.json`, past-tense: *"Move the TEST fixtures ..."*) + one `reviews/GATE_HN.attempt.md`. Every excluded hit is legitimately historical.
- Fixtures genuinely moved: they now live under `tests/fixtures/audit/{hollow,existence,nondeterministic,good,side-effect}.json` and `tests/fixtures/parity/broken.json` (confirmed on disk); `dev-tests.md` lines 213–214 document that location.
The exclusions are justified; no real stale doc/code reference is overlooked. NOT REFUTED.

## Attempt 4 — did the sweep MISS a stale claim the gate didn't catch?

Searched docs for pre-fix behavior:
- `dev-python.md:43` explicitly states `cli.py`, `executor.py`, `mcp_server.py` "all call it directly — no re-entering `cli.main` and scraping stdout" — matches code.
- No doc claims fixtures live under `planning/` (only the gate's own grep pattern references that string).
- `single-source.sh` carries a "Fails today (hb-exec defines its own nonBehavioral)" comment — this is the how-to's RED-then-green narrative, NOT a current-state claim: `hb-exec.js:27` does `const { nonBehavioral } = require('./hb-audit.js')` (imports, no fork) and `single-source.sh` → **SINGLE-SOURCE-OK**. Not stale.
No stale claim found. NOT REFUTED.

## Attempt 5 — positive assertions reflect reality

- `review_policy.py:24` `def accept_review(hb, gate, verdict, artifact=None, note=None)` — the single source.
- Callers: `executor.py:352`, `mcp_server.py:153`, `cli.py:170` all invoke `review_policy.accept_review`.
- Grep for `cli.main([...review...])` re-entry across `py/src/heartbeat/` → **NONE**.
- `GROUPS-SKIPPED` is really emitted by `tests/run-tests.sh:1560` (`echo "GROUPS-RAN: ... GROUPS-SKIPPED: ..."`).
NOT REFUTED.

## Attempt 6 — STATUS.md accurate, not overclaiming

`git diff HEAD STATUS.md`: version line → v1.28; a specific v1.28 section (LK/GS/VD) states plugin/marketplace
→ 1.28.0, Python → 0.18.0 (independent cadence), the single-source review_policy sweep, GROUPS-SKIPPED marker,
fixtures under `tests/fixtures/`, gated by T142 with `--selftest` teeth. All claims verified above. Accurate, not overclaiming.
NOT REFUTED.

## Attempt 7 — suites, real numbers

```
$ HB_NO_GIT=1 bash tests/run-tests.sh   → RESULT: 362 passed, 0 failed · ✅ ALL GREEN
$ cd py && PYTHONPATH=src pytest -q      → 96 passed in 0.91s
$ bash tests/parity.sh                   → ✅ PARITY OK — node ≡ python
```
Specific: T39.4 ✓, T142.1 ✓ (DOCS-CURRENT-OK), T142.2 ✓ (SELFTEST-OK). NOT REFUTED.

## Cleanup

All scratch mutations (dev-python.md, dev-tests.md) reverted from /tmp backups; `git status --short`
matches the original snapshot (6 modified + untracked docs-currency.sh + planning artifacts). Tree clean.

## Conclusion

Every refutation avenue failed. Versions are bumped and consistent with no JSON damage; the docs-currency
gate has genuine teeth on both positive faults (verified destructively against the real docs) and its
selftest; its exclusions are justified and miss no real stale reference; positive assertions match code;
STATUS.md is accurate; all three suites green at the expected numbers. I cannot refute Phase VD.

VERDICT: SOUND
