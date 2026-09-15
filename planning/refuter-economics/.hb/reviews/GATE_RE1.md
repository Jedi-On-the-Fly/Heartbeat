# Refutation attempt — GATE_RE1 (RE1 "Interactive model routing")

Persona: CORRECTNESS refuter (`node .hb/hb.js refute-prompt GATE_RE1`). Everything below was
RUN, not just read, from repo root `/home/curtism/Drums/lab/heartbeat` (uncommitted working
tree: `docs/dev-plugin.md`, `docs/dev-python.md`, `docs/dev-tests.md`, `planning/parity-notes.md`,
`plugin/skills/heartbeat/SKILL.md`, `plugin/templates/hb.js`, `py/src/heartbeat/cli.py`,
`py/src/heartbeat/protocol.py`, `tests/parity.sh`, `tests/run-tests.sh`, plus new
`docs/howto/gate-examples/refuter-model-routing.sh`).

## What held

1. **Proof + selftest green.** `bash docs/howto/gate-examples/refuter-model-routing.sh` →
   `REFUTER-MODEL-ROUTING-OK`. `--selftest` → `SELFTEST-OK`. Both exit 0 (re1x/re1y criteria
   pass as written — reproduced their exact `cmd`s from `.hb/dag.json`).

2. **Spec-first confirmed by actually reverting.** `git stash push` on the 10 tracked files
   (leaving the new proof script in place, untracked), then ran the proof against **pre-RE1**
   `cli.py`/`hb.js`: `FAIL: python refute-prompt --json failed (does the flag exist?)`, exit 1 —
   genuinely RED without the phase's code. `git stash pop` restored the tree cleanly
   (`git status` verified clean pop, no leftover diff).

3. **One compose, not two implementations.** Read both diffs: python's `refute-prompt` branch
   computes `prompt = rp.compose_prompt(...)` once; the `--json` branch's `"prompt": prompt` and
   the plain-text branch's `sys.stdout.write(prompt + "\n")` use the same local. Node's branch
   computes `out = composePrompt(...)` once; both the JSON `prompt: out` and the plain
   `process.stdout.write(out + '\n')` reuse it. No second compose exists on either side.

4. **Byte-identity of json.prompt vs text compose**, tested across more shapes than the shipped
   proof covers. Built a second fixture (`/tmp/.../scratchpad/re1fixture`) with three extra
   gates: `GATE_NOREVIEW` (no `review` key at all), `GATE_ODDVERDICT` (profile with
   `panel:0`, `refute_if:"bogus"`, `model:""`, `provider:null`), `GATE_NOPROFILEKEY` (a
   `review.prompt` with no `profile` key). For every one of these, in both runtimes,
   `jq .prompt` of the `--json` output was byte-identical to the plain-text compose. Node/python
   `--json` also agreed field-for-field on all three (including the odd `model:""` — preserved
   verbatim, not coerced to null or a fabricated default, in both runtimes; and `panel:0`,
   `refute_if:"bogus"` passed through unvalidated identically in both).

