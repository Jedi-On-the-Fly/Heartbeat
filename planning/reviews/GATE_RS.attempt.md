# GATE RS — Refuter round 2 attempt

Phase under review: **RS ("Profile schema + resolver + built-in default, both runtimes")**.

Actor: adversarial refuter, round 2 (did NOT do the work). Repo root: `/home/hamid/Téléchargements/heartbeat`.

Mandate: (1) verify the round-1 fix (normalize() type-canonical in both runtimes + a malformed-parity teeth case with a `divnorm` mutant) is real and complete; (2) hunt for new/remaining holes.

Files exercised:
- `py/src/heartbeat/refuter_profiles.py` — `_normalize`, `resolve`, `_load_from_dirs`, `_load_from_executor`
- `plugin/templates/refuter_profiles.js` — `normalize`, `resolve`, `loadFromDirs`, `loadFromExecutor`
- `docs/howto/gate-examples/refuter-profile-resolve.sh` — the parity/property proof (checks 1–5b, `--selftest`)
- `tests/run-tests.sh` — T145.1 / T145.2 wiring

## 1. The round-1 fix is real

Round-1 hole: `normalize()` diverged for malformed-but-valid-JSON fields — `persona:null` gave py `null` / node `""`; `questions:<non-list>` char-exploded a string in py while node returned `[]`; and the proof had no normalization-parity case.

Both runtimes are now type-canonical and byte-equivalent:
- `_normalize` (py): `persona if isinstance(persona,str) else ""`; `list(questions) if isinstance(questions,list) else []`.
- `normalize` (js): `typeof d.persona==="string" ? d.persona : ""`; `Array.isArray(d.questions) ? d.questions.slice() : []`.

Exact round-1 repro (`{"persona":null,"questions":"authz"}` resolved via each runtime):
- py:  `persona=''`  `questions=[]`
- node: `persona=""` `questions=[]`

The null-passthrough and char-explode bugs are closed, not papered over.

## 2. Normalization parity — 24-case mistyped-input matrix

Wrote each crafted profile to `.hb/refuters/probe.json` and compared the full canonical resolved dict (sorted keys, tight separators) node vs python. Cases covered: persona as null / number / bool / list / object / missing; questions as string / number / null / bool / object / list-of-numbers / list-of-mixed / missing; model/provider/verdict as null / number / object / list / string / missing; the combined round-1 payload; and an unknown extra key.

Result: **ALL-MATCH** (24/24). No divergence found in normalization for any mistyped input.

## 3. The proof's 5b malformed-parity check has real teeth

- `refuter-profile-resolve.sh` → `REFUTER-RESOLVE-OK` (exit 0).
- `--selftest` → `SELFTEST-OK` (exit 0): the un-mutated fake passes the whole suite and every mutant (`drop_persona noerror ignore_env noshadow badmodel divnorm`) is caught. The `divnorm` mutant — which reproduces the exact round-1 bug (null persona passthrough + char-explode) — is caught, so check 5b is individually load-bearing.
- **Mutation on the REAL resolver:** temporarily broke `plugin/templates/refuter_profiles.js` `normalize` so `questions` became `Array.from(d.questions)` (char-explodes a string, the round-1 node/py divergence). The main proof went **RED** (`FAIL: resolver property suite did not hold`, exit 1). Restored the file (verified byte-identical via `diff`) and the proof returned **GREEN**. So the proof genuinely fails on a real normalization divergence — it is not a rubber stamp.

## 4. Other resolver surfaces — attacked, all sound

- **executor.json inline `refuters` path:** `{"refuters":{"inline":{...}}}` resolves identically node ≡ python (MATCH), fully normalized.
- **Precedence dir-file > executor inline:** same name in both a `.hb/refuters/dup.json` file and executor inline → the dir file wins in both runtimes (MATCH `FROM-DIRFILE`). Matches the documented precedence (project files > executor.json inline > built-in default).
- **Malformed executor.json (invalid JSON):** both runtimes swallow the parse error (py `except (ValueError, OSError)`, js `catch`), so `default` still resolves and an unknown name still errors — identical behavior, both exit 1 on the unknown name.
- **Malformed profile FILE (invalid JSON in refuters/x.json):** both runtimes raise and exit **1** (py `JSONDecodeError`, node `SyntaxError`). Same behavior (error, non-zero), not silent-ignore. The malformed *profile-file* is NOT caught by a try/except in either runtime — it propagates. That is identical across runtimes and consistent with "unknown explicit name errors — never a silent no-review": a corrupt named profile is a hard error.
- **Directory named `x.json` (not a file):** py `os.path.isfile` → False, node `statSync().isFile()` → False; both fall through to executor → unknown → error, exit **1**, identical.
- **Symlink to a valid profile:** resolves through the link identically (MATCH `LINKED`) in both runtimes.

Exit-code parity spot-check across malformed-file / dir-as-file / unknown-name: py and node both return **1** in every case. The only cross-runtime differences observed are exception *class names* (ValueError vs Error, JSONDecodeError vs SyntaxError) surfaced to stderr — this is the design's explicit contract (behavior/reason parity, not runtime-specific error-text/class parity per AGENTS rule 2). Callers see identical non-zero-exit behavior.

## 5. Suites & wiring

- Proof wired into the owning suite as `tests/run-tests.sh` T145.1 (property/parity) and T145.2 (selftest teeth).
- Node suite: **368 passed, 0 failed**; T145 present in `GROUPS-PASSED`.
- Parity suite: **PARITY OK — node ≡ python**.
- Python suite: no dedicated `refuter_profiles` unit test exists, but python is exercised behaviorally through the T145 proof (`py_resolve`) and the parity checks against the node oracle. Acceptable under the repo model (the shell proof is the owning test); a pure-python `test_refuter_profiles.py` would be a nice-to-have, not a gate hole.

No stray edits left behind: the temporary break to `refuter_profiles.js` was restored byte-for-byte (`diff` clean); all three source files remain untracked new-file, unmodified by this review.

## Conclusion

The round-1 divergence is genuinely fixed in both runtimes; normalization is byte-equivalent across a 24-case mistyped-input matrix; the new 5b malformed-parity check is load-bearing (caught the `divnorm` mutant AND a real hand-broken normalize); precedence, executor-inline, malformed-JSON, dir-vs-file, and symlink surfaces all behave identically across runtimes with identical exit codes. Suites and parity are green and the proof is wired in. I could not refute phase RS.

VERDICT: SOUND (could not refute)
