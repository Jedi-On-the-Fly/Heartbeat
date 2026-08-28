# Refutation attempt (round 4) — `refuter-bench.dag.json` (plan-level, pre-build)

Actor: distinct-refuter (plan review, round 4). Round 3 returned UNSOUND on the NEW
skill-creator-alignment surface: one BLOCKER (`delta` placed as a top-level sibling of `run_summary`,
which the viewer ignores) plus minors (runs-workspace requirement of `generate_review.py`, unpinned
float-format parity, vacuous variance under stubs, ungated `--holdout`, and a `--check` that could
depend on skill-creator being installed). This round verifies EACH of those is now closed by a
CRITERION, not just prose, and hunts for holes the fixes introduce.

Ground truth re-read this round (real files, not the plan's paraphrase):
- `skill-creator/eval-viewer/viewer.html:1122` `const summary = data.run_summary || {}`; `:1157`
  `const configs = Object.keys(summary).filter(k => k !== "delta")`; `:1164` `const delta =
  summary.delta || {}`; `:1172` renders `delta.pass_rate || "—"`. So the Delta column reads
  **`data.run_summary.delta.pass_rate`**; a top-level `data.delta` is invisible and the column renders
  "—". Confirmed exactly as round 3 stated.
- `skill-creator/references/schemas.md:261-277` nests `delta` INSIDE the `run_summary` object
  (siblings `with_skill` / `without_skill` / `delta`); `:297` `configuration` must be the exact string;
  `:299` `result.pass_rate` nested; `:305` the "viewer reads these field names exactly" warning.
- `skill-creator/eval-viewer/generate_review.py:60-82` `find_runs` counts a run ONLY when a dir has an
  `outputs/` subdir (`:72`); `:387-414` `main()` takes a **workspace** positional and `sys.exit(1)` if
  `find_runs` is empty (`:412-414`); `--benchmark` (`:396-399`) is a SEPARATE optional flag feeding only
  the Benchmark tab. So opening the viewer needs a runs-workspace, not just a benchmark.json. Confirmed.

---

## Round-3 hole #1 (BLOCKER): top-level `delta` → now nested `run_summary.delta`, and load-bearing?

**Prose corrected everywhere.** `_meta`, `cb1`, `cb2`, and `rb1` now all say delta is "NESTED as
`run_summary.delta` — NOT a top-level sibling, which the viewer ignores". The builder is no longer
misdirected; the plan's asserted shape now matches viewer.html:1157/1164 + schemas.md:261-277 exactly.

**The nested PATH is now suite-gated with teeth — in CB.** `cbb` (cmd `refuter-score.sh --selftest`,
greps `SELFTEST-OK`) is described as making "the delta VALUE, and its nested `run_summary.delta` PATH
each individually load-bearing". `cb1` prose backs this: the selftest "so pass_rate, the mean/stddev
variance aggregation, the delta VALUE, and its correct NESTED PATH are EACH individually load-bearing".
So a report that computes the delta correctly but writes it at top-level `delta` must make `--selftest`
go RED. This closes the round-3 blocker: the wrong-path mutant is no longer green — it is caught in a
SUITE gate (`cbb`), in both runtimes (the proof drives node ≡ python).

**Also asserted in RB where the report is born.** `rb1` requires the report's "KEY-SET-AND-PATHS
asserted HERE in RB against the real schema (... and delta at `run_summary.delta` — a top-level delta
must FAIL this check)", enforced by `rba` (main proof, `REFUTER-BENCH-OK`). So the nested path is
checked at both the scorer boundary (CB) and the command boundary (RB).

Residual (MINOR, non-blocking): `rbb`'s selftest enumerates only "shared-compose, miss-a-bug, and
unknown-name" as its load-bearing mutations — it does NOT list a delta-path mutation. So in RB the
nested-path assertion lives in the MAIN proof body (`rba`) rather than being independently teeth-tested
by an RB selftest. That is acceptable because `cbb` already gives the path its teeth in the suite
(a top-level delta makes `--selftest` RED), and `rba` re-checks the path on the real report; the RB path
is checked, just not double-teethed. Not a hole. **Round-3 blocker: CLOSED.**

## Round-3 hole #2: `generate_review.py` needs a runs-workspace, not just benchmark.json — now gated?

**Prose corrected.** `_meta` now states the reason ("generate_review.py needs a runs-workspace (run
dirs each with outputs/) and only feeds benchmark.json to its `--benchmark` TAB — the on-demand runner
ALSO materializes that workspace"). `cd1` says the runner "emits the benchmark.json (RB) AND
materializes the runs-workspace generate_review.py requires (run dirs each with outputs/)". This matches
generate_review.py:72/412-414 exactly.

**Gated deterministically.** `cd1`'s `--check` now "validates ... the runs-workspace layout"; `cdd`'s
selftest explicitly: "a missing runs-workspace `outputs/` dir ... make `--check` go RED". So the
workspace-layout requirement is exercised by `cda` (`--check` → `CALIBRATE-READY`) and its teeth by
`cdd` (`--selftest` → `SELFTEST-OK`), WITHOUT a model. The round-3 overclaim ("reuse the viewer" while
never producing what it opens on) is closed and now behaviorally checked. **CLOSED.**

## Round-3 hole #2b: is `--check` self-contained (no generate_review.py import)?

`cd1` now states `--check` is "BEHAVIORAL and SELF-CONTAINED (validates against a LOCAL copy of the
required benchmark.json key-paths + runs-workspace layout — it must NOT import generate_review.py, since
skill-creator may be absent)". `cda`'s cmd invokes only `refuter-calibrate.sh --check`; it does not
shell to generate_review.py. So the `--check` half survives skill-creator being absent, and no SUITE
gate depends on the foreign tool. **CLOSED.**

