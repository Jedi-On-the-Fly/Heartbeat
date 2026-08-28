# GATE_QS — Adversarial refuter attempt (round 5, FINAL)

Phase: **QS ("Quick scaffolder")** — `hb refuters new <name> [--from <starter>] [--lite]`.
Actor: adversarial refuter (did NOT do the work).

## Design under test (changed since round 4)

Both runtimes now run ONE shared hand-parser over a NAME-FIRST grammar (no argparse `--` magic):
- python captures `refuters` sub-args raw via `argparse.REMAINDER` (`py/src/heartbeat/cli.py` L52),
  then hand-parses in the `refuters new` branch (cli.py L196–237).
- node hand-parses identically (`plugin/templates/hb.js` L549–575).

Grammar: `<name>` is the FIRST token and must not start with `-`; then `[--from <v>|--from=<v>] [--lite]`,
last `--from` wins. A flag-before-name, a second positional, a `--` anywhere, an unknown option, or a
dangling `--from` all ERROR. `--dir` must precede the sub-args (everything after `new` is captured raw).

## Method

Real `refuters new` in BOTH runtimes on FRESH copies of a bootstrapped `.hb/` (via
`plugin/bootstrap.sh`, which seeds `hb.js`, `refuter_profiles.js` and the shipped starters
`correctness.json`, `default.json`, `research-source/` folder, `security.json`). One fresh copy per
runtime per case. Python driven `refuters --dir <p>/.hb new …`; node via its own `.hb/hb.js` with
`HB_DIR`. On double-success: `diff -r` the whole `refuters/` tree byte-for-byte (+ `cksum`).
Exit-code numbers (argparse 2 vs die 1) NOT flagged — only flagged when one SUCCEEDS and the other
ERRORS, or when scaffolded bytes differ.

## Results matrix

### 1. Happy paths — all double-SUCCESS, byte-identical, and RESOLVE
| input | py | node | result |
|---|---|---|---|
| `new foo` | ok(0) | ok(0) | MATCH — byte-identical tree; resolves OK |
| `new foo --lite` | ok(0) | ok(0) | MATCH — byte-identical; lite `.md` resolves OK |
| `new foo --from security` | ok(0) | ok(0) | MATCH — byte-identical; resolves OK |
| `new foo --from=security` | ok(0) | ok(0) | MATCH — byte-identical |
| `new foo --from security --lite` | ok(0) | ok(0) | MATCH — byte-identical |
| `new foo --from=security --lite` | ok(0) | ok(0) | MATCH — byte-identical |

Scaffolded folder / lite `.md` / `--from` refuters all `resolve()` to real profiles in BOTH runtimes.

### 2. Must-error-in-both — all double-ERROR (the round-4 `--` holes are FIXED)
| input | py | node | result |
|---|---|---|---|
| `new --lite foo` (flag before name) | err(2) | err(1) | MATCH — both error |
| `new -- foo` | err(2) | err(1) | MATCH — both error |
| `new foo --` | err(2) | err(1) | MATCH — both error |
| `new -- --lite` | err(2) | err(1) | MATCH — both error |
| `new foo bar` (2nd positional) | err(2) | err(1) | MATCH — both error |
| `new` (no name) | err(2) | err(1) | MATCH — both error |
| `new foo --bogus` | err(2) | err(1) | MATCH — both error |
| `new foo --from` (dangling) | err(2) | err(1) | MATCH — both error |
| `new foo -x` | err(2) | err(1) | MATCH — both error |

Round 4's holes (`new -- --lite`, `new foo --`, and the naming-`foo` divergence on `new -- foo`) are
GONE: with the shared name-first parser, any `--` token starts with `-` → rejected as name or as an
option in both. Confirmed clean.

### 3. Edge but must-match
| input | py | node | result |
|---|---|---|---|
| `new foo --from=` (empty value) | ok(0) | ok(0) | MATCH — byte-identical (empty `from` → generic template) |
| `new foo --from a --from b` (last wins b) | err(1) | err(1) | MATCH — last wins `b`; `b` is not a starter → both fail at resolve, identical text |
| `new .hidden` | ok(0) | ok(0) | MATCH — byte-identical; written to `refuters/.hidden/SKILL.md` (no traversal) |
| `new .` | err(1) | err(1) | MATCH — both reject; NO stray file (refuters stays 4 entries, `.hb` stays 16) |
| `new ..` | err(1) | err(1) | MATCH — both reject; NO stray file |

Note on `--from a --from b`: the task anticipated double-SUCCESS, but `b` is not a shipped starter, so
last-wins correctly selects `b` and BOTH runtimes fail identically at `resolve` (`unknown refuter
profile: 'b' …`). Verified last-wins DOES succeed byte-identically when the last value is valid
(`--from a --from security` → double-OK, `diff -r` identical). Parity-correct, not a hole.

Extra `--from`-guard probes (guard is `startsWith('--')`): `--from --lite` → both reject
("--from requires a value"); `--from -x` → both accept `-x` as value then fail identically at resolve.
MATCH in both.

### 4. No-clobber + shipped starters
No-clobber across ALL three formats, both runtimes (double-ERROR, refusing to overwrite):
| pre-existing | new `<name>` | py | node |
|---|---|---|---|
| `security.json` | `security` | err(1) | err(1) |
| `LITE.md` | `LITE` | err(1) | err(1) |
| `FOLDER/SKILL.md` | `FOLDER` | err(1) | err(1) |

`--from` reads each shipped starter with byte-identical py-vs-node output (`cksum`):
| starter | py | node | cksum (identical) |
|---|---|---|---|
| security | ok | ok | 545732666 |
| correctness | ok | ok | 1219929780 |
| research-source | ok | ok | 3657261227 |
| default | ok | ok | 1839381659 |

### 5. Suites, proofs, teeth
- Node suite: **381 passed, 0 failed** (`bash tests/run-tests.sh`).
- Python suite: **96 passed** (`cd py && PYTHONPATH=src pytest -q`).
- Parity: **PARITY OK — node ≡ python** (incl. `scaffold:foo/SKILL.md`, `scaffold:list`).
- Proof `refuter-scaffold.sh` → **REFUTER-SCAFFOLD-OK**; `--selftest` → **SELFTEST-OK**.
- Teeth (load-bearing): in a scratch copy, changed node's `--from=` slice from `.slice(7)` to
  `.slice(6)` → proof went **RED** (`FAIL: node: --from= equals form failed`, exit 1). Restored →
  **REFUTER-SCAFFOLD-OK**, exit 0. Scratch edit fully reverted; tree clean.

## Cosmetic defect (NOT a grammar/parity hole)

`tests/run-tests.sh` L1618 (introduced by the QS work) has an UNESCAPED backtick literal inside a
double-quoted `grp "…"` title: `` `hb refuters new <name> [--from <starter>] [--lite]` ``. Bash runs
command substitution on it → tries to execute `name` → leaks a stderr line
`tests/run-tests.sh: line 1618: name: No such file or directory` and mangles the T151 group title.
The suite still reports 381/0 (the check itself is unaffected). Fix: escape the backticks (or use
single quotes) in that `grp` title. Cosmetic only — does not affect node≡python parity.

## Verdict

Across the WHOLE grammar — happy paths, all must-error cases, edge cases, no-clobber, and every
shipped starter — node and python are in lockstep: both succeed with byte-identical scaffolded bytes,
or both error. The round-4 `--` holes are fixed by the shared name-first parser. Suites/parity green,
proofs green, teeth load-bearing, tree left clean. The one issue found is a cosmetic unescaped-backtick
in the test harness title, which is not a parity or grammar hole.

VERDICT: SOUND
