# GATE DC — "Docs ↔ claims" — adversarial refutation attempt

**Phase under review:** DC ("Docs ↔ claims"). Claim: *the confident prose is now TRUE and kept from
drifting* via (a) a real CI workflow + accurate "CI-enforced → suite locally + CI" wording (T123,
`ci-workflow.sh`); (b) honest claims — root MIT LICENSE, no unpublished `pip install heartbeat-hb`
install line, an accurate plugin-vs-pyproject version-independence note (T125, `claim-honesty.sh`);
(c) anti-drift — every `docs/howto/*.md` in `howto-list.md` and every `grp "Tnn` in `run-tests.sh`
in the `dev-tests.md` table (T124, `index-coverage.sh`).

(Note: a prior `GATE_DC.attempt.md` reviewed an unrelated "code adapter discovery" phase — name
collision. This file is the Docs↔claims review.)

Actor: adversarial reviewer (distinct from author). Method: mutate temp copies (`/tmp`, real tree
untouched — verified clean at end), read the artifacts, run the suites, probe for hollow teeth.

---

## 1. Teeth — mutation tests (all on an isolated `/tmp` copy; ROOT resolves to the copy)

| Mutation | Gate | Result |
|---|---|---|
| delete `.github/workflows/ci.yml` | ci-workflow.sh | **RED** ("no .github/workflows/*.yml") ✓ |
| remove the pytest line(s) from the workflow | ci-workflow.sh | **RED** ("workflow does not run pytest") ✓ |
| add `grp "T999 …` to run-tests.sh | index-coverage.sh | **RED** ("suite group T999 missing") ✓ |
| add unlisted `docs/howto/zzz.md` | index-coverage.sh | **RED** ("unlisted guide: zzz.md") ✓ |
| remove a dev-tests row (T123) | index-coverage.sh | **RED** ("suite group T123 missing") ✓ |
| delete `LICENSE` | claim-honesty.sh | **RED** ("no LICENSE file") ✓ |
| re-introduce `pip install heartbeat-hb` into a `.md` | claim-honesty.sh | **RED** (names the file) ✓ |
| `LICENSE` present but not MIT | claim-honesty.sh | **RED** ("LICENSE does not say MIT") ✓ |

Every headline mutation the phase advertises turns the owning gate RED. The gates are not hollow.

### Two teeth *narrownesses* found (not clean kills, but real)

- **ci-workflow pytest check is a mere `grep -qE 'pytest'`.** I removed only the pytest *run* step
  (`PYTHONPATH=src python3 -m pytest -q`) while leaving the `pip install -e py pytest` install line and
  the `- name: Python suite (pytest)` step name. The gate stayed **GREEN** — the word "pytest" still
  appears in the file. So the gate proves "the string pytest is somewhere in the YAML," not "a step
  actually runs pytest." Same shape applies to `run-tests.sh` / `parity.sh` (substring, not a run-step
  assertion). Wholesale removal is caught; surgical removal of just the `run:` is not. The header
  states an honest local boundary (validity + wiring), but the check is looser than the prose implies.

- **index-coverage guide-listing match is unanchored regex.** Line 11 is `grep -q "$b" howto-list.md`
  with `$b` an unescaped basename (e.g. `foo.md`). Two probes both stayed **GREEN** while a guide was
  genuinely unlisted: (i) listing only `barfoo.md` satisfies `foo.md` (substring); (ii) an unrelated
  token `fooXmd` satisfies `foo.md` (the `.` is a regex wildcard). So the anti-drift gate *can* pass
  with an unlisted guide whenever a confusingly-similar string coincidentally appears in the index.
  The T-number side is correctly anchored (`\| T12 ` does not match `| T120 `; verified). Latent gap,
  not currently triggered by any real guide, but it weakens the "derived-consistent" teeth.

Neither narrowness is, on its own, a false headline claim — the advertised mutations are all caught.

## 2. CI workflow — real + valid

`.github/workflows/ci.yml` is well-formed and correctly wired: `on: [push, pull_request]` (both
triggers); checkout + setup-node@20 + setup-python@3.11; `pip install -e py pytest` (installs the
package pytest imports); then three run steps — `bash tests/run-tests.sh`, `cd py && PYTHONPATH=src
python3 -m pytest -q`, `bash tests/parity.sh`. All three suites invoked; install covers pytest's
needs. Wording is now accurate: docs say "enforced by the suite (locally + CI on push)" — not a bare
"CI-enforced" overclaim; no stale overclaiming phrasing found. (GitHub Actions not runnable here;
validity + wiring assessed.)

## 3. Claims honest — **one live dishonesty survives the gate's scope**

- LICENSE is genuine MIT text (full permission grant + warranty disclaimer). ✓
- `py/pyproject.toml` is a real installable package: `pip install -e py` in a fresh venv built the
  editable wheel, `import heartbeat` works, and the `hb` entrypoint runs. The reworded quickstarts are
  truthful. ✓