## Round-3 hole #3: float-format parity unpinned + vacuous variance under stubs — now pinned/testable?

**Rounding convention pinned.** `cb1` requires "a pinned rounding convention"; `cb2` spells it: "ONE
pinned rounding convention, e.g. round to 4 decimals with a fixed string format, so python and node
byte-match". `GATE_CB.review` re-asks "Is the mean/stddev rounding pinned so node and python
byte-match". This addresses the `round(_,4)` (banker's) vs JS `toFixed` (half-away) divergence round 3
flagged: one fixed string format is mandated on both sides.

**Variance is no longer vacuous.** `cb1` now says `--selftest` uses "HETEROGENEOUS per-run verdicts so
stddev is non-zero (not vacuous)"; `cbb`'s desc leads with "teeth (heterogeneous per-run verdicts so
stddev≠0)"; `GATE_CB.review` asks "does cbb use heterogeneous per-run verdicts so stddev≠0". A
hard-coded `stddev=0` scorer is now caught by `cbb` — the variance aggregation is load-bearing on a
non-degenerate input. **CLOSED.** (Note: the byte-identity is still only PROVEN on the selftest's chosen
values; if those values round cleanly the last-digit divergence stays un-exercised. But the convention
is now explicitly pinned in `cb2`, so a divergent implementation is a spec violation, not an ambiguity —
acceptable. Recommend the selftest pick at least one value whose 4-decimal rounding differs between
banker's and half-away, e.g. a mean of `0.12345`, to exercise the pin; MINOR, non-blocking.)

## Round-3 hole #4: `--holdout` prose-only/ungated → now a deterministic gated split?

`cd1` now defines `--holdout` as "a DETERMINISTIC seeded split (train/test disjoint, covering all
fixtures) so the split logic is checkable without a model". `--check` validates "that the holdout split
is deterministic+disjoint+total"; `cdd`'s selftest: "a non-disjoint holdout split ... make `--check` go
RED". So the split is exercised by `cda` (part of `--check`) and its teeth by `cdd`, deterministically
and without a model. The round-3 "hollow no-op flag" risk is closed. **CLOSED.**

## Round-3 hole #5 / determinism boundary — still intact?

