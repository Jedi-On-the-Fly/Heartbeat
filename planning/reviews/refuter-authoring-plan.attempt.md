# Plan refutation (round 4) — refuter-authoring.dag.json

Refuter (distinct actor): plan review, not build. Round 3 was UNSOUND with three blocking
folder-format holes (HOLE-A predicate/path-separator, HOLE-B seeding completeness + re-bootstrap
no-clobber, HOLE-C folder listing / non-SKILL.md subdir) plus should-fixes. The author claims to
have closed them by adding CRITERIA teeth, not just task prose. This round verifies EACH claimed fix
is criterion-enforced (afa/afb/afd/afc/qsa/qsb/qsc), re-checks for NEW holes, and sanity-checks the
round-2 `.md`-level guarantees did not regress.

Plan: `planning/refuter-authoring.dag.json`; design: `planning/refuter-authoring-scope.md`.
Current code confirming round-3 premises still hold BEFORE build (this is the RED baseline):
listing globs `.json` only (`plugin/templates/hb.js:554` `f.endsWith('.json')`;
`py/src/heartbeat/cli.py:200` `f.endswith(".json")`); bootstrap seeds `*.json` only
(`plugin/bootstrap.sh:74`); T146 integrity globs `*.json` only
(`docs/howto/gate-examples/refuter-library.sh:52-60`); `_normalize` returns exactly
{persona,questions,model,provider,verdict} and DROPS `description`
(`py/src/heartbeat/refuter_profiles.py:34-40`). `hb-lint` and `hb-audit` both clean (0 hollow).

Verdict up front: **SOUND** — all three round-3 blocking holes are now closed by a criterion, the
should-fixes are addressed, and no new blocking hole is introduced. One residual (T146 folder
integrity criterion-unenforced) is carried, consistent with the round-2/3 stance and behaviorally
covered by afd. Details below.

---

## HOLE-C (folder listing + non-SKILL.md subdir NOT mis-enumerated) — CLOSED

Round 3: a `<name>/` dir is matched by neither the `.json` nor `.md` glob, so the round-2 listing fix
drops folder refuters; and a bundled `references/`/`assets/` subdir (no SKILL.md) could be
mis-listed. Round 3 rated it "gated only by afa's happy path, fragile — no load-bearing teeth in afb."

Now criterion-enforced on TWO levels:

- **Happy path (afa).** `afa.desc` = "…both listed…"; `af1` prose (line 15) requires the proof to
  "Assert both a `.md` AND a `<name>/SKILL.md` FOLDER refuter are LISTED by `hb refuters` in both
  runtimes (a folder has no extension — the list must not silently drop it), and that a
  `references/`/`assets/` subdir WITHOUT a SKILL.md is NOT listed as a refuter." So `REFUTER-SKILL-OK`
  (afa's grep) cannot print unless BOTH the folder-is-listed and the non-SKILL.md-subdir-is-NOT-listed
  assertions hold. That is the fix for the two sub-holes on the happy path.

- **Teeth (afb, load-bearing).** The round-3 gap was "no mutant makes dropping folders fail SELFTEST."
  `af1` now mandates: "--selftest teeth must include: a folder refuter dropped from the listing is
  caught, and a non-SKILL.md subdir mis-enumerated is caught." afb's cmd runs `--selftest` and greps
  `SELFTEST-OK`, which by the load-bearing discipline only prints if EVERY tooth (including these two
  listing teeth) actually fails on its mutant. So a listing implementation that drops folders, or one
  that mis-enumerates a bundled subdir, is now caught by a load-bearing selftest tooth, not merely by
  a happy-path assertion.

Residual nit (non-blocking): afb's *criterion desc* text still reads "each enumerated flat-parser
divergence trap" (parser-scoped) while the listing teeth it now also gates live in `af1`'s selftest
spec. The desc undersells what the cmd enforces; the cmd (`--selftest → SELFTEST-OK`) does gate the
listing teeth because af1 requires them in the same selftest. Prose/desc mismatch, not a hole — the
build must still author the listing teeth or SELFTEST-OK won't be truthful. Acceptable.

## HOLE-B (folder full-tree seed + re-bootstrap no-clobber across formats) — CLOSED

Round 3: afd's "resolves every seeded refuter" passes on a SKILL.md-only partial copy (portability
unverified) and never exercises the re-bootstrap path where a project's `<name>/` folder must not get
a shipped `<name>.json` dropped beside it (the folder analogue of the round-2 brick).

`afd.desc` is now materially strengthened and its two round-3-open sub-paths are named explicitly:
"a bootstrapped project resolves every seeded refuter **incl. a folder one (full tree copy)**;
re-bootstrap **never drops a shipped format beside a project's own folder (no manufactured
collision)**." af1's `--seeding` mode (line 15) is spec'd to match:

