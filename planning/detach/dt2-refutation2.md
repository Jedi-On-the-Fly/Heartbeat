# GATE_DT2 refutation — ROUND 2, after the fix pass

Refuter: adversarial reviewer (same persona/checklist as round 1). All probes ran in mktemp
fixtures and repo COPIES; the repo tree and its live `.hb/` were never touched. Fixture: the
detach-surfacing two-phase dag (P → GATE_P → D → GATE_D), bootstrapped per fixture.

Round 1 REFUTED on P2 only: dev-plugin.md claimed a stamp-mismatched OR missing detach anchor is
"said aloud by doctor", while both doctors' suffix keyed on anchor EXISTENCE only. This round
re-runs that exploit against the fix and spot-checks everything round 1 verified clean.

## 1. The round-1 exploit, re-run — and the full four-state agreement matrix

Probe script: `dt2r2-probe.sh` (scratchpad). Per state, per runtime: doctor output + exit,
suffix presence, and whether `hb changed GATE_D` widened to `_start`.

| State | node suffix / changed widened | python suffix / changed widened | doctor exit |
|---|---|---|---|
| healthy (untampered anchor) | no / no (`_detach_D → worktree`) | no / no | 0 / 0 |
| **stamp tampered** (`detached_at` → 1999) — the round-1 exploit | **YES / YES** | **YES / YES** | 0 / 0 |
| other field tampered (`commit`, `files` mutated; stamp intact) | no / no | no / no | 0 / 0 |
| anchor missing (`rm _detach_D.json`) | YES / YES | YES / YES | 0 / 0 |

- The round-1 exploit is DEAD: on the stamp-tampered fixture both doctors now print
  `… re-audit before relying on the order (no detach anchor — change reports widen to _start)`
  and still exit 0 (a NOTE), while `hb changed` reports
  `no entry anchor '_start' for GATE_D` on both runtimes — doctor and changed() agree.
- Healthy: no suffix, changed diffs against `_detach_D`. Other-field tamper: no suffix, no
  widening — the stamp is the predicate, exactly changed()'s (hb.js l.651–652 /
  anchors.py l.148–149). Missing anchor: suffix, widened — as before.
- Doctor says the suffix exactly when changed() widens, in all four states, on both runtimes.

Predicate identity (source): node doctor l.419 IIFE `(a && a.detached_at === p.detached_at)` is
verbatim changed()'s condition (hb.js l.652). Python doctor l.158
`(read_anchor(…) or {}).get("detached_at") == p.get("detached_at")` vs changed()'s
`_da and _da.get("detached_at") == phase.get("detached_at")` (anchors.py l.149) — textually
different, and I hunted the gap:

**Corner probed (not a finding — sealed by lint):** with the anchor deleted AND the phase's
`detached_at` hand-removed (or nulled on both sides), the two python conditions diverge
(`None == None` suppresses the suffix while changed() widens), and node and python doctor notes
differ on the same fixture — I reproduced both (probe states cornerX/cornerY). But every such
state requires `detached_at` absent or non-string on the phase, and BOTH lints reject exactly
that (`detach fields are partial (…) — a detach records … together`, lint.py l.133 /
hb-lint.js l.157; `detached_at must be a non-empty string timestamp`, lint.py l.143 /
hb-lint.js l.162): doctor reports it as a PROBLEM, exit 1, naming the field, on both runtimes
(reproduced — cornerX doctor output shows the ✗ dag line). On every lint-valid dag
(`detached_at` a non-empty string) the python condition is exactly equivalent to changed()'s:
missing anchor → `None != "…"` → suffix; present anchor → same comparison. The divergent corner
exists only inside a dag the doctor already refuses to call healthy, with a precise repair
message; once repaired it collapses into the agreeing states above. Observation for the authors,
not a defect: making doctor.py l.158 textually mirror anchors.py l.149 (`_da and _da.get(…) == …`)
would close even the lint-rejected corner and remove a future drift trap.

## 2. The doc sentence, re-read