No SUITE gate calls a live model or requires skill-creator installed:
- `cba/cbb/cbd/cbc` — pure scorer + fixtures + wiring greps; no model, no skill-creator.
- `rba/rbb/rbc` — stub-backend (`HB_EXEC_CMD`/`HB_EXEC_CMD` dispatch) + wiring; no model.
- `cda/cdd/cdb/cdc` — `--check`/`--selftest` are model-free and self-contained (do not import
  generate_review.py); prose-check + index-coverage + roadmap grep. The live `generate_review.py`/Ollama
  path is only reached by `refuter-calibrate.sh` WITHOUT `--check`, which is deliberately absent from
  `run-tests.sh` (`cda`'s second clause `! grep -q 'refuter-calibrate' tests/run-tests.sh` proves it).
The workspace materialization is now exercised deterministically inside `--check` (stub-backed via the
RB path), so gating it did NOT smuggle a model into the suite. **Determinism boundary holds.**

## NEW holes introduced by the round-4 fixes?

- `cda` now depends on `--check` deterministically building/inspecting a runs-workspace. That is a
  no-model, stub-backed operation (RB path) — it does not pull Ollama or skill-creator into the gate. No
  new determinism leak. OK.
- Making `run_summary.delta` load-bearing in `cbb` while the delta VALUE is ALSO load-bearing there
  means `cbb` now carries four independent mutations (pass_rate, variance, delta value, delta path). The
  criterion greps a single `SELFTEST-OK`; the four-way teeth rest on `cb1`/`cbb` prose. This is the same
  "selftest is one marker for N mutations" shape used elsewhere in this DAG and across the repo — the
  intent is enumerated in both `cb1` and `cbb.desc`, so a builder dropping one mutation contradicts the
  spec. Consistent with the existing convention; not a new hole.
- Cosmetic (carried from round 3, non-gating): the reused viewer prints "With Skill" / "Without Skill"
  column headers (viewer.html:1160/1222, title-cased) which mislabel profile-vs-baseline for a refuter
  benchmark. `cd2` now explicitly handles this ("the 'With Skill'/'Without Skill' columns MEAN the
  profile-under-test vs the default baseline (the skill-creator labels are reused verbatim)"), so the
  guide will not mis-explain the columns. Closed as a claim; still cosmetic.

## Residuals (all MINOR, non-blocking)

1. RB does not double-teeth the delta PATH via its own selftest (`rbb` omits it); the path's teeth live
   in `cbb` (CB) and the path is re-checked by `rba` (RB main). Adequate.
2. Byte-identity of mean/stddev is proven only on the selftest's chosen values; recommend the selftest
   include a value whose 4-decimal rounding differs between banker's and half-away to actively exercise
   the pinned convention. The pin itself is now mandated in `cb2`.

---

## Verdict

All five round-3 holes are now closed by CRITERIA, not prose:
- BLOCKER (top-level delta): prose corrected in `_meta`/`cb1`/`cb2`/`rb1`; nested `run_summary.delta`
  PATH is suite-gated with teeth by `cbb` (a top-level delta makes `--selftest` RED) and re-checked on
  the real report by `rba` — matching viewer.html:1157/1164 + schemas.md:261-277 exactly. CLOSED.
- runs-workspace: `cd1` materializes it; `cda` `--check` validates the layout, `cdd` `--selftest` proves
  a missing `outputs/` goes RED (matching generate_review.py:72/412-414). CLOSED.
- `--check` self-contained: mandated not to import generate_review.py; `cda` never shells to it. CLOSED.
- float parity: one rounding/string convention pinned in `cb2`; `cbb` heterogeneous verdicts make
  stddev≠0 load-bearing (not vacuous). CLOSED.
- `--holdout`: deterministic disjoint+total seeded split validated by `cda` `--check` and teethed by
  `cdd` `--selftest`, no model. CLOSED.

No new hole introduced; determinism boundary intact (no suite gate needs a live model or skill-creator
installed). Remaining items are MINOR/non-blocking (RB delta-path not double-teethed but covered by CB;
recommend the float selftest exercise a rounding-divergent value).

SOUND — remaining holes: none blocking. Minors: (1) exercise the pinned rounding convention with a
banker's-vs-half-away divergent value in `cbb`'s selftest; (2) optionally double-teeth the delta PATH in
`rbb` for symmetry (already teethed in `cbb`).