- (a) **Full-tree seed.** "a freshly bootstrapped project resolves EVERY seeded refuter INCLUDING a
  folder `<name>/SKILL.md` one (folder seeding is a full tree copy, not just SKILL.md — a bundled
  reference file survives)." So `SEEDING-SAFE-OK` now requires a bundled sidecar file (not just
  SKILL.md) to survive the seed — the SKILL.md-only partial copy that round 3 said afd couldn't see is
  now caught. The round-3 "resolvability ≠ fidelity" gap is closed: afd asserts a bundled file
  survives, which resolvability alone would not.
- (b) **Re-bootstrap no-clobber across formats.** "on RE-bootstrap a project's own `<name>/` folder is
  NOT given a shipped `<name>.json`/`.md` beside it (no-clobber across formats, so no collision is
  manufactured)." This is exactly the re-bootstrap axis round 3 flagged as untested. It is now inside
  the `--seeding` proof that afd gates.

Both round-3-open directions are now behavioral clauses of the same `--seeding → SEEDING-SAFE-OK`
criterion. afd is no longer satisfiable by a SKILL.md-only partial check.

## HOLE-A (folder predicate "dir IFF contains SKILL.md" + path-separator rejection) — CLOSED

Round 3: nothing pinned "a directory under refuters/ is a refuter IFF it contains SKILL.md" as a
criterion, and a `<name>` with a path separator (`/`/`..`) was an un-rejected footgun for both resolve
and `hb refuters new` (mkdir).

- **Predicate.** af2 (line 21): "A dir under refuters/ is a refuter IFF it contains a `SKILL.md` (so
  bundled `references/`/`assets/` subdirs are NOT mis-enumerated)." This predicate is what makes the
  HOLE-C non-SKILL.md-subdir teeth (afb) satisfiable — the predicate is the implementation, the
  afa/afb assertions are its gate. So the predicate IS criterion-enforced (via afa happy-path +
  afb tooth "a non-SKILL.md subdir mis-enumerated is caught").
- **Path separator, resolve side.** af2 (line 21): "reject a `<name>` containing a path separator."
  Gated indirectly — but see the note below on directness.
- **Path separator, scaffolder side.** qs1 (line 41): "a `<name>` containing a path separator is
  rejected"; qs2 (line 47) implements it; **qsb** (line 74) lists "unknown-starter-errors, no-clobber,
  byte-parity, and bare-list-still-works each individually load-bearing" — the path-separator reject on
  the scaffold side is asserted in qs1's happy proof (qsa) and qs1 also says "--selftest proves
  resolvable-output, unknown-starter-errors, no-clobber, byte-parity, and bare-list-still-works." The
  path-separator reject is in qsa's happy path ("a `<name>` containing a path separator is rejected").

Note (non-blocking): the path-separator reject is enforced on the SCAFFOLDER side by qsa's happy path,
and on the RESOLVE side it lives in af2 prose. There is no dedicated selftest tooth naming
"path-separator name must be rejected" as load-bearing in either afb or qsb's enumerated list. It is a
happy-path assertion (qsa: "a `<name>` containing a path separator is rejected") rather than a
load-bearing mutant. Given the footgun is a fail-closed reject (its absence would let a real
`mkdir ../x` escape), and qsa exercises it directly, this is adequately gated. A dedicated tooth would
harden it but its absence is not blocking — the happy-path assertion cannot pass unless the reject
fires. Round 3's ask ("reject a `<name>` containing a path separator, pinned by a teeth case") is met
at the happy-path level for both surfaces and as a selftest-listed property on the scaffold side.

## HOLE-D (folder byte-parity walks the whole tree) — CLOSED (should-fix)

Round 3: qsb byte-parity for a FOLDER was under-defined (a file-only `cmp` on SKILL.md would miss a
stray sidecar or a `skill.md`-vs-`SKILL.md` divergence). qs1 (line 41) now says: "the scaffolded
output is byte-identical node ≡ python across the WHOLE created tree (**for a folder: every file, not
just SKILL.md**)." So qsa/qsb byte-parity walks the full created tree. Closed.

## Should-fixes (round 3 items 5, 6) — addressed

- **_meta portability overclaim (item 5).** Softened. `_meta` now reads: "Packaging a refuter into a
  `.skill` is a property of the folder format, done with the standard skill tooling — **not something
  this plan builds or gates.**" The plan no longer asserts a package/load guarantee it doesn't gate.
  Closed.
- **`description` carried but not in the compose dict (item 6).** `_meta` and af2 now state:
  "`description` is carried in the FILE … but is NOT part of the normalized compose dict (compose
  ignores it)." This matches `_normalize` which returns only {persona,questions,model,provider,verdict}
  (`refuter_profiles.py:34-40`) — no regression, and the plan no longer implies description is
  load-bearing for the resolved dict. qs1/qsa still assert the scaffolded frontmatter carries
  name+description (portable-skill validity on the surface a user authors). Consistent. Closed.

