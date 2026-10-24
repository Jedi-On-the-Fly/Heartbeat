# DS1 round-3 refutation (GATE_DS1)

Phase DS1 (replan contract / drift tripwire). Ran in mktemp fixtures (plugin/bootstrap.sh), HB_NO_GIT=1, env vars unset, HB_ROT_CHECK unset; live .hb untouched; repo unmodified.
- bash tests/replan.sh -> REPLAN-OK; --selftest -> REPLAN-SELFTEST-OK; tests/parity.sh -> PARITY OK.
- Re-ran round-2 repros: t8.py (hostile numbers) -> 2^53+1 vs 2^53 quiet/quiet; 1e400 vs null DRIFT/DRIFT (type-class); -0.0 vs 0, 2^60, 1e-7, 1e21 all agree. t9.py 2^53 case agrees (3 problems each... same count both). t10.py id-less 9-task phase: byte-identical "[?] 9 tasks (>8)" rc 0 both.
- New t14.py: string id "1" vs number 1 DRIFT both; numeric/bool/null/array/object ids with WEAKENED string cmd (yyy vs zzz, true vs "test x") DRIFT on both; negative zero quiet both; same-string quiet both. Raw NaN literal in events: node treats the line as unparseable, python accepts it -- both end in drift/undefined-gate noise rc 1 (NaN is not valid JSON; out of schema).
- New t13.py lint: missing / null / int / empty / object / list phase id at the undefined-gate and locked-forever sites: same rc and same finding lines on both runtimes, no traceback.
- Fresh G4 spot-check: hb protocol criteria_drift answers on node and python (text names full regate cycle, "never freeze or edit past"); bootstrap PROTOCOL.md identical to `hb protocol --md`; hook text names criteria_drift in both lists; mcp_server and SKILL.md row present; SKILL.md freeze advice is only on unsanctioned_drift row.
- T184 row in docs/dev-tests.md now scopes dup rule to string ids (F3 wording resolved) and F4 doc/code contradiction addressed.

## Round-2 folds verified REAL
G2 (type-class canonicalization): the boundary shapes that split in round 2 now agree; weakened string cmds keep their teeth under every hostile id.
G5 (second p['id'] crash): fixed at all three message sites; parity holds on degenerate ids.

## Residual notes (not counted; pre-existing and outside the stated failure conditions)
- A dag criteria entry whose cmd is a non-string (int) or an entry that is a list crashes python doctor in lint.extract_paths / doctor.py:31 (TypeError / AttributeError) while node reports normally. This is the doctor's path-extraction scan, not the drift walk, on a schema-invalid dag that lint would reject; noted in round 2 as pre-existing. Not a G2 shape (G2 enumerates null/missing id, not non-string cmd).

## Per-id
P1: NOT-REPRODUCED -- replan.sh green; append case untouched by round-2 folds.
P2: NOT-REPRODUCED -- weakened cmd drifts on both under all ids; replan.sh drift/cure matrix green; doc wording now matches behavior.
P3: NOT-REPRODUCED -- SWEEP-OK/TICK-OK green; parity green.
P4: NOT-REPRODUCED -- --selftest green (guard strips redden named checks); T184 row present; parity drift:cross green.
G1: NOT-REPRODUCED -- replan.sh sweep/tick checks green; code paths unchanged by folds.
G2: NOT-REPRODUCED -- 2^53 neighbors, 1e400, -0.0, string-vs-number, bool/null/object ids all classify identically with no crash; string cmd weakening drifts on both.
G3: NOT-REPRODUCED -- HB_ROT_CHECK unset throughout; TICK-OK green.
G4: NOT-REPRODUCED -- fresh spot-check above: all surfaces carry criteria_drift, no freeze offer.
G5: NOT-REPRODUCED -- id-less 9-task and degenerate ids at all three sites agree byte-for-byte, no traceback; dup string ids error on both.
G6: NOT-REPRODUCED -- suites/parity green, re-specs untouched by folds.

## Overall
COULD-NOT-REFUTE. Both round-2 folds hold; nothing new broke. Verdict: SOUND.