5. **Fail-closed agreement.** Added `GATE_UNKNOWNPROF` (profile name that doesn't exist) and
   `GATE_MALFORMEDPROF` (profile file is invalid JSON). Both runtimes reject with exit 1 and no
   stdout JSON, for both plain and `--json` modes, on both gates — the error surfaces inside
   `compose_prompt`/`composePrompt` before the `--json` branch ever runs, so `--json` can't
   silently downgrade a hard failure into a bogus 0-exit JSON blob.

6. **Parity case has real teeth, not a vacuous wire-up.** `tests/parity.sh`'s new
   `refute-prompt:json` case (uses `GATE_P0` with a real profile, `model:"M1"`) passes on the
   unmodified tree. To confirm it would actually catch drift, copied `py/` to a scratch dir and
   mutated `cli.py` to report `"provider": prof.get("model")` (an injected bug swapping
   provider↔model). Re-ran `HB_PY_SRC=<mutated> bash tests/parity.sh`: the `refute-prompt:json`
   case failed exactly as expected (`node=[...,null,...]` vs `py=[...,"M1",...]`), and the whole
   script exited 1. Not hollow.

7. **GROUPS-PASSED hardening (re1c) is really in the diff and really changes behavior.**
   `git diff -- tests/run-tests.sh` shows the line changed from
   `[ -z "${_GFAIL[$g]:-}" ] && _gp="$_gp $g"` to
   `[ -z "${_GFAIL[$g]:-}" ] && [ -n "${_GCHECKS[$g]:-}" ] && _gp="$_gp $g"`. Hand-simulated the
   accumulation with a synthetic "group registered via `grp` but zero `ok`/`ko` calls" (models a
   dependency-absent skip like the `python3 absent` branches elsewhere in the suite): under the
   OLD formula that group wrongly lands in `GROUPS-PASSED`; under the NEW formula it's correctly
   excluded, while a real passing group and a real failing group are handled the same as before.
   Caveat, not a hole in RE1's own criteria (the gate's own `re1z` desc says run-enforcement of
   this is `re3z`'s job): `tests/run-tests.sh` T52.2 still only re-implements the *old* formula
   inline as a toy, so the suite has no regression test pinned to the *actual* line 1772 with the
   new `_GCHECKS` gate — verified only by my manual reproduction above and by the full suite run
   (below) never exercising a real zero-check group.

8. **Instruction text: both halves are literally present** (confirmed the proof's grep 6
   passes) and the SPAWN half reads as a genuinely followable instruction: "read
   `... refute-prompt <gate> --json` and pass its `.model` to the Agent tool's model parameter
   (inherit the session model only when null)" — verified `.model` really is `null` on a
   profile-less gate and really is the profile's string otherwise (item 4).

9. **The `--model` RECORD half is honestly pre-disclosed as not-yet-wired**, and this is *not* a
   fresh hole: `GATE_RE1`'s own `review.prompt` says the flag "lands in RE2" and calls out
   "round-2 refutation NEW-1: py argparse would refuse it loudly, node would swallow it into the
   note." I confirmed both halves of that claim by reading (not running — the task forbids
   running `hb review`) `py/src/heartbeat/cli.py`'s `review` subparser (`p.add_argument("gate");
   ...; p.add_argument("--artifact"); _add_dir(p)` — no `--model`, so argparse would raise
   "unrecognized arguments") and `plugin/templates/hb.js`'s `case 'review'` (`const note =
   rest.slice(1).join(' ')` after splicing out `--artifact <file>` — a trailing `--model <val>`
   falls straight into `note`, i.e. silently absorbed, not honored). Since this was already
   surfaced by a prior refutation round and is explicitly scoped out of RE1's claim ("skill/
   PROTOCOL instruct the spawner to honor it" is about the SPAWN half — `--json`/`.model`; the
   RECORD half is forward-documentation for RE2), I did not re-flag it as new.

10. Full regression suites, run for real: `bash tests/run-tests.sh` → `419 passed, 0 failed`,
    all 163 groups in `GROUPS-PASSED` (T163 included), `GROUPS-RAN: 163 GROUPS-SKIPPED: 0`. `cd
    py && PYTHONPATH=src .venv/bin/python3 -m pytest -q` → `115 passed`. `bash tests/parity.sh`
    → `✅ PARITY OK — node ≡ python` (includes `refute-prompt:json`, `refute-prompt:composed`).

## What broke — the hole

**Node and python `refute-prompt --json` do NOT agree when `--json` precedes the gate
argument — node silently misparses `--json` as the gate id and returns a bogus, WRONG
plain-text answer with exit 0, never emitting JSON at all.**

Root cause: `plugin/templates/hb.js` line 374 does purely positional parsing —
`const [cmd, arg1, ...rest] = process.argv.slice(2);` — and the `refute-prompt` case (line
~592) always treats `arg1` as the gate id and only checks `rest.includes('--json')` for the
flag. If the flag comes first, it's consumed into `arg1` instead of `rest`, and the real gate id
ends up an unused element of `rest`.

Reproduced on the `re1fixture` project (`GATE_NOPROFILEKEY`, `review.prompt: "no profile key
here"`, no `profile` key):

```
$ node .hb/hb.js refute-prompt --json GATE_NOPROFILEKEY
Refute that --json is truly complete.
EXIT=0

$ node .hb/hb.js refute-prompt GATE_NOPROFILEKEY --json      # documented order
{"prompt":"no profile key here","model":null,"provider":null,"panel":null,"refute_if":null}
EXIT=0

$ python3 -m heartbeat.cli refute-prompt --json GATE_NOPROFILEKEY --dir re1fixture
{"prompt": "no profile key here", "model": null, "provider": null, "panel": null, "refute_if": null}
EXIT=0

$ python3 -m heartbeat.cli refute-prompt GATE_NOPROFILEKEY --json --dir re1fixture
{"prompt": "no profile key here", "model": null, "provider": null, "panel": null, "refute_if": null}
EXIT=0
```

