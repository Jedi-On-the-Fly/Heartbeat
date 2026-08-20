# GATE_RS refutation attempt — "The research skill — the full loop"

**Phase:** RS — the research-grounding skill documents the FULL research loop
(source → stamp → ground → refute → write) reusing the real tools, plus a worked
worked-example how-to; both prose-clean, referencing real wired proofs, no overclaim.

**Reviewer stance:** adversarial. Goal: break the claim with concrete commands.

---

## 1. Loop completeness & accuracy (real commands run as written)

The skill (`plugin/skills/research-grounding/SKILL.md`) documents all five steps under
the heading "The loop (source → stamp → ground → refute → write)":

1. **Source** — on-demand, explicitly *not* gated. No command to break.
2. **Stamp** — `node plugin/adapters/research/stamp-evidence.js evidence.json sources/` + python twin
   `python3 -m heartbeat.adapters.research.stamp_evidence evidence.json sources/`.
3. **Ground** — `node plugin/adapters/research/ground-check.js stamped.json sources/ --strict` + twin
   `python3 -m heartbeat.adapters.research.ground_check stamped.json sources/ --strict`.
4. **Refute** — `node .hb/hb-audit.js .hb/dag.json --questions <gate>`.
5. **Write** — `node plugin/adapters/research/research-context.js stamped.json <section>` + twin
   `python3 -m heartbeat.adapters.research.research_context stamped.json <section>`.

Verified against shipped code:
- Script paths all exist: `plugin/adapters/research/{stamp-evidence.js,ground-check.js,research-context.js}`.
- Python twins exist and the **module names shown resolve** (`heartbeat.adapters.research.{stamp_evidence,ground_check,research_context}`) — all ran with exit 0 (see §2).
- `--questions` flag is real: `grep -n questions plugin/templates/hb-audit.js` → line 39 doc + line 130 `argv.indexOf('--questions')`. The `.hb/hb-audit.js` path is the deployed copy of `plugin/templates/hb-audit.js`; consistent with every other how-to.
- Flags (`--strict`) correct; `--strict` returns exit 1 on any issue (verified in STALE test, §1a).

**No command in the skill is wrong or misleading.** REFUTATION FAILED on point 1.

### 1a. STALE / --strict blocking
Edited a stored source after stamping, re-ran ground-check --strict:
```
HB-GROUND: grounded=0 issues=2
STALE: c_boil — source s1 changed since fetch (sha mismatch)
STALE: c_freeze — source s1 changed since fetch (sha mismatch)
exit=1
```
Matches the skill's description exactly. Restored (in /tmp).

---

## 2. Worked example reproduced byte-for-byte

Created a temp dir with `sources/s1.txt` and `evidence.json` exactly as printed in
`docs/howto/run-a-grounded-research-project.md`, then ran the three shown commands.

**Stamp** → produced `stamped.json` with a real sha256 filled into `s1`.

**Ground-check --strict** →
```
HB-GROUND: grounded=2 issues=0   (exit 0)
```
Matches the guide's shown output at line 59 exactly, including the doc's claim that the
line-wrapped "water boils at 100 degrees Celsius / at sea level" still matches
(whitespace-normalized). Confirmed.

**research-context background** →
```
Grounded evidence for background:
  - c_boil: Water boils at 100°C at sea level.
    source s1 https://example.org/thermo
    » water boils at 100 degrees Celsius at sea level
  - c_freeze: Water freezes at 0°C.
    source s1 https://example.org/thermo
    » freezes at zero degrees Celsius
```
**Byte-for-byte identical** to the guide's shown block (lines 88–96).

Also ran the **python twins** on the same inputs: identical grounding line, identical
context block, and `diff` of node vs python stamped.json → **IDENTICAL**.

Adversarial extras:
- Added a **fabricated** claim → `FABRICATED-QUOTE: c_fake — excerpt not found in source s1` (as documented).
- Added a **method-section** claim → it did **not** leak into `background` output, confirming the guide's
  claim "a `method`-section claim would never leak in."