dev-plugin.md l.152: "STAMPED with `detached_at` (a stamp-mismatched or missing anchor reads as
missing: `_start` fallback, said aloud by doctor)" — now LITERALLY TRUE: both halves reproduced
on both runtimes in the table above (stamp-mismatch and missing each widen AND are said aloud).
Same line's "doctor NOTES (never problems) the live detach (with the anchor-missing suffix)" —
true (exit 0, suffix). Sweep of all four changed docs for claims the fix could have staled
(anchor/stamp/suffix/_start): dev-python.md l.72 ("`anchors.changed()` … with the stamp check;
doctor NOTES the live detach and both divergence directions"), dev-tests.md T182/T183 rows
("stamp-mismatch = missing"; "the `no detach anchor` suffix"), parity-notes l.339–340 ("a stamp
mismatch reads as missing (fail-closed …)") — all accurate against the shipped behavior; none
claims an existence-only suffix. Source comments checked too: hb.js l.893–895 (write-failure arm,
truthful) and the guard comment on l.419 states the new predicate explicitly.

## 3. Did the fix break anything? (suites + spots)

| Suite (this round, post-fix) | Result |
|---|---|
| `bash tests/detach-surfacing.sh` | MARKER/CLEAR/QUIET/DOCTOR/AUDIT-OK → `DETACH-SURFACING-OK`, rc=0 (DOCTOR now includes the doctor-stamp-mismatch fixture, l.96–100) |
| `bash tests/detach-surfacing.sh --selftest` | `DETACH-SURFACING-SELFTEST-OK`, rc=0 — python halves now import-check the stripped copies (l.153, l.160), mirroring node `--check`: round 1's rework note is closed |
| `bash tests/detach.sh` (+ `--selftest`) | `DETACH-OK` / `DETACH-SELFTEST-OK`, rc=0 |
| `bash tests/parity.sh` | `✅ PARITY OK — node ≡ python`, rc=0 |
| `cd py && PYTHONPATH=src .venv/bin/python -m pytest -q` (full) | 171 passed, rc=0 |
| `bash tests/run-tests.sh` (full node suite) | 472 passed, 0 failed; GROUPS-RAN 183, SKIPPED 0; T183.1/T183.2 green — ALL GREEN |

**G2 strip spot** (`dt2r2-g2g3.sh`): `sed '/detach-guard: doctor/d'` on COPIES of hb.js and
doctor.py — the stripped hb.js passes `node --check`, the stripped doctor.py imports; on four
fixtures (composed detach+regate-pending, stamp-mismatch, direction-A no-event, direction-B
re-lock) the stripped doctors exit 0 with ZERO detach lines and the non-detach findings (the
regate pending note) byte-unchanged, both runtimes. The changed l.419/l.158 lines are still
single marked lines; no structural line gained a marker (grep inventory unchanged from round 1).

**G3 byte-identity spot**: `git show HEAD:` versions of hb.js, hb-report.js, doctor.py, report.py
swapped in-place against the working-tree versions on the SAME never-detached fixtures (plain,
and regate-pending): doctor output+exit, report text, and report `--json` (minus the per-run
`"generated"` line) byte-IDENTICAL on both runtimes. The fix is invisible on untouched projects.

**G1 composed spot** (re-exercised, both runtimes): one unbroken phase line
`… ⛔ revised — rearm pending (by bob: criteria premises changed)  ⟂ detached from GATE_P (by
alice: volumes were replaced)` — regate before detach, full payloads, grep -c = 1; neither
marker in `--json` (0 hits, both runtimes); `reattach D` → ⟂ gone, ⛔ intact (both runtimes).

## Answers

P1: NOT-REPRODUCED — round 1 held on every probe; this round the fix strengthens it: suffix fires on stamp-mismatch AND missing (both runtimes, doctor exit 0 as a NOTE), agrees with `hb changed`'s widening in all four anchor states, and the full proof suite re-ran green (MARKER/CLEAR/QUIET/DOCTOR/AUDIT-OK incl. the new doctor-stamp-mismatch fixture).
P2: NOT-REPRODUCED — the round-1 exploit re-run (tamper `_detach_D.json` detached_at → 1999) now produces the "(no detach anchor — change reports widen to _start)" suffix on BOTH runtimes' doctors while `hb changed` widens, so dev-plugin.md l.152 is literally true; a sweep of all four changed docs found no claim the fix staled, and the only remaining doctor/changed() daylight lives on dags both lints reject as "detach fields are partial"/"detached_at must be a non-empty string timestamp" — a doctor PROBLEM (exit 1) naming the repair, reported above as an observation.
G1: NOT-REPRODUCED — round 1 verified fully; round-2 re-exercise of the composed fixture: one unbroken line with regate before detach and both payloads on both runtimes, zero marker text in either runtime's --json, and independent clearing (reattach leaves ⛔ intact, detach marker gone); the fix touched neither renderer (G3 byte-identity on report text and json).
G2: NOT-REPRODUCED — round-2 strip of the detach-guard: doctor class on copies: node --check passes, stripped doctor.py imports, zero detach notes and exit 0 on the composed + stamp-mismatch + A1 + B fixtures, non-detach findings byte-unchanged (both runtimes); the report-class strips are re-proven by the green --selftest, whose python halves now carry the import-checks round 1 flagged as missing (detach-surfacing.sh l.153, l.160).
G3: NOT-REPRODUCED — HEAD vs working-tree swaps of all four files on the same never-detached fixtures (plain and regate-pending): doctor output+exit, report text, and report --json (minus "generated") byte-identical on both runtimes — the fix is additive-only where no detach exists.

## Verdict

The round-1 finding is repaired by making the code match the doc, not by softening the doc: the
suffix now keys on changed()'s stamp predicate on both runtimes, the proof suite pins it with a
stamp-mismatch fixture, the selftest's python halves gained the import-checks, and every suite,
strip, byte-identity and composition probe is green. The one remaining corner where the python
doctor condition is not textually changed()'s predicate is unreachable on a lint-valid dag and is
loudly a doctor PROBLEM on both runtimes — recorded as an observation, not a finding.

SOUND
CLEAR