Python's argparse handles either order correctly (it always has). Node, given the flag first,
composes a prompt for a gate literally named `--json` (falls through the "unknown gate" default:
`"Refute that " + gate + " is truly complete."`), exits 0, and never enters the JSON branch —
so a host asking for machine-readable output gets prose instead, indistinguishable from a
genuine (if odd) plain-text answer. No error, no non-zero exit, no signal that anything went
wrong.

Why this matters for RE1 specifically, not as a pre-existing/out-of-scope quirk:
- The falsification checklist I was handed explicitly asks "Do node and python `--json` agree
  ... ?" and to "try to construct a divergence" — this is exactly that, on the exact new surface
  RE1 adds.
- Neither `docs/howto/gate-examples/refuter-model-routing.sh` (assertions 1/2/3/5) nor its
  `--selftest`, nor `tests/parity.sh`'s new `refute-prompt:json` case, ever invoke the flag
  before the gate id — all three always use `refute-prompt <gate> --json`, the one order that
  happens to work on both runtimes. The divergence is real but completely outside every net
  RE1 cast for itself.
- The audience for this exact feature is an LLM/agent host improvising a shell command from the
  skill text ("read `node .hb/hb.js refute-prompt <gate> --json` and pass its `.model`...").
  Flags-before-positional (`refute-prompt --json <gate>`) is at least as natural a phrasing as
  the documented one, and on node it fails **silently and successfully** (exit 0, plausible
  prose) rather than loudly — exactly the "error path swallowed" failure mode the domain
  checklist asks me to hunt for.
