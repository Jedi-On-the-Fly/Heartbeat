# GATE_SC refutation attempt — phase SC ("Scale + parity") of the research adapter

**Phase:** SC (in `planning/research-adapter-testing.dag.json`, `gate_exit: GATE_SC`).
**Claim under refutation:** a deterministic seeded generator builds a large messy corpus and a proof
shows the research adapter stays node ≡ python BYTE-identical and fast at scale; wired as T115.

**Role:** adversarial reviewer. I tried to make the proof lie — generate non-determinism, a cosmetic
(no-op) corpus, a parity check that can't catch a real divergence, dishonest counts, or a hollow perf
guard. Below is every probe, with commands and results. Real files left untouched (all mutation done in
`mktemp` copies); working tree verified clean afterward.

---

## 1. Determinism — COULD NOT REFUTE

Generated the corpus into two independent temp dirs and compared byte-for-byte:

```
node gen.js "$d1"; node gen.js "$d2"; diff -r "$d1" "$d2"   # -> IDENTICAL (empty diff)
```

`diff -r` was empty → byte-identical. Grepped the generator for any time/randomness source
(`Date`, `Date.now`, `Math.random`, `process.hrtime`, `performance`, `new Date`) → **none**. Every value
is derived from the claim index `i` (`pad3(i)`, `i % NS`, `i % 4`, `i % 5`). Counts confirmed: 60 sources,
200 claims, 60 source files. Deterministic as claimed.

## 2. Messy corpus is REAL, not cosmetic — COULD NOT REFUTE

Generated and inspected:

- **Unicode is present in BOTH sources and excerpts.** All 60 source files contain `°C`, `»`, `é`, `—`
  (`grep -rl` → 60/60 each). 160 grounded excerpts each contain `°C`, `»`, `é` (verified via a Python
  scan over `evidence.json`). Not decoration confined to filler — it's in the actual bytes being matched.
- **The line-wrap is genuinely injected and normalization is NOT a no-op.** For grounded claim `c_001`
  the excerpt (`'finding 001 — measured 1°C effect » in cohort é'`, single space) is **NOT** present
  verbatim in the stored source (`in body` → False); the stored form has the first space replaced by a
  newline (`excerpt.replace(' ','\n',1) in body` → True). So `ground-check` MUST whitespace-normalize to
  match. Proven decisively in §3: a mutant that drops normalization takes grounded from 160 → **0**.
- **Multi-claim-per-source is real.** All 60 sources are cited; every source is cited by >1 claim
  (min 3, max 4 claims/source).
- **Exactly 40 fabricated / 160 grounded.** `grep -c NOTINSOURCE evidence.json` → 40; those tokens appear
  in **zero** source files (`grep -rc NOTINSOURCE sources` → none). Running ground-check on both runtimes
  reports `grounded=160 issues=40` with 40 `FABRICATED-QUOTE` lines (`c_000, c_005, … c_195`, i.e. i%5==0).

## 3. Parity is GENUINE (the decisive test) — COULD NOT REFUTE

Copied py/src + the research adapter + the proof into a `mktemp` tree so the proof's `$ROOT` resolved to
the mutant, then introduced ONE real divergence per run:

**Mutant A — research_context.py:** changed the excerpt prefix `"    » %s"` → `"    >> %s"` (a subtle
one-char formatting change on ONE runtime). Ran the proof against the mutant:
```
FAIL: research-context node vs python differ for section background   (exit=1)
```
RED. The marker did NOT print.

**Mutant B — ground_check.py:** changed `_norm` from `re.sub(r"\s+"," ",s).strip()` to `(s).strip()`
(normalize differently on ONE runtime). Python ground-check then reported `grounded=0 issues=200`
(the line-wrap now fails to match), and the proof:
```
FAIL: ground-check node vs python differ at scale
< HB-GROUND: grounded=160 issues=40
> HB-GROUND: grounded=0 issues=200        (exit=1)
```
RED. This simultaneously proves (a) the byte-identity check has teeth and (b) the corpus's line-wrap
genuinely exercises normalization — remove it and 160 claims stop matching.

Both a formatting divergence and a normalization divergence are caught. The proof is genuinely comparing
the two runtimes, not stubbing one. Real files were restored between runs; not touched.

## 4. Counts honest / full processing — COULD NOT REFUTE

Both runtimes iterate `sorted(claims.keys())` over all 200 claims and produce `grounded=160 issues=40`
(all 40 fabricated ids listed). The proof asserts `grep -q 'grounded=160 issues=40'` (line 28) AND the
final marker embeds `grounded=160 issues=40` (line 43). A silently-shrunk corpus would change these
numbers and both the count grep and the marker grep in T115 would fail. Honest.