- Version-independence note is accurate and consistent with T39.4: the note says plugin version lives
  in `plugin.json`, package version in `pyproject.toml`, and `marketplace.json` *mirrors the plugin
  version*; T39.4 checks exactly `plugin.json == marketplace.json` (plugin==marketplace, **not**
  ==pyproject). Actual values (plugin 1.27.0 == marketplace 1.27.0; package 0.17.0) match the note. ✓
- **BUT: `release/README.md:49` still presents `pip install heartbeat-hb` as the primary Python
  install line** ("`pip install heartbeat-hb   # or: pip install ./py from a clone`"). This is a
  git-tracked, hand-maintained, launch/release-facing README, updated across v1.25–v1.27. It is
  exactly the unpublished-package-as-install-line dishonesty the DC phase claims to have eliminated
  ("no doc presents an unpublished `pip install heartbeat-hb` as an install line"). The claim-honesty
  gate scopes its grep to `docs/`, root `README.md`, and `INSTALL.md` only — `release/` is outside
  scope, so the gate is GREEN while a real doc carries the false install line. T93 whole-docs prose
  has the same scope gap (it covers `docs/**` + root `*.md`, not `release/`). The `crewai.md`
  `heartbeat-hb[crewai]` mention is defensible (shown as the "or" published alternative; primary is
  `./py[crewai]`) — not a violation. `release/README.md` is.

## 4. index-coverage — honest, not vacuous (with the caveat in §1)

- Enumerates from reality: `for f in "$ROOT"/docs/howto/*.md` (FS glob) and
  `grep -oE 'grp "T[0-9]+' run-tests.sh` (the live suite). Not a hardcoded list. ✓
- Self-match avoided: `claim-honesty.sh` itself contains `pip install heartbeat-hb` (in comment +
  grep pattern), but the check restricts to `--include='*.md'`, so the `.sh` is excluded and baseline
  is GREEN. ✓
- Discovery-notes.md is now listed (line 69 of howto-list.md); T117–T125 rows all present in
  dev-tests.md and all correspond to real `grp` groups. ✓
- Caveat: the guide-side match is a loose/unanchored substring+dot-wildcard grep (§1) — it *can* pass
  with a genuinely-unlisted guide. This is the vacuousness risk the question asks about, confirmed
  latent.

## 5. Suites

- `HB_NO_GIT=1 bash tests/run-tests.sh` → **343 passed, 0 failed**; T123, T124, T125 all in
  GROUPS-PASSED. ✓
- `cd py && PYTHONPATH=src python3 -m pytest -q` → **96 passed**. ✓
- `bash tests/parity.sh` → **PARITY OK — node ≡ python**. ✓
- self-audit → `SELF-AUDIT-OK:70/68 (parity:ok)`. ✓
- T93 whole-docs prose is GREEN in the node suite (gates `docs/**/*.md` + root `*.md`; `release/`
  excluded — see §3). ✓

Real tree left clean: probes were isolated to `/tmp`; no `T999`/`zzz.md`/`foo.md`/`barfoo` pollution
in the working tree (verified). The tracked-file diffs present are the genuine DC-phase changes.

---

## Verdict rationale

The three gates have real teeth on their advertised mutations, the CI workflow is valid and honestly
worded, the version note is accurate, the package is installable, and all suites are green. However
the DC claim is stated absolutely — *"the confident prose is now TRUE"* / *"no doc presents an
unpublished `pip install heartbeat-hb` as an install line."* That claim is **false as written**:
`release/README.md` (git-tracked, launch-facing, recently maintained) presents exactly that
unpublished install line as its primary Python install command, and neither claim-honesty (T125) nor
whole-docs prose (T93) covers `release/`, so the gate certifies the claim GREEN while a real doc
contradicts it. This is a genuine docs↔claims drift the phase says it closed. Combined with the two
teeth narrownesses (§1: pytest presence-not-execution; index-coverage unanchored guide match), the
phase does not fully deliver its own claim.

Fix to clear the refutation: correct `release/README.md` line 49 to the real local install
(`pip install -e py`), and extend claim-honesty's grep scope (and ideally T93) to include `release/`
so the drift stays closed.

VERDICT: REFUTED

---

# Re-refutation (post-fix) — 2026-08-22

**Fix under re-review:** release/README.md → `pip install -e py` (not heartbeat-hb); claim-honesty.sh
grep scope widened to include `$ROOT/release` + `$ROOT/SECURITY.md`; ci-workflow.sh now asserts the
RUN commands (`bash tests/run-tests.sh`, `python3 -m pytest|pytest -q`, `bash tests/parity.sh`);
index-coverage.sh switched to `grep -Fq "($b)"` (fixed-string, anchored to the markdown link target).

