# GATE_RT — adversarial refutation attempt

Phase **RT — "Red-team the gate/review boundary"**. Actor: adversarial reviewer (distinct from author).

Claim under test: a committed red-team corpus proves `ground-check` catches every MECHANICAL failure
mode and stays SILENT on truth (two grounded-but-wrong claims report `grounded`), node ≡ python; a how-to
documents the boundary; wired as T114.

Method: run the code, mutate the code under test, independently identify the semantic claims, verify the
boundary from both sides. Real `ground-check.js` and the proof were left untouched (confirmed by empty
`git diff` and a clean working tree at the end).

---

## 1. Proof teeth — mutation test (the decisive check)

I copied `plugin/adapters/research/ground-check.js` to a tempdir, mutated each copy, then ran a copy of
the proof (`docs/howto/gate-examples/ground-check-redteam.sh`) placed *in the real gate-examples dir* (so
`ROOT`/`FX` resolve correctly) with only the `GC=` line overridden to point at the mutant. Four mutations:

| Mutant | Change | Raw ground-check output | Proof result |
|---|---|---|---|
| **m1** STALE never fires | sha-mismatch condition → `false` | `grounded=4 issues=4` (c_stale now GROUNDED) | **RED** — "FAIL: expected grounded=3 issues=5" |
| **m2** flag every claim | excerpt-substring check → `true` | `grounded=0 issues=8` (c_ok/c_drift/c_context all FABRICATED) | **RED** — tally fails |
| **m3** drop FABRICATED-QUOTE | excerpt-substring check → `false` | `grounded=4 issues=4` (c_fab now GROUNDED) | **RED** — tally fails |
| **m4** *start judging truth* | flag any claim whose text has OVERREACH/OUT-OF-CONTEXT markers | `grounded=1 issues=7` (c_drift/c_context = `SEMANTIC`) | **RED** — tally fails; boundary line also violated |

Sanity: the proof against the **real** file printed `RED-TEAM-OK grounded=3 issues=5` and exited 0.

m4 is the important one: it simulates the exact regression the phase claim is about — the gate starting
to judge truth. The proof caught it (both the `grounded=3 issues=5` tally and line 30's
`grep -qE 'c_drift|c_context'` boundary assertion would fire). Every mutation went RED. **Teeth are real.**

## 2. Fixture correctness

`node plugin/adapters/research/ground-check.js .../evidence.json .../sources` →

```
HB-GROUND: grounded=3 issues=5
FABRICATED-QUOTE: c_fab — excerpt not found in source s1
MISSING-SOURCE: c_missing — stored source s_missing.txt not found
UNGROUNDED: c_noex — no excerpt
UNGROUNDED: c_nosrc — source s_undeclared not in evidence.sources
STALE: c_stale — source s_stale changed since fetch (sha mismatch)
```

- Exactly `grounded=3 issues=5`. Each mechanical class on the right claim: c_fab→FABRICATED-QUOTE,
  c_missing→MISSING-SOURCE, c_noex→UNGROUNDED, c_nosrc→UNGROUNDED, c_stale→STALE. ✓
- **c_stale is STALE, not FABRICATED** — proving sha-before-excerpt. Confirmed by reading the source:
  `s_stale.txt` literally contains the excerpt "recorded hash no longer matches", so the excerpt-substring
  test WOULD pass; yet the recorded sha in evidence.json is `deadbeef…` while the real file sha is
  `afa514df7376…`, so STALE fires first (line 40 runs before line 45). This is a genuine ordering proof,
  not a coincidence. ✓
- **c_drift and c_context absent from every issue line.** Grepping the output for `c_drift|c_context`
  returns nothing; both are counted in `grounded=3` (with c_ok). ✓

## 3. THE BOUNDARY — demonstrated independently

`node plugin/templates/hb-audit.js planning/research-adapter-testing.dag.json --questions GATE_RT`
generates a falsification checklist seeding a refuter: for grep-based criteria "could it pass on a hollow
stub…", for run-code criteria "does it pin the REAL behaviour or a weak PROXY", and the phase-claim
question "could every criterion pass while this is still broken? Is the REAL runtime exercised?"