## 5. Timeout guard — **REFUTED (this point)**

Clean proof run: **0.475s** — not flaky, comfortably under the 20s `timeout` ceiling.

But the proof (line 24) and the how-to (§"The two guarantees", lines 43-45) both explicitly claim the
`timeout` is *"a perf guard: a regression to quadratic behaviour on 200 claims blows the ceiling and
fails."* I tested that claim directly by simulating the exact regression named — for each claim, scan
every source file (O(claims × sources) = 200 × 60 = 12,000 file reads instead of 1 per claim):

```
node on2.js  ->  grounded 160  ms 115
```

**A genuine O(n²) regression completes in ~115ms — nowhere near the 20s ceiling; it would sail straight
through the proof, GREEN.** To actually breach 20s I had to construct an O(claims² × sources) blow-up
(2.4M file reads), which lands at **20.18s** — right on the boundary, i.e. a coin-flip that would make
the proof *flaky* rather than a reliable guard. So the timeout as calibrated:
  - does NOT catch the quadratic regression the docs claim it catches (off by ~170×), and
  - only trips on a far-worse regression, and then only marginally/flakily.

The `timeout` wrapper is effectively an anti-hang backstop, not the "O(n²) perf guard" the proof and
how-to advertise. The corpus (200 claims / 60 sources) is too small, or the ceiling (20s) too loose, for
the stated perf-guard guarantee to hold. The prose in `scale-test-the-research-adapter.md` and the
comment in `research-scale-parity.sh` overclaim what the guard does — a doc-is-a-claim violation
(AGENTS.md rule 7) and a hollow-guarantee gap in the phase's stated contract.

## 6. Zero-padded ids → identical sort — COULD NOT REFUTE

```
node: Object.keys(claims).sort()   vs   python: sorted(claims.keys())   -> diff -> IDENTICAL
```
`c_000 … c_199`, fixed-width, ASCII → UTF-16-code-unit sort ≡ code-point sort. Confirmed identical.

## 7. How-to honesty + suites — MOSTLY green, one honesty gap

- **Listed:** `howto-list.md` line 42 lists it, tagged T115. Referenced `planning/research-adapter-scope.md`
  exists. Both stamp-evidence twins exist.
- **Node suite:** `333 passed, 0 failed`; T115 present in `GROUPS-PASSED`.
- **Python suite:** `96 passed`.
- **Parity:** `PARITY OK — node ≡ python`.
- **Audit:** `node plugin/templates/hb-audit.js planning/research-adapter-testing.dag.json` →
  `✓ gates look behavioural (0 warning(s))`.
- **Honesty gap:** the how-to's guarantee #2 ("a regression to quadratic behaviour on 200 claims blows the
  ceiling and fails") is FALSE per §5 — an O(n²) regression runs in 0.115s and passes. The doc claims a
  guarantee the proof does not actually deliver.