- It falsifies the literal PHASE CLAIM ("`refute-prompt --json` emits the profile's
  model/provider in both runtimes ... node ≡ python") for a realistic, reachable input the
  phase's own tests never try.

## Round 2

Coordinator reports the round-1 catch was recorded as a review fail and the fix landed at the
root cause: `plugin/templates/hb.js`'s `refute-prompt` case now parses flag-order-safe
(`rpArgs`/`rpJson`/`rpGate`), the proof gained assertion 1b + a selftest tooth, and
`tests/parity.sh` gained `refute-prompt:json-order`. Re-verified adversarially, everything run
for real from `/home/curtism/Drums/lab/heartbeat`.

**Diff reviewed.** `git diff HEAD -- plugin/templates/hb.js` (case `'refute-prompt'`, now lines
592-626): `rpArgs = [arg1, ...rest].filter(Boolean)`; `rpJson = rpArgs.includes('--json')`;
`rpGate = rpArgs.find(a => a !== '--json')`; `die(...)` if no `rpGate`; `composePrompt`/
`gateProfile` now keyed on `rpGate` instead of `arg1`. `py/src/heartbeat/cli.py` is unchanged
(it was already order-safe via argparse — only node had the bug). New proof assertion "1b"
round-trips `--json GATE_A` (flag first) on both runtimes and requires `model == "m-cheap"`
(i.e., a *real* profile field, not just "some JSON"). New selftest tooth feeds the literal
round-1 bug output (`printf 'Refute that --json is truly complete.\n'`) into the JSON-field
check and requires it to be REJECTED. `tests/parity.sh` gained `refute-prompt:json-order`,
diffing `node ... refute-prompt --json GATE_P0` against the python equivalent.

**1. Original repro re-run against the fixed code:**
```
$ node .hb/hb.js refute-prompt --json GATE_NOPROFILEKEY
{"prompt":"no profile key here","model":null,"provider":null,"panel":null,"refute_if":null}
EXIT=0
$ python3 -m heartbeat.cli refute-prompt --json GATE_NOPROFILEKEY --dir re1fixture
{"prompt": "no profile key here", "model": null, ...}
EXIT=0
```
Identical, correct. The catch is fixed.

**2. Proof / selftest / parity, run fresh:**
- `bash docs/howto/gate-examples/refuter-model-routing.sh` → `REFUTER-MODEL-ROUTING-OK`, exit 0.
- `bash docs/howto/gate-examples/refuter-model-routing.sh --selftest` → `SELFTEST-OK`, exit 0.
- `bash tests/parity.sh` → `✅ PARITY OK — node ≡ python`, includes new
  `✓ refute-prompt:json-order` line, exit 0.

**3. Confirmed the new teeth actually bite (not just wired).** Built a scratch copy of
`hb.js`'s `refute-prompt` case reverted to the exact round-1 shape (plain `arg1` +
`rest.includes('--json')`, no `rpArgs`/`rpGate`) in the scratchpad, then **temporarily swapped
it into `plugin/templates/hb.js`** (backed up the real file first) and re-ran:
  - The proof script → `FAIL: node --json-first: not JSON or model missing — the flag was eaten
    as the gate name` (assertion 1b correctly goes RED on the round-1 bug shape).
  - `tests/parity.sh` → `✗ refute-prompt:json-order` (`node=` empty — python's `json.load`
    choked on node's plain-text output — `JSONDecodeError`), overall script exit 1.
  Restored the real file immediately after each check; `diff` against the pre-swap backup
  confirmed byte-identical restoration, and `git status --short` afterward showed only the
  same working-tree diff that existed before I touched anything (the 10 tracked files + 1
  untracked proof script — no residual drift).

**4. Hunted for a NEW divergence** with more orderings/malformed invocations than round 1:
`--json` alone (no gate), gate given twice, an unknown flag (`--foo`), `--json` given twice, and
a dash-leading "gate" (`-x`) — on the fixed code, against `re1fixture`:

| case | node | python |
|---|---|---|
| `--json` alone | `usage: ...`, exit 1 | argparse error, exit 2 |
| gate given twice | silently uses the FIRST gate, exit 0 | `unrecognized arguments: <2nd gate>`, exit 2 |
| `GATE --foo --json` | silently ignores `--foo`, correct JSON, exit 0 | `unrecognized arguments: --foo`, exit 2 |
| `--json --json` | correct JSON, exit 0 | correct JSON, exit 0 (matches) |
| `-x` as gate | treats it as a literal (unknown) gate id, exit 0 | argparse eats it as an unrecognized flag → "required: gate" error, exit 2 |

The `--json --json` case matches. The other three ("gate twice", unknown flag, dash-leading
gate) are real node/python differences, but I checked whether they're **new** — they are not.
I reproduced the identical pattern (node silently ignores an extra/unknown positional arg and
succeeds; python's argparse hard-errors) on a completely unrelated, untouched-by-RE1 subcommand:
`hb evidence GATE EXTRA_JUNK` → node exits 0 ("no recorded gate pass..."), python exits 2
("unrecognized arguments: EXTRA_JUNK"). This is a pre-existing, whole-CLI characteristic
(bespoke positional parsing in `hb.js` vs. strict `argparse` in `cli.py`) present since before
RE1 and orthogonal to the specific defect (flag-order for `--json`) that RE1/round-2 targets —
not something the round-2 patch introduced or could plausibly be asked to fix. The `-x` case is
the same argparse-leading-dash quirk, and would have applied equally to the plain
`refute-prompt <gate>` positional before RE1 ever added `--json`; gate ids in this codebase are
conventionally `GATE_*`, so a dash-leading id is not a realistic input either. None of these
falsify the PHASE CLAIM for the inputs the phase's own scope covers (a flag/gate pair, in either
order).

**5. Full suites re-run clean:** `bash tests/run-tests.sh` → `419 passed, 0 failed`, all 163
groups in `GROUPS-PASSED`, `GROUPS-SKIPPED: 0`. `cd py && PYTHONPATH=src .venv/bin/python3 -m
pytest -q` → `115 passed`. `bash tests/parity.sh` → `✅ PARITY OK — node ≡ python` (including
both `refute-prompt:json` and `refute-prompt:json-order`).

**Conclusion:** the round-1 hole (node silently misparsing a leading `--json` as the gate id,
returning a wrong plain-text answer with exit 0) is fixed at the root cause, proven by a real
assertion that I confirmed goes RED on the old code and stays GREEN on the new code, backed by
a parity case I confirmed has the same teeth. No new divergence attributable to RE1/round-2 was
found; the other node/python gaps I found (extra positional args, unknown flags, dash-leading
ids) are pre-existing, whole-CLI, out-of-scope behavior unrelated to this phase's claim.

## VERDICT: CLEAR
