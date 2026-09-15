# GATE_RE3 refutation attempt — phase RE3, whole-feature review (refuter-economics)

Fresh strong-model adversarial review, per the composed brief (`node .hb/hb.js refute-prompt GATE_RE3`).
Reviewer: distinct actor from the doer; the two prior gates were reviewed by the profile-bound
cheap model (correctness/sonnet) — this pass is the semantic tier plus the guide itself.

## What I ran (evidence, not trust)

- Full node suite: `bash tests/run-tests.sh` → **421 passed, 0 failed, ALL GREEN**, with both
  `T163` and `T164` present in `GROUPS-PASSED` (run-enforcement, not header-grep).
- `bash tests/parity.sh` → **PARITY OK**, including `refute-prompt:composed`, `refute-prompt:json`,
  `refute-prompt:json-order`, and `refuter-impact` (the model-extended mixed null/named case).
- Python suite: `cd py && PYTHONPATH=src .venv/bin/python -m pytest -q` → **115 passed**.
- Both proofs and both selftests, directly:
  `docs/howto/gate-examples/refuter-model-routing.sh` → `REFUTER-MODEL-ROUTING-OK` + `SELFTEST-OK`;
  `docs/howto/gate-examples/refuter-model-provenance.sh` → `REFUTER-PROVENANCE-OK` + `SELFTEST-OK`.
- The re3x checkers directly: `prose-check.sh docs/howto/tier-the-refuter.md` → `ALL-PROSE-OK:1`;
  `index-coverage.sh` → `INDEX-COVERAGE-OK`. Indexed at `docs/howto/howto-list.md:83`; cross-link
  present at `docs/howto/cross-model-verification.md:58`; back-links in the guide resolve.
- `node .hb/hb-report.js .hb` and `--json` on this plan project itself (see finding 1).

## Verified true (attack lines that did NOT land)

1. **Honest-limit section is real, not decorative.** All four limits are present and each is
   load-bearing prose (`docs/howto/tier-the-refuter.md:55-69`): cheaper ≠ differently-failing
   (with the subset-failing framing), watch per-model impact before trusting a downgrade, never
   downgrade to buy a pass, and the trust boundary. The trust-boundary limit is **correct in
   code**: `py/src/heartbeat/executor.py:329-336` derives `r_model` from the resolved
   profile / `refute_model` config and stamps it on the review event with no operator input
   (`executor.py:366-367,387`; node twin proven behaviorally by T164's stub-backend run on
   `hb-exec.js`), while the CLI/MCP `--model` is whatever the recording actor says. Minor
   wording nit only: the guide says the auto-stamp is config-derived "from the resolved
   profile" — in code it is `prof.model or cfg["refute_model"]` (HB_REFUTE_MODEL/executor.json
   fallback, `executor.py:329`). Still config-derived; the boundary claim stands.
2. **Both deferrals are accurate, verified in code, not just asserted.**
   - *Panel fan-out*: `refute-prompt --json` does emit `panel`/`refute_if` (T163 asserts both,
     `hb.js:634`), and **nothing instructs N spawns interactively** — the `review_pending`
     texts in `plugin/skills/heartbeat/SKILL.md:298`, `py/src/heartbeat/protocol.py:11`, and
     `plugin/templates/hb.js:48` instruct exactly one spawn + `--model` record; no panel wording.
   - *`audit --agent` unrouted*: `py/src/heartbeat/review.py:36-45` dispatches the plan
     refutation via `executor.dispatch(cfg, "refute", …)` with **no** `model=` argument and no
     profile resolution (`executor.py:128-136` only sets HB_EXEC_MODEL when passed), and it
     writes **no review event** — so its spend is genuinely outside the impact report, exactly
     as the guide states (`tier-the-refuter.md:71-74`).
3. **No token-savings promise, no equivalence claim.** The guide never quantifies savings
   (tokens are explicitly not recorded — `tier-the-refuter.md:68-69`, matching re2b's design
   note) and limit 1 explicitly denies cheap≡strong. The "often *more* adversarial per token"
   line (`:41`) is a hedged heuristic, not a measurable claim.
4. **Plan-level closure.** Gap (a) interactive binding → RE1: `--json` emits
   `{prompt, model, provider, panel, refute_if}`, byte-pinned to the one compose profiled and
   profile-less, text path byte-unchanged (T147 pin re-run inside T163), both instruction
   halves in skill + both PROTOCOLs — parity case `refute-prompt:json`. Gap (b) provenance →
   RE2: `--model` on pass AND fail in both runtimes, null-honesty, exec auto-stamp on both
   executors via a run stub backend, MCP `review.model` through real stdio JSON-RPC, per-model
   impact node ≡ python on the mixed fixture, `(none)` bucket convention, guards + Sev-1 rot
   intact — parity case `refuter-impact`, notes row `planning/parity-notes.md:21`. Gap (c) →
   the guide. Nothing load-bearing is silently missing from scope; the deferred items are the
   two verified above and are stated in guide, dag `_meta`, and dev docs alike.