**Independent identification (I did not look at the proof's answer key first):** reading only the corpus
sources and claims, a claim is *grounded-but-wrong* if its excerpt is verbatim in its source yet the claim
overreaches or is out of context:

- **c_drift** — source `s1` (the primary cohort study) says "green tea daily had a modestly lower
  incidence" and explicitly "the association did not establish causation." The claim's paraphrase is
  "Green tea daily PREVENTS the condition" — that is causal overreach on a modest associational finding.
  The quote is real (grounded); the paraphrase is wrong. → a review target.
- **c_context** — same excerpt, but sourced from `s_blog` (a non-primary weekly roundup that itself says
  the "caveats about causation can be safely ignored"). Real words, primary-sounding, but lifted out of
  context from a secondary source. → a review target.

I arrived at exactly {c_drift, c_context} — the two the gate reports as `grounded`. The gate is silent on
both; only a semantic reader (the distinct-actor review the how-to's `--questions` refuter drives) catches
them. Boundary demonstrated from both sides: gate catches the 5 mechanical, review catches these 2.

## 4. node ≡ python

Byte-identical on the red-team corpus. Ran both directly:

```
=== NODE ===  HB-GROUND: grounded=3 issues=5  … (5 issue lines)
=== PYTHON === HB-GROUND: grounded=3 issues=5  … (identical 5 issue lines)
```

The proof also asserts `[ "$out" = "$py" ]` internally and passed. ✓

## 5. How-to honesty

`docs/howto/red-team-a-grounding-corpus.md`:
- States plainly it verifies grounding NOT truth: "It verifies **grounding, not truth**"; "the gate
  catches mechanical fabrication and reports the semantic cases as `grounded`"; a truth-judging gate would
  be "guessing at truth — exactly the confident-but-wrong behaviour HeartBeat exists to distrust."
- The refutation closes the semantic gap without overclaiming: §"Close the semantic gap with a refuter"
  seeds questions via `--questions <gate>` and expects a *different actor* to flag c_drift/c_context.
- No overclaim that ground-check judges truth. ✓
- `prose-check.sh red-team-a-grounding-corpus.md` → `PROSE-OK` / `ALL-PROSE-OK:1`. ✓
- Listed in `docs/howto/howto-list.md` line 41, tagged T114. ✓

## 6. Suites

- `bash tests/run-tests.sh` → **332 passed, 0 failed**; T114 present in GROUPS-PASSED; T114.1 green
  (`ground-check-redteam.sh → RED-TEAM-OK`). ✓
- `cd py && PYTHONPATH=src pytest -q` → **96 passed**. ✓
- `bash tests/parity.sh` → **PARITY OK — node ≡ python**. ✓
- `node plugin/templates/hb-audit.js planning/research-adapter-testing.dag.json` → "gates look
  behavioural (0 warning(s))". ✓
- No standalone self-audit script/dag was invoked here; corpus-coherence self-audit is covered by the
  green node suite. Not a blocker for RT.

## Working tree

Left clean. Only the RT deliverables remain (modified `howto-list.md`, `run-tests.sh`; untracked
`ground-check-redteam.sh`, `red-team-a-grounding-corpus.md`, `research-adapter-testing.dag.json`,
`fixtures/redteam/`). `git diff` on `ground-check.js` and the proof is empty — code under test untouched;
no mutation-test residue (`.mut-proof.sh` and tempdir removed).

---

## Verdict per point

1. Proof teeth — **could not refute.** All 4 mutations (including the "starts judging truth" one) go RED.
2. Fixture correctness — **could not refute.** grounded=3 issues=5, each class right, c_stale proves
   sha-before-excerpt, c_drift/c_context absent.
3. Boundary — **could not refute.** Independently identified c_drift & c_context; gate reports them
   grounded; review is what catches them.
4. node ≡ python — **could not refute.** Byte-identical.
5. How-to honesty — **could not refute.** Says grounding-not-truth, refuter closes the gap, prose clean,
   listed.
6. Suites — **could not refute.** Node 332/0 (T114 green), pytest 96, parity OK, audit 0 warnings.

I attacked the load-bearing claim (the boundary + proof teeth) directly with code mutation and independent
semantic analysis and could not make the phase's proof pass while the behaviour was broken.

VERDICT: COULD NOT REFUTE
