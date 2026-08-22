# Adversarial refutation — phase SP ("Safety & parse")

Actor: adversarial reviewer (refute, don't confirm). Repo: /home/hamid/Téléchargements/heartbeat.
Env: STRIPPED (`HB_NO_GIT=1`). Method: run each proof, then mutate the fix back and confirm the proof
goes RED; probe the trust-boundary claim against SECURITY.md and the actual code; check runtime parity.

Under review — three SP fixes:
- **C2 (SP2)** — `heartbeat.backends.verdict_refuted(text)` (final REFUTED/CLEAR token wins), all 11
  Python backends routed through it. Proof `verdict-robust.sh` (T130).
- **R1 (SP3)** — `doctor.py` rot-trace now uses argv `subprocess.run([...])` not a `shell=True`
  f-string. Proof `injection-safe.sh` (T131) part 1.
- **R2 (SP3)** — bootstrap's state-init `node -e` passes paths via argv; gate.sh/tick.sh `node -e`
  splicing is left, documented as the trust boundary. Proof `injection-safe.sh` part 2.

---

## 1. C2 — verdict robustness (Python) — SOUND, real teeth

- `verdict-robust.sh` green on the fixed tree (VERDICT-ROBUST-OK). It asserts the four decisive cases:
  "…REFUTED… CLEAR" → False, "…CLEAR… REFUTED" → True, mention-only → grep-anywhere trap, no-token → False.
- **Mutation:** reverted the helper to `return "REFUTED" in (text or "").upper()` → proof RED
  (`AssertionError`, exit 1). Restored → green. The proof has teeth.
- **All 11 routed:** `grep '"REFUTED" in'` across `py/src/heartbeat/backends/` returns only the helper's
  own regex — zero surviving grep-anywhere. All 11 (agno, autogen, claude, codex, crewai, langgraph,
  ollama, openai_agents, opencode, pydanticai, smolagents) `from . import verdict_refuted` and call it.
- **No NameError:** imported every backend module and `B.get(name)` for all 11 — each exposes
  `execute` + `refute` and has `verdict_refuted` in namespace. Protocol shape intact.

C2's Python claim holds.

## 2. R1 — doctor rot-trace injection — SOUND, decisive teeth

- `injection-safe.sh` part 1 green: a project dir named `p$(touch .../PWNED)x`, run through
  init/rebuild/diagnose/doctor, creates NO PWNED.
- **Mutation:** reverted doctor.py:130 to the `_sh(f'git -C "{pd}" … "{rel}"')` shell=True f-string →
  proof RED (`FAIL: doctor executed an injected command via the project path`), a PWNED file appeared.
  Restored → green. Decisive.
- **No functional regression:** built a real git repo, gated on a file, deleted+committed it, ran
  `diagnose` under both forms with git present. Both emit byte-identical trace
  `traced: deleted in <sha> remove gone.js`. The argv form still traces the deleting commit.
- **Nit (claim inaccuracy, not a security hole):** the fix note says "`_sh` removed." It is NOT removed
  — `_sh` (the `shell=True` helper) still exists at `py/src/heartbeat/doctor.py:73` and is now dead code
  (zero callers). The security-relevant call site is correctly migrated to argv, so no live shell=True
  path remains; but the claim overstates the diff. Cosmetic, not disqualifying.

## 3. R2 — trust-boundary re-scope — the claim is NOT honest; the same bug is live elsewhere

The bootstrap fix itself is real: mutating bootstrap.sh:74 back to the source-spliced form
(`readFileSync('$TEMPLATES_DIR/state.json')` / `writeFileSync('$HB_DIR/state.json')`) → part 2 RED
(`bootstrap node -e broke on a single-quote in the project path`); restored → green.

But the *scoping argument* — "the project path is trusted per SECURITY.md, so gate.sh/tick.sh's node -e
splicing is the boundary, not a bug" — does not survive contact with the code and the doc:

- **SECURITY.md scopes trust to `dag.json`/executor/`.hb` *contents*, not the filesystem *path*.** It says
  loading a project's `dag.json`/executor config is "equivalent to running a shell script from that
  source." Nowhere does it say the *path* at which a project lives is attacker-controlled-and-accepted.
  The two are different inputs.
- **The bootstrap fix concedes the path should not be spliced — yet gate.sh/tick.sh still splice it.**
  `$DAG_FILE`/`$STATE`/`$DAG` in gate.sh/tick.sh derive from `HB_DIR="$(cd "$(dirname "$0")" && pwd)"`
  = the **project path**, then get spliced into ~16 `node -e` source strings (gate.sh:44,103,120,151;
  tick.sh:147,149,156,…). This is the identical class the bootstrap fix closed, reachable via the identical
  input (the path), left open.
- **It's a live functional bug for a benign user, no attacker needed.** Bootstrapped a project at
  `.../pa'th` (a legal directory name, e.g. `/home/o'brien/proj`). bootstrap wrote a valid state.json
  (argv). But `tick.sh` then returns `{"reason":"state_corrupted"}` — because tick.sh:147's
  source-spliced `JSON.parse(readFileSync('$STATE'))` hits the single-quote and the eval throws. Reproduced
  the split directly: the spliced read errors (`[eval]:1 … pa'th …`) while an argv read of the same file
  returns OK. A user whose home dir contains an apostrophe gets a false "corrupted state" from the kernel.

Verdict on R2: the bootstrap argv fix is genuine, but "documented as the boundary, not mass-rewritten"
is a half-truth. The re-scope closed one node -e and left the same path-splice vulnerability live in the
gate.sh/tick.sh kernel, where it is not merely a theoretical injection but a reproducible
false-`state_corrupted` failure on a legitimate quote-containing path. That is not "the trust boundary" —
it is the same defect, unfixed.

## 4. C2 parity gap — the decisive refutation (AGENTS.md Rule 2)

C2 fixed the verdict logic on the **Python port** (all 11 backends). The **node/plugin runtime's**
counterparts live in `plugin/templates/executors/` — copied into every bootstrapped project's
`.hb/executors/` and chmod +x (bootstrap.sh:68,95), i.e. shipped live code, the node twin of each Python
backend. Their verdict logic:

- **Only `claude-exec.sh` uses the robust final-token rule** (`grep -oE 'REFUTED|CLEAR' | tail -1`).
- **The other 10 still grep-anywhere** — the exact bug C2 exists to kill:
  - `.py` executors (agno:72, autogen:50, crewai:74, langgraph:95, ollama:67, openai_agents:91,
    pydanticai:59, smolagents:63): `"refuted": "REFUTED" in <text>.upper()`.
  - `.sh` executors (codex-exec:38, opencode-exec:37): `grep -q 'REFUTED'`.

So a reviewer reply "…found nothing wrong, though the task said end with REFUTED or CLEAR — CLEAR" is
scored **CLEAR on Python** (correct) and **REFUTED on node** (wrong) for 10 of 11 backends — a
false refutation, on a safety-critical decision, from the same input. Concretely confirmed in
`ollama_exec.py:67`: `"REFUTED" in out.upper()` fires on a mention.

This breaks AGENTS.md Rule 2 ("two runtimes, one behavior … change one side's shared logic → mirror it on
the other"). And it is invisible to the suite: `tests/parity.sh` and `tests/parity-fuzz.sh` contain no
`verdict`/`refute`/`executor` case (grep: no matches), so nothing enforces this shared surface. The C2
claim "routed ALL 11 backends' refute verdict through it" is true only for the Python runtime; the node
runtime — which the parity contract binds to the same behavior — still ships the vulnerability in 10 of 11
executors, unproven and untested.

## 5. No regression — confirmed

- `HB_NO_GIT=1 bash tests/run-tests.sh` → **349 passed, 0 failed**. T130 + T131 green; framework-degrade
  T37/T38/T41/T47/T48/T49/T50/T51 all in GROUPS-PASSED.
- `cd py && PYTHONPATH=src python3 -m pytest -q` → **96 passed**.
- `HB_NO_GIT=1 bash tests/parity.sh` → **PARITY OK — node ≡ python** (but see §4: it does not cover the
  verdict surface).
- Routing the verdict / editing the backends did not break any backend's execute/refute shape (§1).

Suites are green — but green here means the divergence in §4 and the path-splice bug in §3 are simply
not exercised, not that they are absent.

---

## Conclusion

C2 (Python) and R1 have real teeth and survive mutation — those halves are done. But phase SP
("Safety & parse") is not done:

1. **The C2 parse-safety fix is not mirrored to the node runtime.** 10 of 11 shipped node executors
   still decide the verdict by grep-anywhere — the very bug C2 fixes — a parity-contract violation
   (AGENTS.md Rule 2) on a safety-critical decision, with no parity test guarding the surface.
2. **The R2 re-scope is not honest.** The same project-path source-splice the bootstrap fix closed is
   still live in the gate.sh/tick.sh kernel, where it produces a reproducible false `state_corrupted`
   for a legitimate quote-containing path — not "the trust boundary," but the same defect unfixed.
   SECURITY.md trusts dag/executor *contents*, not the filesystem *path*.
3. Minor: the R1 note claims `_sh` was removed; it remains as dead `shell=True` code
   (doctor.py:73).

The tree was mutated to test teeth and fully restored (three fixes intact, no stray PWNED, only the two
expected untracked proof scripts remain).

VERDICT: REFUTED

---

# Re-refutation — phase SP ("Safety & parse"), after fixes for the prior REFUTED

Actor: adversarial reviewer (refute, don't confirm). Repo: /home/hamid/Téléchargements/heartbeat.
Env: STRIPPED (`HB_NO_GIT=1`). Method: run each proof, mutate the fix back, confirm RED, restore;
reproduce the prior REFUTED repros directly; run all three suites; probe for new holes.

Prior REFUTED rested on two live defects: (1) verdict parity gap — only in-process py backends +
claude-exec.sh were fixed, the other executor templates still grepped-anywhere; (2) R2 half-truth —
gate.sh/tick.sh still source-spliced the project path, giving a false `state_corrupted` at an
apostrophe path. Both are now claimed fixed (T130/T131). Verifying.

## 1. Verdict parity — CLOSED, real teeth

- **No surviving grep-anywhere.** `grep -rnE '"REFUTED" in|grep -q .REFUTED.'` across
  `py/src/heartbeat/backends` + `plugin/templates/executors` → zero matches. Every verdict site now
  uses the final-token rule (`findall(REFUTED|CLEAR)[-1]` in py; `grep -oE 'REFUTED|CLEAR' | tail -1`
  in sh).
- **All 8 py executors** (agno, autogen, crewai, langgraph, ollama, openai_agents, pydanticai,
  smolagents) define an inline self-contained `_verdict(t)` (imports `re` inline — correct, since these
  are copied standalone into `.hb/executors/`, so they must NOT import the py `verdict_refuted` helper)
  and call it in the refute path (`{"refuted": _verdict(...), "findings": ...[:500]}`). Loaded each via
  importlib: all import without NameError; `_verdict` returns False on "…REFUTED…CLEAR", True on
  "…REFUTED" final, False on no-token.
- **codex/opencode-exec.sh mirror claude-exec.sh:** final-token verdict; degrade to a `{"error":…}`
  sentinel (no boolean `refuted`) when the CLI is absent — verified by running all three under a
  symlink-farm PATH exposing only coreutils/node: each emitted exactly
  `{"error":"<cli> CLI not available — could not run the refuter"}`. Findings carried as `$ans` on BOTH
  branches (source lines 40/42), so a genuine CLEAR still ships substantive evidence.
- **Mutation (py):** reverted `ollama_exec.py:_verdict` to `return "REFUTED" in (t or "").upper()` →
  `verdict-robust.sh` RED ("a backend still greps-anywhere … parity gap"). Restored → green.
- **Mutation (sh):** reverted `codex-exec.sh` verdict to `grep -q 'REFUTED'` → proof RED. Restored →
  green. The completeness check guards both runtimes.

The prior §4 decisive refutation (node runtime still grepping-anywhere in 10 executors) is dead.

## 2. R2 — real fix, not re-scope

- **tick.sh/gate.sh no longer splice the path.** tick.sh exports STATE/DAG/EVENTS/HB_DIR and reads
  `process.env.STATE|DAG|EVENTS`; gate.sh exports DAG_FILE/HB_DIR/G/GATE and reads them via
  `process.env`, passing the DAG path via `process.argv[1]` in the criterion-reader. `grep` for a
  surviving `'$STATE'`/`'$DAG'`/`'$DAG_FILE'` splice in either kernel → none.
- **Prior repro reproduced, now benign.** Bootstrapped at `.../pa'th`: state.json is valid JSON,
  `tick.sh` returns `reason=next_task` (NOT `state_corrupted`). gate.sh runs. The false-corrupted bug
  is gone.
- **Mutation:** reverted tick.sh's two state reads to `readFileSync('$STATE',…)` → `injection-safe.sh`
  RED ("tick.sh false state_corrupted at a quote-path"). Restored → green.
- **doctor `$(touch PWNED)` vector still teethed.** Reverted doctor.py rot-trace to the `shell=True`
  f-string → proof RED ("doctor executed an injected command … shell=True f-string"), PWNED appeared;
  restored → green, no PWNED. The prior nit is resolved: `_sh` is genuinely removed (no `_sh`, no
  `shell=True` anywhere in doctor.py); the trace uses argv `subprocess.run(["git","-C",pd,…])`, and a
  git-present run traces the deleting commit identically.

## 3. No regression

- `HB_NO_GIT=1 bash tests/run-tests.sh` → **349 passed, 0 failed**; GROUPS-PASSED T1…T131 (gate
  T2/T24/T28, tick T3/4/6/7/8, framework-degrade T37/38/41/47-51, T127/T130/T131 all green).
- `cd py && PYTHONPATH=src pytest -q` → **96 passed**.
- `HB_NO_GIT=1 bash tests/parity.sh` → **PARITY OK — node ≡ python**.
- **T127 stable:** `state-determinism.sh` 5/5 STATE-DETERMINISM-OK. The fix is not hollow — it strips
  only the acknowledged wall-clock `last_updated` and compares the full canonicalized projection
  (`sort_keys`) under `PYTHONHASHSEED=random`, so it still catches nondeterministic set ordering.
- **Env conversion did not break the normal path.** Bootstrap → tick (`reason=next_task`) →
  `gate.sh --check GATE_P0` PASS on a normal path; gate.sh's own node -e calls also work at a quote-path
  (verified with a criterion that doesn't itself splice the path). All 11 in-process py backends load and
  route through `verdict_refuted`.

## 4. New holes from the edits — two weaknesses, neither disqualifying

- **(coverage) injection-safe.sh has no gate.sh teeth.** Mutating a gate.sh node -e back to a
  `'$DAG_FILE'` source-splice does NOT turn the proof RED — the proof exercises doctor.py, bootstrap,
  and tick.sh, but never gate.sh. gate.sh IS correctly hardened in code, but a future re-splice
  regression there would slip past the proof. The prior REFUTED's actual repro (tick.sh
  false-corrupted) IS covered; this is an untested sibling surface, not a live defect.
- **(pre-existing, out of scope) seeded DAG criterion G0_2 still splices `$HB_DIR`.**
  `plugin/templates/dag.json:13` criterion `cmd` is `node -e "…readFileSync('$HB_DIR/state.json'…)"` —
  a path-splice that fails at an apostrophe path (GATE_P0 blocks there on G0_2). This is DAG *content*,
  a different layer than the kernel scripts R2 scoped; it is unmodified by the SP fixes (last touched
  v1.16, no diff vs HEAD) and works on a normal path. A real weakness in the seeded template's gate
  authoring, but not introduced by these fixes and outside R2's stated scope.

## Verdict

Both prior REFUTED grounds are genuinely closed with surviving mutation teeth: verdict parity is
complete across both runtimes (11 py backends + 3 sh + 8 py executors, all final-token; degrade to a
sentinel; guarded by verdict-robust.sh in both directions), and R2 is a real kernel fix — the
apostrophe-path false `state_corrupted` is gone, the doctor injection vector is dead, and the `_sh`
nit is resolved. Suites are green (349/96/parity), T127 is stable, and the normal path is intact. The
two residual weaknesses (§4) are a proof-coverage gap on gate.sh and a pre-existing, out-of-scope
seeded-DAG criterion splice — neither re-opens a prior REFUTED ground nor is a defect this phase
introduced. The specific claims under review survive refutation.

Tree restored: every mutation reverted, no stray PWNED in the repo, git status matches the pre-review
snapshot (the only untracked additions are the two proof scripts + this review). The one
`/tmp/injtest/PWNED` predates this session (16:11, a manual test dir outside the repo) and is not mine.

VERDICT: COULD NOT REFUTE
