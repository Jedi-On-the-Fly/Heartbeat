# Adversarial refutation — phase RC ("Compose via one shared `hb refute-prompt` across all three surfaces + backward-compat + parity")

Actor: independent refuter (did NOT do the work). Method: read the impl, then run real commands to try to break each claim.
The RC work is present in the working tree (uncommitted, on top of RS `0283a5d` + RL `cf7c1b5`).

## What RC claims
A single compose — `hb refute-prompt <gate>` / `refuter_profiles.compose_prompt` (py) ≡ `composePrompt` (node) —
serves all three refute surfaces (node exec, python exec, interactive skill), with (A) byte-identical backward-compat,
(B) named-profile persona + BASE questions + EXTRA questions + review.prompt and profile.model/provider to dispatch,
(C) append-not-replace, (D) fail-closed on unknown at the compose/dispatch site, (E) distinct-actor + shared tick untouched,
and node ≡ python byte-identical.

## Attacks run and outcomes

### 1. Backward-compat byte-identity — HELD
- `refuter_profiles.py:compose_prompt` / `refuter_profiles.js:composePrompt`: when `gate_profile()`/`gateProfile()` returns
  `None` (no `review.profile` AND no `HB_REFUTER`), the function returns `prompt` *unchanged* — never even resolving a profile.
- **Seeded `default.json` trap:** RL's bootstrap DOES seed `.hb/refuters/default.json` on disk (confirmed via a real
  `plugin/bootstrap.sh` run). I feared this would trip composition in the no-profile path. It does NOT: `gate_profile`
  short-circuits to `None` before touching the filesystem when no profile is selected. Real bootstrap + a `review.prompt`
  gate → both runtimes emit EXACTLY `MARKER refute me`, byte-identical, no persona/checklist leaked.
- Fallback form (a gate with NO `review.prompt`): both runtimes emit `Refute that GATE_P0 is truly complete.`, byte-identical.
- `HB_REFUTER=default` DOES flip to composed output (persona + checklist + review.prompt), byte-identical node vs py — as documented.
- `HB_REFUTER=<unknown>` → both runtimes exit non-zero with the same `unknown refuter profile` message.

### 2. Proof has teeth (RED on revert) — HELD
- `docs/howto/gate-examples/refuter-compose.sh` → `REFUTER-COMPOSE-OK`; `--selftest` → `SELFTEST-OK`.
- Reverted `compose_prompt` (py) to `return prompt` always → proof went RED
  (`FAIL: python composed prompt missing a piece`). Restored → green.
- Reverted `composePrompt` (node) to early `return prompt` → proof went RED
  (`FAIL: node composed prompt missing a piece`). Restored → green.
- Both reverts done in-file and restored; `grep` confirms 0 `REVERTED` markers remain and the full compose bodies
  (`parts.append(prompt)` / `parts.push(prompt)`) are present.

### 3. Append-not-replace — HELD
- Named profile with persona+question over a gate with a criterion: output contains the persona, the BASE
  `Falsification checklist ... / PHASE CLAIM`, the EXTRA question under `Domain checks from the refuter profile:`,
  AND `review.prompt` — in that order.
- Edge: empty persona + questions-only profile → persona line correctly OMITTED (no leading blank), base checklist still
  anchors, extra appended. So the base is never dropped even when the profile brings only questions.
- `--selftest` `chk_append` proves a base-replaced output fails the check (load-bearing).

### 4. Fail-closed at DISPATCH (not just resolver) — HELD, both runtimes
- `hb refute-prompt <unknown>`: exit 1 node AND py.
- Python `exec run` with `review.profile=ghost-profile` + a stub backend: phase P0 does NOT complete
  (`completed_phases: []`) — `executor.py:~322` catches `ValueError` and returns 1 (`HB-EXEC STOP: review_error`).
- Node `hb-exec.js run` with an unknown profile: `HB-EXEC STOP: review_error — GATE_P0: unknown refuter profile ...`,
  phase stays incomplete. `hb-exec.js:~340` wraps `composePrompt`/`gateProfile` in try/catch → `escalate('review_error')`.
- No path found where an unknown profile silently downgrades to default/no-review.

### 5. model/provider routing + precedence — HELD, no confusion
- `executor.py:329-330` / `hb-exec.js:344-345`: `r_model = profile.model || cfg.refute_model`,
  `r_provider = profile.provider || cfg.refute_provider`. `cfg.refute_model` itself is
  `HB_REFUTE_MODEL env || executor.json refute_model` (executor.py:58, hb-exec.js:88). So precedence is
  `profile.model > HB_REFUTE_MODEL > executor.json refute_model` — a clean, documented chain.
- Empirically proved: profile `{"model":"PROFILE-MODEL"}` with `executor.json {"refute_model":"EXECUTOR-MODEL"}` →
  the stub refuter observed `MODEL=PROFILE-MODEL`. Profile wins.

### 6. node ≡ python byte-identical compose — HELD
- Direct `cmp` of `hb refute-prompt` output for a profile with persona + questions (incl. a question containing an
  embedded `\n` and `\t`) + model, over a gate with two criteria (mixed `cmd`/`test`): IDENTICAL (same md5).
- `review_questions` (py audit.py:60) and `reviewQuestions` (hb-audit.js:58) are byte-for-byte equal source, and
  `DEFAULT_PERSONA` matches across the twins. `parity.sh` `refute-prompt:composed` case is green.

### 7. tick untouched + no regression — HELD
- `git diff` on `py/src/heartbeat/tick.py` and the shared tick path: EMPTY. No tick files in the diffstat.
- Existing refute tests (`cross-model-refuter`, `refute-integrity`) show no modification in `git status` and the full
  node suite (372 passed, 0 failed) + python suite (96 passed) are green.

### 8. Docs vs code — HELD, no overclaim
- `dev-python.md` / `dev-plugin.md`: "ONE compose used by every refute surface (executor `review_pending` + interactive
  skill), no profile ⇒ today's prompt, else persona + BASE review_questions + appended profile questions + review.prompt,
  profile.model/provider route through cross-model refute path, unknown fails closed, node ≡ python" — every clause verified.
- `parity-notes.md` adds the `Refute-prompt compose` row citing T147 + `parity.sh refute-prompt:composed` — accurate.
- `dev-tests.md` T147 row matches the proof's actual checks.
- Interactive surface is genuinely the third: `SKILL.md` review_pending now seeds the sub-agent with
  `node .hb/hb.js refute-prompt <gate>` "the SAME compose the automated path uses"; `protocol.py` review_pending text
  points to `hb refute-prompt <gate>`. Both point at the one compose.

## Suites
- Node: `bash tests/run-tests.sh` → 372 passed, 0 failed (T147.1 + T147.2 green).
- Python: `cd py && PYTHONPATH=src pytest -q` → 96 passed.
- Parity: `bash tests/parity.sh` → PARITY OK, `refute-prompt:composed` green.

## Tree hygiene
All in-file reverts (py + node compose) restored; `grep` confirms no `REVERTED` markers, full compose bodies intact.
Working tree shows only the expected RC-modified files + the new proof. (`planning/refuter-profiles/.hb/state.json` is a
pre-existing derived-projection change, not touched by this review.)

## Holes
None found. Every RC claim (A–E + byte-identical parity) is backed by a passing, teeth-having proof and independently
reproduced by hand. The one genuine risk (RL's seeded `default.json` silently activating composition in the no-profile
path) is correctly guarded by `gate_profile` short-circuiting before any filesystem lookup.

VERDICT: SOUND