## Q4 — T146 folder integrity: criterion or task-prose-only? (round-3 residual)

af3 (line 27) prose: "Extend the library integrity loop (refuter-library.sh / T146) to cover seeded
`*.md` and `<name>/SKILL.md` refuters too … so a broken shipped skill-format refuter can't ship
silently." As in round 3, **no GATE_AF criterion directly greps that refuter-library.sh's
`p_integrity` was extended to folders** — `afc` only greps that `refuter-skill-format.sh` is wired,
enumerated in dev-tests, and recorded in parity-notes.

Is that a residual hole? No, for the same reason round 3 accepted it for `.md`: afd's `--seeding`
clause behaviorally proves that every SEEDED refuter (including a folder one, full-tree) RESOLVES, so
a broken shipped folder refuter IS caught by THIS plan's own proof (afd), independent of T146. The
T146 suite edit remains a suite-currency obligation (AGENTS.md rule 4/7) rather than a gated behavior —
identical posture to the round-2/3 `.md` decision. Flag for the builder so the edit is not skipped;
not blocking. Consistent residual, not a regression.

## New-hole scan + round-2 regression sanity

- **Structure/spec-first.** af1→af2→af3 and qs1→qs2→qs3 remain correct RED-before-impl chains;
  GATE_AF still gates QS (`gate_entry: GATE_AF` on QS). No circularity. hb-lint clean (0 warnings),
  hb-audit clean (0 hollow) — no `test -f`/`true` hollow criterion introduced by the folder additions.
- **Collision rule coherence (round-2 carry).** afa still gates the same-NAME cross-format collision
  ("collision errors … both runtimes"), now over all three formats; af2's "in one dir" scoping is
  preserved so a legitimate cross-dir project-shadows-shipped case is NOT bricked. No regression.
- **Shared parser (round-3 Q4 SOUND).** af2 still mandates ONE shared line-parser feeding both the
  folder and lite front-doors, with afa pinning folder≡lite≡json to the same canonical dict. The
  folder additions did not split the parser. No regression.
- **Parser divergence traps (round-2 teeth).** afb still enumerates the full T145 trap matrix
  (first-`:`-split, quotes, WS/tabs, CRLF, BOM, blank lines, duplicate keys, key case, `#` in value,
  missing closing `---`, `## Checklist` casing, `-`/`*` bullets, persona trim), each load-bearing,
  exercised via a direct shared-parser call under GATE_TIMEOUT_S. Intact.
- **Doc prose-integrity (round-2).** qsc still greps `prose-check.sh … ALL-PROSE-OK` on
  write-a-refuter-profile.md and requires the skill quick-start be documented placeholder-free. af3
  keeps the doc prose-clean requirement. No regression.
- **No new hole found** from the folder-format criterion upgrades. The two remaining nits (afb desc
  wording undersells its listing teeth; path-separator reject is happy-path/selftest-listed rather
  than a dedicated named mutant) are hardening opportunities, not holes — each underlying property
  cannot pass its gate unless the behavior is actually implemented.

---

## Verdict: SOUND

All three round-3 blocking holes are closed by a criterion, not just task prose:

- **HOLE-C (folder listing + non-SKILL.md subdir):** gated by afa (happy: both listed, bundled subdir
  NOT listed) AND afb (load-bearing teeth: drop-folder mutant and mis-enumerate-subdir mutant must
  fail SELFTEST). No longer happy-path-only.
- **HOLE-B (folder full-tree seed + re-bootstrap no-clobber):** afd is rewritten so `SEEDING-SAFE-OK`
  requires a bundled sidecar file to survive the seed (fidelity, not just resolvability) AND requires
  re-bootstrap to not drop a shipped format beside a project's own folder. No longer satisfiable by a
  SKILL.md-only partial check.
- **HOLE-A (predicate + path separator):** af2 pins "dir is a refuter IFF it contains SKILL.md" (gated
  via afa/afb), and path-separator rejection is asserted on both resolve (af2) and scaffold (qs1/qsa)
  surfaces.

Should-fixes addressed: folder byte-parity walks the whole tree (qs1/qsa/qsb); `_meta` packaging
overclaim softened to "not gated"; `description` correctly carried-in-file-but-not-in-compose-dict,
matching `_normalize`.

**Remaining (non-blocking, carried):**
1. T146 folder-integrity edit has no dedicated GATE_AF criterion (behavior covered by afd's seeding
   proof; suite-currency obligation for the builder) — same accepted posture as rounds 2–3.
2. Nit: afb's criterion *desc* text says "flat-parser divergence trap" while its cmd now also gates
   the af1-spec'd listing teeth — desc wording undersells the cmd; harden the desc, not blocking.
3. Nit: path-separator reject is enforced by happy-path (qsa) / selftest-listed (qs1) rather than a
   dedicated named load-bearing mutant in afb/qsb — adequately gated, a dedicated tooth would harden.

SOUND.