Actor: adversarial reviewer (distinct from author). Method: repo-wide grep + mutation tests on `/tmp`
copies (real tree untouched — verified clean), then the full suites.

## 1. Original finding — CLOSED

- Repo-wide `grep -rn --include='*.md' "pip install heartbeat-hb"` (excluding planning/reviews) →
  **NONE**. The three remaining `heartbeat-hb` *mentions* in `.md` are all legitimate, non-install-line:
  `docs/dev-python.md` (distribution table cell — the package name), `release/README.md:49`
  (now explicitly "*heartbeat-hb is not published*", command is `pip install -e py`), and
  `use-heartbeat-with-crewai.md:29` (shown as the "or" *published alternative*; primary is `./py[crewai]`).
- **claim-honesty now covers release/**: on a `/tmp` copy, re-adding `pip install heartbeat-hb` to
  `release/README.md` → gate goes **RED** naming the file; removing it → **GREEN** again. The scope
  gap that produced the prior REFUTAL is closed.

## 2. Teeth — improved, not broken

- **ci-workflow.sh** (`/tmp` copy): removing ONLY `run: bash tests/run-tests.sh` (step name kept) →
  **RED** ("does not run tests/run-tests.sh"). Removing ONLY the pytest *run* line while leaving both
  `pip install -e py pytest` AND `- name: Python suite (pytest)` (both containing the word "pytest") →
  **RED** ("does not run pytest"). Removing ONLY `run: bash tests/parity.sh` → **RED**. The prior
  "pytest presence-not-execution" narrowness is fixed: the gate now asserts the run command, not the
  substring. Baseline copy still GREEN.
- **index-coverage.sh** (`/tmp` copy): baseline with all real guides → **GREEN**. Substring-collision
  probe (list only `barfoo.md`, leave `foo.md` unlisted) → **RED** ("unlisted guide: foo.md") — the old
  unanchored `grep -q "$b"` would have false-passed. Regex-wildcard probe (index carries bogus token
  `fooXmd`, `foo.md` unlisted) → **RED** — old `.`-as-wildcard would have false-passed. Correctly
  listing `foo.md` → **GREEN**. `grep -Fq "($b)"` (fixed-string, `(...)` link-target anchored) kills
  both false-pass vectors while still matching all real guides.

## 3. No overclaim / nothing else missed

- Other `pip install heartbeat` hits outside the review artifact are only in `planning/*.dag.json`
  (plan text, not install-facing docs, not `.md`) and `tests/run-tests.sh:1447` (the T125 check's own
  description string). Neither is an install-facing doc.
- Unscoped install-facing `.md`: `py/README.md` is NOT in the gate scope, but uses the real
  `pip install ./py` (no `heartbeat-hb`) — no live dishonesty. All other unscoped `.md` (plugin
  SKILLs, adapter READMEs, corpus fixtures, STATUS.md, CLAUDE snippets) carry no unpublished-package
  install line. `release/launch-post.md` (also in the now-scoped release/) is clean.
- `pip install -e py` is genuinely valid: `py/pyproject.toml` is a real installable package
  (`name = heartbeat-hb`, `version 0.17.0`, stdlib-only core, `hb = heartbeat.cli:main` entrypoint,
  `packages.find where = src`). The prior review already confirmed a fresh-venv editable build + import
  + entrypoint; the package is unchanged.
- CI workflow (`.github/workflows/ci.yml`) still valid + wires three suites: `on: [push, pull_request]`,
  installs `pip install -e py pytest`, then three run steps for run-tests.sh / pytest / parity.sh, all
  present and referencing existing scripts.

## 4. Suites

- `HB_NO_GIT=1 bash tests/run-tests.sh` → **343 passed, 0 failed**; T123, T124, T125 all in
  GROUPS-PASSED; T93 (whole-docs prose) in GROUPS-PASSED. ✓
- `cd py && PYTHONPATH=src python3 -m pytest -q` → **96 passed**. ✓
- `bash tests/parity.sh` → **PARITY OK — node ≡ python**. ✓

Real tree left clean: every mutation was isolated to `/tmp`; `git status` shows only the genuine
DC-phase changes (no `foo`/`zzz`/`T999`/`barfoo` pollution).

## Re-verdict rationale

All three points that grounded the prior REFUTAL are now resolved: (a) the live dishonesty in
`release/README.md` is gone and the honesty gate's scope now includes `release/` (proven RED on
reintroduction); (b) the ci-workflow pytest presence-not-execution narrowness is fixed — surgical
removal of any single run command is now caught; (c) the index-coverage unanchored-match narrowness is
fixed — both substring and regex-wildcard false-pass vectors go RED. No other install-facing surface
carries the unpublished line, the package install is valid, the CI workflow is valid and wired, and all
suites are green. I could not find a surviving docs↔claims drift or a hollow tooth.

VERDICT: COULD NOT REFUTE
