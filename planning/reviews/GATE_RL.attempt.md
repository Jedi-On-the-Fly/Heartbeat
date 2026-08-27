# GATE_RL refutation attempt — "Shareable refuter library"

Adversarial review of phase **RL** ("Shareable refuter library — shipped under `templates/refuters`,
bootstrap-seeded, discovery"). I did NOT do this work. I tried hard to refute the claims by running
real commands against both runtimes and by mutating the implementation in copies/in-place-with-restore.

Repo root: `/home/hamid/Téléchargements/heartbeat`

## Artifacts examined
- Proof: `docs/howto/gate-examples/refuter-library.sh` (+ `--selftest`)
- Impl: `plugin/bootstrap.sh:70-79` (seeding block), `plugin/templates/refuters/default.json`,
  `hb refuters` in `plugin/templates/hb.js:549-558` and `py/src/heartbeat/cli.py:195-201`
- Resolver twins: `plugin/templates/refuter_profiles.js`, `py/src/heartbeat/refuter_profiles.py`
- Wiring: `tests/run-tests.sh:1576-1582` (T146), `tests/parity.sh:118-130` (refuters:list),
  `docs/dev-tests.md:165`, `planning/parity-notes.md:17,19-27`
- Python scaffold: `py/src/heartbeat/scaffold.py`

## Attacks run and results

### 1. Does the proof go RED if seeding is removed/broken? (load-bearing)
- **Moved `plugin/templates/refuters/default.json` aside** → proof fails:
  `FAIL: shipped refuters were NOT seeded into .hb/refuters/ by bootstrap`. Restored, verified byte-identical.
- **Neutered the seeding `cp` in `bootstrap.sh`** (in-place, replaced `cp "$_rf" "$_dest"` with a no-op)
  → proof fails with the same message. Restored, `diff` clean.
- `p_seeded` checks `[ -f .hb/refuters/default.json ]` FIRST, so it detects the *file* being seeded,
  not merely that `default` resolves (the built-in fallback would otherwise mask a missing file).
  **Teeth confirmed — the proof cannot pass without real seeding.**

### 2. Is no-clobber real, and does fresh bootstrap actually seed?
Ran `plugin/bootstrap.sh` on a temp dir myself:
- Fresh bootstrap creates `.hb/refuters/default.json` (the shipped persona, 277-char skeptic). Seeding is real.
- Edited it to `{"persona":"MYEDIT"}`, re-ran bootstrap → **MYEDIT SURVIVED**. No-clobber holds
  (`[ -e "$_dest" ] || cp` — line 77).

### 3. Is `hb refuters` truly identical node vs python for tricky cases?
Directly diffed node vs python output on one seeded project for each case:
- Multiple profiles + sort (incl. uppercase `Security.json` — byte/ASCII sort, `S`<`a`): **identical**.
- Non-`.json` files present (`README.txt`, `notes.json.bak`): both ignore them: **identical**.
- A real subdirectory `subdir/` (non-`.json` name): both skip it: **identical**.
- A subdirectory *named* `evil.json`: both LIST it (`readdirSync`/`os.listdir` are name-only, non-recursive):
  cosmetic quirk but **identical in both** — parity holds.
- Empty `.hb/refuters/`: both print nothing, exit 0: **identical**.
- Missing `.hb/refuters/` dir entirely: both print nothing, exit 0: **identical**.
- `tests/parity.sh` `refuters:list` case runs green.

### 4. Is the integrity check BEHAVIORAL (not `test -f`)?
`p_integrity` resolves every `*.json` through the RS resolver and requires a non-empty persona:
- **Broken JSON** (`{not valid json`): resolver raises → `persona_py` exits 1 → `p_integrity` returns 1. Caught.
- **Valid JSON, empty persona** (`{"persona":""}`): resolves to `''` → `[ -n "$per" ]` fails. Caught.
- **Valid JSON, no persona key** (`{"questions":[]}`): normalizes to `''` → caught.
This is genuinely behavioral (parse + resolve + assert content), not existence.

### 5. Parity soundness / the one-tier design decision
- The one-tier search path (`refuter_profiles.{js,py}` `search_dirs` = `[hbdir/refuters]` only) is byte-mirrored
  in both runtimes. No runtime "shipped" tier exists, so node/python can't diverge on *where* a name resolves.
  Given identical `.hb/refuters/`, both resolve and list identically (verified in 3, and by T145).
- **Divergence I found and chased (NOT an RL overclaim):** python `hb init` (`scaffold.py`) does **NOT**
  seed `refuters/` — a python-`init`'d project has no `.hb/refuters/` dir and `hb refuters` prints nothing,
  while a node-`bootstrap.sh`'d project lists `default`. HOWEVER:
  - `scaffold.py init` also does NOT seed `executors/` (verified) — it is a deliberately minimal scaffold;
    the full shipped-library seeding is `bootstrap.sh`'s job. This is a **pre-existing, consistent pattern**,
    not introduced by RL, and `docs/dev-python.md:55` lists exactly what `hb init` scaffolds (no refuters/executors).
  - RL's parity claim is scoped to "given the same `.hb/refuters/`, node ≡ python listing" — which holds.
    `parity-notes.md` correctly attributes seeding to `bootstrap.sh`, not to both bootstrappers.
  - The built-in `default` persona still `resolve`s (277 chars) even with no seeded file, so refutation
    never fails-open on a python-init project — it just isn't *listed*.
  - Worth a one-line note in parity-notes that `hb init` is not a seeder (like executors), but this does
    not falsify any RL claim.

### 6. Hermeticity
- The proof `unset HB_DIR DAG_FILE EVENTS_FILE` (line 17); running it with bogus `HB_DIR=/tmp/bogus`
  `DAG_FILE=/tmp/bogus.json` exported still prints `REFUTER-LIBRARY-OK`. No ambient-env dependence.
- Uses `mktemp -d` + `trap rm -rf EXIT` for both selftest and main; **no stray files left in the repo**
  (`git status` shows only the RL work-in-progress edits + my restored files intact).

### 7. Overclaim check (docs vs code)
- `dev-tests.md:165` and `parity-notes.md:17,19-27` accurately describe seed-model, no-clobber shadow,
  behavioral integrity, and one-tier parity. The one-tier rationale (avoid a module-relative shipped tier
  that differs node-plugin-tree vs python-installed-package) is a real, correct justification.
- No overclaim found. (`parity-notes.md:25` "Seeding keeps the shipped set identical for both" is true
  *because both read the same seeded `.hb/refuters/`* — it presumes the project was seeded by bootstrap.sh,
  which is the documented entry point.)

## Minor notes (non-blocking)
- `--selftest`'s integrity tooth proves broken-JSON is load-bearing but does NOT independently assert the
  empty-persona path of `p_integrity` as load-bearing (I verified manually it is caught). Coverage nit, not a defect.
- The existing RL driver project `planning/refuter-profiles/.hb/` predates the seeding block, so it has
  `executors/` but no `refuters/` yet — a re-bootstrap would seed it (no-clobber). Not an RL defect.

## Restores confirmed
`plugin/bootstrap.sh` and `plugin/templates/refuters/default.json` both `diff`-clean against backups.

## Conclusion
Every RL claim survived attack: seeding is real and load-bearing (RED when removed), no-clobber is real
(edit survives re-bootstrap), the shipped set is behaviorally valid+resolvable (catches broken JSON AND
empty personas), `hb refuters` is byte-identical node≡python across sort/non-json/subdir/empty/missing
cases, and the one-tier seed design is genuinely parity-preserving and hermetic. The python-`hb init`
non-seeding is a real but pre-existing, documented, RL-consistent scaffold minimalism — not a falsification
of any RL claim.

VERDICT: SOUND
