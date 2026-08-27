# Refutation attempt — GATE_RH (Refuter-profile how-to guide)

**Phase:** RH — refute the new how-to `docs/howto/write-a-refuter-profile.md`.
**Actor:** adversarial refuter (did NOT author the guide).
**Method:** every behavioral claim tested against shipped code; every command run in a real bootstrapped project (`bash plugin/bootstrap.sh /tmp/gx`); both gate scripts + the four backing proofs + parity run to completion.

## Claims tested vs code (all held)

### 1. "no profile ⇒ byte-identical to today" (guide L30–31)
Ran `node .hb/hb.js refute-prompt GATE_P0` in a fresh project with no `review` block and no `HB_REFUTER` → output was exactly `Refute that GATE_P0 is truly complete.` (the fallback), nothing injected. Python `hb refute-prompt GATE_P1` → identical. Matches `compose_prompt` / `composePrompt`: `if prof is None: return prompt`. Gated by `refuter-compose.sh` check (A) with `--selftest` teeth (SELFTEST-OK). **Confirmed.**

### 2. "unknown explicit name errors, never silent downgrade" (guide L37–38)
Set `review.profile = "nonexistent-xyz"` → `refute-prompt: unknown refuter profile: 'nonexistent-xyz' …` EXIT 1 in both runtimes. `resolve()` raises `ValueError`/throws for any `eff != "default"` with no file/executor entry. Also `HB_REFUTER=zzz` errors (stricter than the guide's "explicit" wording — env unknown also fails closed, not a contradiction). **Confirmed.**

### 3. "questions APPEND, never replace the base checklist" (guide L86–88)
With `security` profile the composed prompt contained the full `Falsification checklist for GATE_P0 …` (base `review_questions`) AND a separate `Domain checks from the refuter profile:` block with the profile's three questions. Code appends: base checklist part is unconditional, extra questions are a *separate* appended part. Gated by `refuter-compose.sh` check (C) whose selftest fails if the base is dropped. **Confirmed.**

### 4. Precedence (guide L69–71)
- WHICH name: set gate `review.profile=correctness` with `HB_REFUTER=security` in env → composed prompt used the **CORRECTNESS** persona. Gate profile beats env. `HB_REFUTER=default` with no gate profile → default persona. Matches `eff = name || env || "default"`.
- WHERE it resolves: `search_dirs` returns the project `.hb/refuters/` first (shadows shipped, which RL inserts after). **Confirmed.**

### 5. Bootstrap seeds no-clobber; project file shadows shipped (guide L102–104)
Empirical: wrote `{"persona":"MINE"}` to `/tmp/gx/.hb/refuters/security.json`, re-ran `bootstrap.sh /tmp/gx`, file was still `{"persona":"MINE"}`. Matches `[ -e "$_dest" ] || cp` in `plugin/bootstrap.sh` L74–78. **Confirmed.**

### 6. Panel aggregation + fail-closed (guide L91–95)
`aggregate_verdict`/`aggregateVerdict`: `any` ⇒ t≥1, `all` ⇒ n>0 and t==n, `majority` ⇒ 2t>n. Executor (`executor.py` L341–373): a panelist with no boolean verdict → `review_error … fail-closed`; a pass with `<40` chars of findings → `refuter returned a pass with no substantive findings` EXIT 1 (the "clear verdict citing no evidence cannot certify" claim). Parity has a dedicated `panel-aggregate` case (green). **Confirmed.**

### 7. "refute-prompt is what BOTH the executor and an interactive refuter use" (guide L82–83)
`executor.py` L320–324 and `hb-exec.js` L337–342 both call the shared `compose_prompt`/`composePrompt` ("ONE compose (shared with `hb refute-prompt` + the interactive surface)"). `plugin/skills/heartbeat/SKILL.md` L295 seeds the interactive refuter with `node .hb/hb.js refute-prompt <gate>` — "the SAME compose the automated path uses." **Confirmed.**

## Commands (every backticked form runs)
- `node .hb/hb.js refuters` → lists 4, EXIT 0. `hb refuters` (python `hb = heartbeat.cli:main` console script; also `python3 -m heartbeat.cli refuters`) → identical.
- `node .hb/hb.js refute-prompt GATE_P0` / `hb refute-prompt GATE_P0` → composed prompt, EXIT 0. Both subcommands registered in `hb.js` (L549/L560) and `cli.py` (L52/L53). No dead commands in the guide.

## Starters (guide L108–109)
`security.json`, `correctness.json`, `research-source.json` all present under `plugin/templates/refuters/`, valid JSON, seeded by bootstrap, and normalize to non-empty personas (persona_len 336/371/380, questions 3/3/3) in the node runtime; both runtimes share the parity-proven normalize. `refuter-library.sh` (behavioral: resolves, not file-exists) green + SELFTEST-OK. **Confirmed.**

## Links (guide) — all resolve
`gate-examples/refuter-profile-resolve.sh`, `refuter-library.sh`, `refuter-compose.sh`, `refuter-panel.sh`, `writing-behavioral-gates.md`, `../dev-tests.md`, `gate-examples/`, `../heartbeat.md` — all exist relative to `docs/howto/`.

## Gates (required)
- `prose-check.sh docs/howto/write-a-refuter-profile.md` → PROSE-OK, EXIT 0.
- `index-coverage.sh` → INDEX-COVERAGE-OK, EXIT 0.
- Four backing proofs T145–T148 each green + `--selftest` SELFTEST-OK.
- `tests/parity.sh` → `PARITY OK — node ≡ python`, EXIT 0.

## Honesty boundary (guide L112–119)
The guide correctly states a profile is *prompts*, does NOT claim a profile guarantees better verdicts ("A profile changes the lens; it does not guarantee the verdict"), and defers "better verdicts" to a live-model measurement, never a gate. Matches the code's design (pure resolution + plumbing gates only). No overclaim. **Confirmed.**

## Holes found (minor, non-blocking)

**H1 — JSONC copy trap (real, unwarned).** The author example (guide L44–56) is fenced ```jsonc``` and contains `// comments` (`// .hb/refuters/security.json`, `// a domain lens…`, `// optional…`). A user who copies it verbatim into `.hb/refuters/security.json` will hit `JSON.parse` failure — verified: `JSON.parse('{ "persona":"x", // c\n … }')` → `Expected double-quoted property name in JSON`. The loaders use plain `JSON.parse`/`json.load` (no comment stripping), and no shipped starter contains `//`. The guide says "A profile is a JSON file" but never warns the comments must be removed. This is a genuine footgun a one-line caution would close. **Not a behavioral contradiction with the code — an omission in the guide.**

**H2 — "Three starter profiles ship today" is imprecise (cosmetic).** Guide L108 says three ship (`security`, `correctness`, `research-source`), but `plugin/templates/refuters/` also ships `default.json`, which bootstrap seeds, so `hb refuters` lists FOUR. The shipped `default.json` persona is byte-identical to the built-in `DEFAULT_PERSONA`, so there is no behavioral divergence or fail-open — the guide simply treats `default` as "the built-in" (L34–38) separately from the three domain starters. Framing nit, not a hole in behavior.

Neither H1 nor H2 is an OVERCLAIM against the code, a broken link, a dead command, or a hollow/unsupported behavioral claim. Every load-bearing claim is backed by a proof with real teeth and holds in both runtimes. The JSONC trap (H1) is worth a one-line fix but the guide's ```jsonc``` fence already signals the block is illustrative.

VERDICT: SOUND
Holes (advisory, non-blocking): H1 — the ```jsonc``` author example (L44–56) carries `//` comments that will break `JSON.parse` if copied verbatim into a `.json` file; add a one-line "strip the comments — JSON has none" caution. H2 — "Three starter profiles ship" undercounts the shipped set (a byte-identical `default.json` also ships/seeds); cosmetic.