Working tree left clean (the only tracked-file diffs — `howto-list.md`, `run-tests.sh` — are the SC
phase's own uncommitted deliverables, not my edits; all mutation was in temp copies, now removed).

---

## Verdict

Points 1, 2, 3, 4, 6 hold solidly: determinism is real, the corpus is genuinely messy (unicode +
line-wrap that a mutant proves is load-bearing), parity is genuine (two independent real divergences go
RED), counts are honest, sort order is identical, and all suites/audit are green. The decisive parity
test passed — this is a real oracle, not a rubber stamp.

However, the phase's stated contract includes a **perf guarantee that is not delivered**: the `timeout`
is advertised (in both the proof comment and the how-to) as catching an O(n²) regression on 200 claims,
but a genuine O(n²) regression completes in ~115ms — ~170× under the 20s ceiling — and would pass GREEN.
The guard only trips on a much-worse-than-quadratic blow-up, and then only at the flaky boundary. The
how-to therefore makes a false behavioral claim (AGENTS.md rule 7: a doc is a claim), and the "fast at
scale / perf divergence caught" half of the SC claim is not backed by the proof. That is a substantive,
concrete hole in the phase's stated done-ness.

VERDICT: REFUTED

---

# RE-REVIEW (post-fix) — phase SC ("Scale + parity"), adversarial

**Context.** The prior attempt (above) REFUTED phase SC for ONE reason: the proof comment and the how-to
claimed the `timeout` was an O(n²) perf guard, but a genuine O(n²) regression at 200 claims runs in
~115ms — ~170× under the 20s ceiling — so the guard catches nothing quadratic. A false behavioral claim
(AGENTS.md rule 7). The stated fix REMOVES the perf-guard claim and re-describes the timeout as an
anti-hang backstop. I re-tried to refute, concretely. Real files untouched; all mutation in `mktemp`
copies; working tree verified clean.

## 1. Timeout honesty — where the fix LANDED, and where it did NOT

**Fixed, and honest, in the two files the task named:**
- `research-scale-parity.sh` (lines 8–9, 26): now reads *"wrapped in `timeout` as an anti-hang backstop
  … a coarse ceiling, NOT a fine-grained perf-divergence check."* No `O(n`, no "perf guard", no
  "quadratic", no "fast". `grep -niE 'O\(n|perf guard|quadratic|\bfast\b|performance'` over the proof →
  **zero hits**.
- `scale-test-the-research-adapter.md` — guarantee #2 (lines 43–46) now reads *"A hung runtime fails
  fast. … deliberately *not* a fine-grained performance-divergence check — parity, not speed, is what
  this proof asserts."* The only two grep hits are this honest disclaimer. The how-to still correctly
  claims what IS true: byte-identical node≡python at scale, a deterministic generator (no time/random),
  planted unicode + line-wraps, and known 160/40 counts proving full processing. Prose-check GREEN
  (`PROSE-OK:scale-test-the-research-adapter.md`).

**BUT the same refuted claim SURVIVES, verbatim, in the SC phase's own deliverables** (grep over the
related files, not just the two named):

  a. `planning/research-adapter-testing.dag.json` **line 37** (task SC1's description — the phase's own
     gate contract) still says, word for word:
     > "the ground-check run completes within a `timeout` ceiling **(a perf guard against an accidental
     > O(n^2) blowup)**"
     This is the EXACT false claim the prior review refuted — an O(n²) blowup does NOT breach the
     ceiling (proven above at ~115ms). The fix scrubbed the proof and the how-to but left the lie in the
     DAG that defines what "SC done" means.

  b. `planning/research-adapter-testing.dag.json` **line 29** (SC title) and `tests/run-tests.sh`
     **line 1382** (T115 group label, printed live into suite output: *"node ≡ python **and fast** on a
     large generated corpus"*) both still assert the refuted "fast at scale" half. The T115.1 *check*
     text was fixed to "within a timeout ceiling", but the group banner it prints was not.

The task's own instruction — *"Any remaining overclaim about speed/performance → REFUTE"* — is triggered.
The phase's stated contract (the DAG task) still advertises a perf guarantee the proof does not deliver.
This is the same AGENTS.md rule-7 doc-is-a-claim violation, merely relocated from the proof/how-to into
the DAG + suite label. **Point 1: REFUTED (overclaim persists in DAG line 37 + title/T115 label).**

## 2. Parity is the real teeth (decisive) — COULD NOT REFUTE

Mirrored `py/src`, the research adapter, and the proof into a `mktemp` tree (so the proof's `$ROOT`
resolved to the mutant), then introduced ONE real per-runtime divergence:

- **Mutant A — `research_context.py`:** `"    » %s"` → `"    >> %s"` (one-char format change on ONE
  runtime). Proof: `FAIL: research-context node vs python differ for section background` (exit 1). RED.
- **Mutant B — `ground_check.py`:** `_norm` `re.sub(r"\s+"," ",s).strip()` → `(s).strip()` (drop
  whitespace normalization on ONE runtime). Proof: `FAIL: ground-check node vs python differ at scale`,
  diff `grounded=160 issues=40` vs `grounded=0 issues=200` (exit 1). RED — and this simultaneously proves
  the planted line-wrap is load-bearing (remove normalization and all 160 grounded claims stop matching).

Real files restored between runs; temp tree removed. The proof is a genuine two-runtime oracle, not a
stub. **COULD NOT REFUTE.**

## 3. Generator soundness — COULD NOT REFUTE

- **Deterministic:** `node gen.js d1; node gen.js d2; diff -r d1 d2` → empty (byte-identical). Generator
  has no `Date`/`Math.random`/`hrtime` — every value derived from index `i`.
- **Unicode + line-wraps genuinely exercised:** sources + grounded excerpts carry `°C » é —`; every
  stored grounded excerpt has its first space → `\n` (`excerpt.replace(' ','\n')`), and Mutant B proves
  normalization is required to match (160→0 without it).
- **Counts:** `claims=200 fabricated=40 (i%5==0) grounded=160`; `grep -c NOTINSOURCE evidence.json` = 40;
  60 source files. All 200 processed (marker asserts `grounded=160 issues=40`). **COULD NOT REFUTE.**

## 4. Sort parity — COULD NOT REFUTE

`node Object.keys(claims).sort()` vs `python sorted(claims.keys())` on the zero-padded ids → `diff`
empty. Fixed-width ASCII ids make UTF-16-code-unit sort ≡ code-point sort. **COULD NOT REFUTE.**

## 5. Suites + hygiene — GREEN

- Node: `RESULT: 333 passed, 0 failed`; T115 in `GROUPS-PASSED`.
- Python: `96 passed`.
- Parity: `✅ PARITY OK — node ≡ python`.
- Self-audit: `SELF-AUDIT-OK:68/66 (parity:ok)`.
- Prose-check on the how-to: `PROSE-OK` / `ALL-PROSE-OK:1`.
- `hb-audit planning/research-adapter-testing.dag.json` → `0 warning(s)`; `hb-lint` → `0 warning(s)`.
- How-to listed (`howto-list.md` line 42, tagged T115) and references the real proof
  `research-scale-parity.sh`. Suites/hygiene: clean.

Working tree left clean — the only tracked diffs (`howto-list.md`, `run-tests.sh`) are SC's own
uncommitted deliverables, not mine; all mutation was in removed temp copies.

## Verdict

The honesty fix is REAL but INCOMPLETE. Points 2–5 hold: parity is a genuine oracle (two independent
real divergences go RED), the generator is deterministic with load-bearing unicode/line-wraps, counts are
honest, sort is byte-identical, and every suite/audit/lint/prose check is green. The proof and how-to no
longer claim a perf guard.

However the refuted overclaim was not fully removed — it survives verbatim in the phase's own contract:
`research-adapter-testing.dag.json` line 37 still says the timeout is *"a perf guard against an accidental
O(n^2) blowup"* (the exact claim proven false — an O(n²) regression runs in ~115ms, ~170× under 20s), and
the SC title (line 29) + the T115 suite banner (`run-tests.sh` line 1382) still advertise the adapter as
*"fast"* at scale. Per AGENTS.md rule 7 and the task's explicit "any remaining overclaim about
speed/performance → REFUTE", the phase's stated done-ness still contains a false behavioral claim.
Scrubbing the proof and how-to while leaving it in the DAG task and the printed suite label is a partial
fix. To clear SC: strike "(a perf guard against an accidental O(n^2) blowup)" from DAG line 37 and drop
"and fast"/"fast" from the SC title and the T115 group label (honest wording: "within a timeout ceiling"
/ "anti-hang backstop", as the proof and how-to now say).

VERDICT: REFUTED

---

## FINAL RE-REVIEW (round 3) — 2026-08-20

Third and final adversarial pass on phase **SC** (`planning/research-adapter-testing.dag.json`,
`gate_exit: GATE_SC`). This phase was refuted TWICE for a single dishonesty: a false claim that the
`timeout`/harness catches perf / O(n²) / quadratic regressions. Round 1 fixed the proof + how-to; round 2
found the overclaim SURVIVED in the DAG task text, the phase title, and the T115 suite banner. A further
fix claims to have scrubbed those plus the `_meta` note, the SC3 description, and the SC review prompt.
My job: confirm the honesty fix is COMPLETE and the phase's real value (node ≡ python parity at scale) is
intact. All mutation done in `mktemp` copies; working tree verified clean afterward.

### 1. Overclaim fully gone — the decisive check — COULD NOT REFUTE
Ran the mandated grep across all four SC deliverables:
`grep -rniE 'perf|fast|O\(n|quadratic|speed' <dag> <run-tests.sh> <proof> <how-to>`. Classified EVERY hit:

- `scale-test-the-research-adapter.md:43-46` — "A hung runtime fails fast … a coarse ceiling, deliberately
  *not* a fine-grained performance-divergence check — parity, not speed, is what this proof asserts."
  → (a) honest disclaimer.
- `research-scale-parity.sh:8-9` — "`timeout` as an anti-hang backstop … a coarse ceiling, NOT a
  fine-grained perf-divergence check." → (a) honest disclaimer.
- `research-adapter-testing.dag.json:37` (SC1 desc) — "wrapped in `timeout` as an anti-hang backstop
  (a hung/looping runtime fails the proof instead of blocking the suite — NOT a fine-grained perf check)."
  → (a) honest disclaimer.
- `research-adapter-testing.dag.json:49` (SC3 desc) — "the timeout as an anti-hang backstop (NOT a perf
  check)." → (a) honest disclaimer.