5. **Env-hygiene fixes are correct and break no legitimate caller.** `gate.sh` exports
   `HB_DIR PROJECT_DIR DAG_FILE EVENTS_FILE GATE` (`plugin/templates/gate.sh:19-24,207`) and
   the fixtures' copied `hb.js` honors env `HB_DIR` (`hb.js:30`) — so a suite run *as a gate
   criterion* would silently point dozens of fixtures at the calling project. The unsets at the
   top of `tests/run-tests.sh:13`, `tests/parity.sh:12`, `tests/parity-fuzz.sh:19` (correctly
   broader than advertised: also `DAG_FILE`/`EVENTS_FILE`/`G`) fix exactly that. I grepped all
   docs and tests: `HB_DIR`/`PROJECT_DIR` are documented only as gate-criterion env
   (`docs/dev-plugin.md:52,241`) and CLI dir-resolution fallback (`docs/dev-python.md:51`) —
   never as a suite input; the suites build all fixtures in `mktemp` dirs. The sanctioned
   suite-level override, `HB_PY_SRC`, is preserved (`${HB_PY_SRC:-…}` in both parity scripts).
6. **Freshness.** `docs/dev-tests.md:169-170` (T163/T164 rows), `planning/parity-notes.md:20-21`
   (tokens `Refute-prompt --json`, `Review-event model field`), and the refuter-profile
   paragraphs in `docs/dev-plugin.md:183` / `docs/dev-python.md:103-110` all describe current
   state accurately, no version narrative.

## Findings that DO land (the guide misstates its own evidence)

