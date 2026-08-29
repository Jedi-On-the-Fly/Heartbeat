# Refuter attempt — `hb report` REFUTER IMPACT section

Actor: adversarial refuter (did not build the feature). Date: 2026-08-29.

Feature under test: `refuter_impact(events, dag)` (py `heartbeat/report.py`) ≡ `refuterImpact(evs, d)`
(node `plugin/templates/hb-report.js`), wired into `build()`/`render()` and the report object.
`review_failed` = CATCH, `review_passed` = clear, per gate, lens = gate `review.profile`, plus findings.

Method: for each case, write a temp project (`bootstrap.sh`), overwrite `dag.json` + `events.jsonl`,
`node .hb/hb.js rebuild`, then compare the canonical `refuters` object from
`node .hb/hb-report.js --json` vs `python -m heartbeat.cli report --json` (via `build()`).

## Baseline

- `refuter-impact.sh` → REFUTER-IMPACT-OK
- `refuter-impact.sh --selftest` → SELFTEST-OK
- `tests/parity.sh` → PARITY OK (incl. `refuter-impact`)
- `tests/run-tests.sh` → 383 passed, 0 failed (T152.1/T152.2 green)
- `py pytest` → 96 passed

## 1 — Counting correctness + node ≡ python (ALL PARITY-OK)

Every case below produced byte-identical canonical JSON node vs python:

| Case | Input | Result (both runtimes) |
|---|---|---|
| multiple `review_failed` one gate | 3 fails | caught 3, findings [h1,h2,h3] |
| `review_failed` no `note` | 1 fail, no note | caught 1, findings [""] |
| gate only `review_passed` | 1 pass | caught 0, cleared 1 |
| `review_failed` gate NOT in dag.gates | GATE_MISSING | caught 1, profile null (no crash) |
| review event missing `gate` field | no gate | dropped → caught 0, gates [] |
| review event empty `gate` (`""`) | gate:"" | dropped → caught 0, gates [] |
| interleaved two gates | S-fail, C-pass, C-fail, S-pass | S{1,1}, C{1,1}, sorted C before S |
| re-opened gate (fail,pass,fail) | | caught 2, cleared 1, findings [first,second] |

Ordering (`sorted(per)` / `Object.keys().sort()`) agrees; findings preserve event order; totals correct.

## 2 — Lens (ALL PARITY-OK)

- `review.profile:"security"` → `"security"` both.
- review block but no profile → `null` both.
- NO review block, but a review event → `null`, no crash both.
- profile as number (42) → `42` both (passes through; profile treated as opaque string but numbers survive).

## 3 — Honesty / overclaim (PASS)

- Docstrings (py+node), proof header, and `dev-tests.md` T152 all state explicitly:
  "records what was caught, never what was missed (unknowable)". No claim of measuring the
  refuter's real value or blind-spot catching.
- "did the refuter earn its keep?" is bounded by the caught/cleared framing — accurate.
- The "0 caught = theater" trap is AVOIDED: render condition is `caught OR cleared`, so a
  pure-clear run renders honestly: `Refuter impact: caught 0 hole(s) across 3 review(s)`.
  A clear is shown as a real review, not hidden and not called theater. Verified live.
- `parity-notes.md` line + `dev-tests.md` T152 wording match the code behavior.

## 4 — Parity/selftest teeth (PASS)

- Sabotage node counting (count `review_passed` as caught) → `parity.sh` prints `✗ refuter-impact`
  + `❌ PARITY DIVERGENCE`. Restore → `✓ refuter-impact` + PARITY OK. **Load-bearing.**
- Sabotage node caught-increment entirely → main proof `refuter-impact.sh` FAILs with a real
  node-vs-python diff. **Main proof is load-bearing against implementation bugs.**
- `--selftest` tests synthetic constants against the proof's own grep/compare assertions (not the
  real code). It proves the proof's *assertions* have teeth (a wrong count won't match `"caught":2`),
  which is its documented intent. Note: teeth against real code come from the main proof body, not
  `--selftest`.

## 5 — Existing consumers (PASS)

`refuters` is purely additive to the report object. Consumers: `hb-exec.js` runs the TEXT report
(unaffected); T13 checks only JSON parseability + specific keys; `hb-viz`/`doctor` don't read
`refuters`. Full node suite + pytest + parity all green with the field present.

## 6 — Determinism: newlines / quotes / unicode / long / tab

Findings with `\n`, `"`, `'`, tab, `\`, 5000-char note, and unicode (`café ☃ 日本語 🔥`) all
round-trip through `hb.js rebuild` byte-for-byte. Human render truncates to first line, 100 chars,
identically in both runtimes.

### FINDING A (minor, wording) — "byte-identical" is an overclaim for non-ASCII findings

The docstrings say "Canonical shape is byte-identical node ≡ python." For a finding containing
non-ASCII, the two runtimes' `--json` byte streams DIFFER:
- node `hb-report.js --json` (`JSON.stringify`) emits raw UTF-8: `café 🔥`
- python `report --json` (`json.dumps`, `ensure_ascii=True`) emits `café 🔥`

They are **semantically identical** (both parse to `café 🔥`, verified `n==p` True), but NOT
byte-identical. This ASCII-escaping difference is **pre-existing across the whole report** (also hits
`report.project`, phase `title`) — it is NOT introduced by this feature, and the parity/proof
harnesses correctly compare via re-canonicalization, not raw bytes. So no parity contract is broken.
The only defect is the docstring/proof-header phrase "byte-identical", which is inaccurate for
non-ASCII findings; "structurally identical" (or "byte-identical for ASCII findings") would be honest.

### FINDING B (negligible, out-of-spec input) — numeric `gate` field diverges

Hand-crafted event `{"review_failed","gate":123}` → py emits `"gate":123` (int), node emits
`"gate":"123"` (JS object keys coerce to string) → genuine divergence. Also `{"gate":0}` is silently
dropped by BOTH (`if not g` / `!e.gate` treat 0 as falsy — a legit gate literally named "0" would be
dropped, consistently in both). Reachability: the real `hb review` CLI always writes `gate` from
`argv` as a string, and dag gate keys are strings, so a numeric `gate` cannot arise through the
sanctioned path (violates AGENTS rule 1 "mutate only through the CLI"). Not a real-world hole.

## Restore / cleanliness

All sabotaged copies restored (`diff -q` confirms `hb-report.js` == pre-edit backup). Proof + selftest
+ parity re-run green after restore. No scratch artifacts left in the tree; the `M` files in
`git status` are the feature under review (pre-existing uncommitted work), not my edits.

## Verdict

The feature is correct and consistent across both runtimes on every realistic input: counting,
lens, findings, ordering, empty/missing gate, unknown gate, re-open, pure-clear, unicode, long/quoted
notes. Honesty framing is sound (caught-not-missed; a clear is not theater). Parity case and main
proof both have real teeth. The two divergences found are (A) a docstring wording overclaim for
non-ASCII (pre-existing report-wide serialization difference, not a broken contract) and (B) an
out-of-spec numeric-gate input unreachable through the CLI. Neither is a functional hole in the
feature as specified.

VERDICT: SOUND — with one wording nit: replace "byte-identical" with "structurally identical"
in the py/node docstrings and the proof header, since python's `ensure_ascii` escaping makes the
`--json` bytes differ for non-ASCII findings (the values are equal, and the harness compares via
re-canonicalization, so parity holds).