**No overclaim in the shown outputs.** REFUTATION FAILED on point 2.

---

## 3. Overclaim / honesty

Both docs state the boundaries explicitly:
- Skill description: "NOT a web searcher and NOT a truth oracle — it checks grounding, not truth."
- Skill body: "fetch is on-demand (non-deterministic)"; Boundary: "verifies grounding, not truth", "no live web in the gate".
- Worked example: "## 1. Source (on-demand)"; "You did **not** prove the sources are correct or unbiased";
  "HeartBeat didn't fetch or fact-check for you — it made the sourcing you did hard to fake and easy to re-verify."

`research-context.js` renders (does not re-verify) grounding — its own docstring says
"Grounding is verified upstream by ground-check — this only renders." The worked example
places ground-check --strict (step 3, the gate) *before* research-context (step 5),
so the ordering claim is honest; nothing claims research-context is itself a gate.

No drift, no "grounding = truth", no "fetches/fact-checks" claim. REFUTATION FAILED on point 3.

---

## 4. T92 skill-integrity

`bash docs/howto/gate-examples/skill-integrity.sh` →
```
SKILL-INTEGRITY-OK: 3 adapters, 12 wired proof reference(s), 0 findings.
```
The skill still declares `<!-- HB-ADAPTER: research -->` (line 8). It names proofs
`stamp-evidence.sh` (T113), `ground-check.sh` (T110), `research-context.sh` (T112) —
all exist and are wired in `tests/run-tests.sh`. Extending the skill dropped/broke no
named proof. T92.1 and T92.2 (teeth selftest) both green in the full suite. REFUTATION FAILED on point 4.

---

## 5. Prose integrity & listing

`bash docs/howto/gate-examples/prose-check.sh docs/howto/run-a-grounded-research-project.md` →
```
PROSE-OK:run-a-grounded-research-project.md
ALL-PROSE-OK:1
```
Manually verified every relative link from `docs/howto/` and from the skill resolves
(run-a-grounded..., source-and-ground-research.md, ground-research-claims.md, the two
SKILL.md links, gate-examples/, research-adapter-scope.md) — all OK, none dead.
Listed in `howto-list.md` line 40 (family B), status ✅, tagged T112/T113. No placeholder /
dead link / fake command. REFUTATION FAILED on point 5.

---

## 6. Suite reality

- `bash tests/run-tests.sh` → **331 passed, 0 failed; ALL GREEN.** T92, T110, T111,
  T112, T113 all present in GROUPS-PASSED and individually ✓.
- `cd py && PYTHONPATH=src python3 -m pytest -q` → **96 passed.**
- `bash tests/parity.sh` → **PARITY OK — node ≡ python.**
- `bash docs/howto/gate-examples/self-audit.sh` →
  `SELF-AUDIT-OK:66/64 (parity:ok) — 66 guides prose-clean; 64 referenced proofs exist and are wired; node ≡ python.`

No red anywhere. REFUTATION FAILED on point 6.

---

## Working tree

All my mutations were confined to `/tmp` (temp evidence maps, source edits). Repo
working tree contains only phase RS's own deliverables (`SKILL.md`, the new worked
example, the `howto-list.md` entry); no adapter/fixture/gate-example file was touched by
this review.

---

## Verdict

Every attack failed: the five-step loop is complete and its real commands run as
written on both runtimes; the worked example reproduces byte-for-byte (grounded=2
issues=0 and the exact context block, node ≡ python); FABRICATED-QUOTE, STALE, and
section-filtering behave as documented; both docs state fetch-is-on-demand and
grounding-not-truth with no overclaim; T92 skill-integrity, prose-check, self-audit,
all three suites, and parity are green; the guide is listed with all links resolving.

I could not refute that phase RS is done.