**Finding 1 — "models stamped" overclaims the repo's own impact report**
(`docs/howto/tier-the-refuter.md:87-91`). The Proof section closes: *"both phases' gate reviews
ran on a profile-bound cheap model, which caught two real defects … — catches recorded, models
stamped, visible in this repo's own impact report."* The catches are real and recorded — but the
GATE_RE1 review events carry **no model field at all** (`.hb/events.jsonl`: `review_failed`/
`review_passed GATE_RE1`, actor `refuter-sonnet`, model key absent — the `--model` flag did not
exist until RE2 shipped, unavoidable spec-first ordering), so this repo's own impact report shows
the RE1 catch under the `(none)` bucket: `node .hb/hb-report.js .hb --json` →
`GATE_RE1 … models {"(none)": {caught:1, cleared:1}}`; only GATE_RE2's catch is stamped `sonnet`.
"Models stamped" (plural, over both phases' reviews) is contradicted by the log the sentence
cites. In a guide whose fourth limit is precisely about what the model field can and cannot
attest, the dogfood sentence must be exact — the honest version ("RE1's review predates the
flag, so its catch sits in the `(none)` bucket — the null convention demonstrating itself; RE2's
is stamped") is *stronger*, not weaker.

**Finding 2 — the guide points "watch the per-model impact" at a surface that doesn't show it**
(`docs/howto/tier-the-refuter.md:47-51`, load-bearing for limits 1-2). The guide states
*"`hb report` breaks refuter impact down per model: caught vs cleared, per lens."* The per-model
breakdown exists **only in the JSON output** (`refuters.gates[].models`): the human-readable
render in both runtimes prints per-gate/per-lens totals and findings but no per-model line
(`plugin/templates/hb-report.js:159-163`, `py/src/heartbeat/report.py:83-88`; confirmed by
running both on this project). A reader following the guide's own verification step — and its
limit 2, "watch the per-model impact report before trusting a downgrade" — runs `hb report` and
cannot see the data they were told to watch. T164 proves the mechanism via `hb report --json`;
the guide claims it for the bare command. Fix is one of: say `hb report --json` (with the jq/py
one-liner), or add the per-model line to both renders (a shared-surface change → parity case).

Neither finding weakens the mechanisms (all proven, all green); both are claims-vs-evidence
defects in the shipped guide — the exact class this repo's docs-as-verified-claims rule (AGENTS
rule 7) exists to catch, and below the grep-resolution of criterion re3y.

VERDICT: REFUTED (round 1)

## Round 2

Round-1 verdict was recorded (`review_failed GATE_RE3 model='fable'` in `.hb/events.jsonl` — now
itself a stamped line in the impact report: `GATE_RE3 [default] · fable: caught 1, cleared 0`).
Re-verification of the fixes and the newly disclosed log recovery, everything re-run on the
current working tree (the round-2 diffs are uncommitted; my round-1 suite runs predated them):

**(a) Per-model breakdown now renders in both text reports — verified live, not by diff alone.**
`node .hb/hb-report.js .hb` and `PYTHONPATH=py/src python3 -m heartbeat.cli report --dir .`
both print `· <model>: caught N, cleared M` under each gate's lens with identical numbers
(`GATE_RE1 · (none): 1/1`, `GATE_RE2 · sonnet: 1/1`, `GATE_RE3 · fable: 1/0`). The diffs are
surgical mirrors (`plugin/templates/hb-report.js:162-163`, `py/src/heartbeat/report.py:87-88`),
both deterministically sorted, same format string.

**(b) The revised guide matches the shipped behavior.** `prose-check.sh` → `ALL-PROSE-OK:1`,
`index-coverage.sh` → `INDEX-COVERAGE-OK`. `docs/howto/tier-the-refuter.md:47-50` now describes
exactly the real render line plus the `--json` path (`refuters.gates[].models`) — finding 2
closed at the root. The history paragraph (`:89-95`) now states the truth of finding 1: the
first catch predates the flag and sits in `(none)`, framed as the ordering debt made visible.
Residual nit, non-blocking: the RE1 *clearing* pass (16:46Z, also pre-flag) is unstamped too, so
the `(none)` bucket shows `caught 1, cleared 1` while the sentence names only the catch — every
post-flag verdict IS stamped (sonnet ×2, fable ×1), so the claim holds under its natural
pre/post-flag reading; "the first review *cycle*" would be airtight.

**(c) Log recovery audited line-by-line — clean.** Scripted diff of
`.hb/events.polluted.jsonl` (273 events) vs `.hb/events.jsonl` (91): the kept 91 are a
**byte-identical, order-preserved subsequence** of the polluted file; all 182 dropped lines are
foreign (fixture gates/tasks: `A`×55, `P0T1`×48, `P0T2`×19, `A0T1`×16, `T1`×16, `Z0T1`×10,
`GATE_P0`×9, `GA0`×9); **zero plan-native events dropped or altered**; zero foreign events kept
(the only neither-field survivor is the single `initialized`); all 5 native review events —
the RE1/RE2/RE3 review trail — byte-intact; zero foreign lines appended after recovery. The
rebuilt projection is consistent: `completed_phases [RE1, RE2]`, current RE3, 8/8 tasks,
`pending_reviews [GATE_RE3]`. The polluted original is preserved as evidence, and the cleaned
impact report now tells only the plan's own story (round 1's `GA0`/`GATE_P0` rows were that
pollution — my round-1 report readings included foreign fixture reviews without knowing it).

**(d) Recurrence closed for every path that can touch this log.** The incident's channel was
suite-under-gate (re3z runs `run-tests.sh` as a criterion; `gate.sh:19-24` exports
`HB_DIR`/`PROJECT_DIR`/`DAG_FILE`/`EVENTS_FILE`; fixture `hb.js:30` honors env `HB_DIR`). Now:
`run-tests.sh:13`, `parity.sh:12`, `parity-fuzz.sh:19` unset all five at top — covering every
proof they invoke — and both RE proofs carry their own unsets (`refuter-model-routing.sh:21`,
`refuter-model-provenance.sh:19`), as does the whole refuter-family. re3x's checkers
(`prose-check.sh`, `index-coverage.sh`) never touch `hb.js`; re3y is pure grep. Advisory,
pre-existing, outside RE scope: ~15 other gate-example proofs drive fixture `hb.js` without
their own unset (safe under the suites, exposed only if wired directly as a gate criterion in
some other dogfood project) — a follow-up sweep, or fixing the root (`hb.js` letting env
`HB_DIR` override `__dirname` in a per-project copy), would close the class.

**Exit bar re-confirmed on the fixed tree:** node suite **421 passed, 0 failed, ALL GREEN**,
T163+T164 in GROUPS-PASSED; `parity.sh` **PARITY OK** (incl. `refuter-impact`,
`refute-prompt:json`, `:json-order`); pytest **115 passed**.

Both round-1 defects are fixed at the root, not papered over; the recovery is forensically
clean with the original preserved; the recurrence defense covers every path this plan
exercises. The residual wording nit and the gate-example sweep are non-blocking advisories.
I could not refute that RE3 — and the feature — is done.

VERDICT: CLEAR