- `research-adapter-testing.dag.json:72` (SC review prompt) — now AFFIRMATIVELY demands honesty: "Is the
  timeout described HONESTLY as an anti-hang backstop with NO residual overclaim (anywhere … proof,
  how-to, DAG text, or suite label) that it catches perf / O(n^2) regressions?" → (a) — the prompt is the
  guardrail, not an overclaim.
- `run-tests.sh:232 / 246 / 253 / 797` (`T18.2 fast timeout`, `T20 fast reclaim`, `fast-determinism-check`)
  → (b) unrelated pre-existing tests, nothing to do with SC.

Also directly inspected the spots round 2 flagged and the fix claims to have scrubbed:
- **`_meta.note`** — now "the run completes within a timeout anti-hang backstop" (was "…encoding/sort/perf
  divergences"). Clean.
- **Phase title** (`SC.title`) — "Scale + parity — the adapter stays node ≡ python on a large messy
  corpus." No perf claim.
- **T115 suite banner + label** (`run-tests.sh:1382-1384`) — banner: "node ≡ python on a large generated
  corpus (60 sources / 200 claims, unicode, line-wraps)"; label: "…within a timeout ceiling". No perf claim.
- **GATE_SC.desc** — "the run stays within a timeout ceiling". Honest.

`git diff` on the two tracked deliverables is EXACTLY the scrub: every removed line carried the overclaim
("a perf guard against an accidental O(n^2) blowup", "sort-order / perf divergences", "a meaningful perf
ceiling", "encoding/sort/perf divergences"); every added line replaced it with anti-hang/ceiling wording
plus an explicit "NOT a perf check". Zero category-(c) survivors. The overclaim is gone from proof,
how-to, DAG note, DAG title, all three task descriptions, the review prompt, and the suite label.

### 2. Parity teeth still real — COULD NOT REFUTE
Copied `py/src` to a `mktemp` dir and mutated the Python twin's `_norm` in `ground_check.py` from
`re.sub(r"\s+", " ", …)` to `re.sub(r"[ \t]+", " ", …)` (a realistic bug: collapse spaces but not
newlines). Generated a corpus with the real generator, ran real-node vs mutated-python ground-check
exactly as the proof does. Result: **RED** — `HB-GROUND: grounded=160 issues=40` (node) vs
`grounded=0 issues=200` (mutated python); the byte-identical `[ "$jn" = "$py" ]` guard would fail and the
proof aborts before printing the marker. This simultaneously proves (i) the parity check has teeth and
(ii) the injected line-wraps genuinely exercise newline normalization on every grounded claim — a twin
that mishandles newlines fails all 160. Real files untouched (temp copy deleted).

### 3. Everything true is still claimed & holds — COULD NOT REFUTE
- **Deterministic:** two generator runs → `diff -r` clean (byte-identical).
- **Counts:** 60 sources, 200 claims, exactly 160 grounded / 40 issues (proof asserts
  `grounded=160 issues=40`, which also proves the whole corpus is processed, not bailed early).
- **Zero-padded ids:** `c_000..c_199`, `s_00..s_59`; every claim id's numeric part is width-3 → identical
  node `Array.sort` / python `sorted` order.
- **Unicode:** `° » é —` present in generated source files.
- The how-to still honestly claims **node ≡ python, byte-identical at scale** (§"The two guarantees").

### 4. Suites / hygiene — COULD NOT REFUTE
- Node: `bash tests/run-tests.sh` → **333 passed, 0 failed**; **T115 present in GROUPS-PASSED**.
- Python: `pytest -q` → 96 passed.
- Parity: `bash tests/parity.sh` → PARITY OK — node ≡ python.
- Self-audit: `SELF-AUDIT-OK:68/66 (parity:ok)`.
- Prose: `prose-check.sh scale-test-the-research-adapter.md` → `ALL-PROSE-OK:1`.
- How-to listed in `docs/howto/howto-list.md` (line 42, tagged T115) and references the real proof.
- `hb-audit` on the DAG → **0 warnings** (gates behavioural); `hb-lint` → **0 warnings** (DAG valid).
- Real scale proof itself → `SCALE-PARITY-OK sources=60 claims=200 grounded=160 issues=40`.

### Conclusion
The single dishonesty that sank rounds 1 and 2 is now eradicated across every SC surface — proof, how-to,
DAG `_meta` note, phase title, all three task descriptions, the review prompt, GATE_SC.desc, and the T115
suite banner/label. The timeout is honestly framed everywhere as an anti-hang backstop, explicitly "NOT a
perf check". The phase's genuine value — a deterministic messy-corpus generator whose byte-identical
node≡python comparison has demonstrable teeth (a subtle Python-twin mutation went RED) — is intact and
fully wired (T115) and documented. All suites, parity, audit, lint, prose, and self-audit are green.
Working tree verified clean after all probes.

VERDICT: COULD NOT REFUTE
