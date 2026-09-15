# Refutation attempt — GATE_RE2

## GATE_RE2

Persona: CORRECTNESS refuter (`node .hb/hb.js refute-prompt GATE_RE2`), phase RE2 "Model
provenance on review events + per-model refuter impact". Everything below was RUN, not read,
from repo root `/home/curtism/Drums/lab/heartbeat` against the uncommitted working tree:
`py/src/heartbeat/review_policy.py`, `py/src/heartbeat/cli.py`, `py/src/heartbeat/executor.py`,
`py/src/heartbeat/mcp_server.py`, `py/src/heartbeat/report.py`, `plugin/templates/hb.js`,
`plugin/templates/hb-exec.js`, `plugin/templates/hb-report.js`,
`docs/howto/gate-examples/refuter-impact.sh`, `tests/parity.sh`, `tests/run-tests.sh`, plus new
`docs/howto/gate-examples/refuter-model-provenance.sh` (T164).

## What held

1. **Proof + selftest green.** `bash docs/howto/gate-examples/refuter-model-provenance.sh` →
   `REFUTER-PROVENANCE-OK`, exit 0. `--selftest` → `SELFTEST-OK`, exit 0. T164 wired in
   `tests/run-tests.sh` (`T164.1`/`T164.2`, grepping for the same markers).

2. **Diff-read confirms the four review-pass guards are structurally untouched.** Read
   `py/src/heartbeat/review_policy.py::accept_review` in full: artifact-required, thin-artifact
   (<40 chars) rejection, citation (real anchor) requirement, and self-review (distinct
   `HB_ACTOR`) rejection are all present, unchanged except for `model` threaded through as a
   plain extra parameter. The proof's guard checks (item 6: pass without `--artifact` on both
   runtimes, plus a doctor Sev-1 rot check after deleting `reviews/G0.md`) all still fire.

3. **Model recording matches node ≡ python** for: `--model` with a real value (fail + pass, both
   runtimes — proof items 1/2), omitted `--model` → `model: null` honestly (never fabricated —
   proof item 2), MCP `pass` with `model` (proof item 4), exec auto-stamp on the "could not
   refute" pass path (proof item 3, both executors via a stub backend, run not grepped).

4. **Extra scenarios I constructed and ran, beyond the shipped proof** (fresh throwaway
   `.hb` fixtures per scenario, mirroring `mkproj` in the shipped proof):
   - `--model ""` (empty string): both runtimes record `"model": ""` verbatim — not coerced to
     null, not defaulted. Matches.
   - `--model` as the trailing token after a multi-word note (tests node's splice-based
     `indexOf`/`splice` ordering): both record the correct model and the correct, un-corrupted
     note. Matches.
   - Exec **FAIL path** (`refuted:true`, untested by the shipped proof — item 3's stub always
     returns `refuted:false`): built a stub returning `{"refuted":true,"findings":"..."}` and
     ran `hb exec run` (python) and `node .hb/hb-exec.js run`. Both correctly auto-stamp
     `"model":"m-auto"` on the resulting `review_failed` event. No divergence — the coverage gap
     in the shipped proof (only exercises the pass/`refuted:false` exec branch) is real but not
     a functional bug: I confirmed the fail branch (`py/src/heartbeat/executor.py:363-368`,
     `plugin/templates/hb-exec.js:381-384`, the exact `git diff` hunks from this phase) works.
   - MCP `review` tool with `verdict:"fail"` + `model` (shipped proof's item 4 only exercises
     `pass`): sent a raw JSON-RPC `tools/call` for `review` with `verdict:"fail"`,
     `model:"m-mcp-fail"` — recorded correctly on `review_failed`. Matches.
   - Mixed-model impact where the **same** model appears on both a `review_failed` and a
     `review_passed` for the same gate: `report.py:refuter_impact` and
     `hb-report.js:refuterImpact` both correctly accumulate `{"same-m": {"caught": 2,
     "cleared": 1}}`. Matches.

5. **Parity case has real teeth, verified two ways.** `tests/parity.sh`'s `impact_case` (now
   seeding a mixed null+`"m1"` fixture) does a full recursive sorted-key structural compare of
   the whole `refuters` object (node's `canon()` helper and python's
   `json.dumps(sort_keys=True)` both recurse into the new `models` sub-object) — not a substring
   grep. Confirmed by injecting a bug into a scratch copy of `report.py`
   (`mk = "(none)"` unconditionally, dropping the real per-model split) and re-running
   `HB_PY_SRC=<mutated> bash tests/parity.sh`: `refuter-impact` failed exactly as expected
   (`node` showed the real `m1`/`(none)` split, `py` showed everything collapsed into
   `(none)`), overall script exit 1.

6. **The refuter-impact.sh key-adjacency fix is real, not cosmetic.** `git diff` shows the old
   `grep -q '"gate":"GATE_C","profile":null'` (which relied on `gate`/`profile` being
   alphabetically adjacent in a `sort_keys` JSON dump) replaced with a structural
   `json.load`+field-check, because `models` now sorts alphabetically between `gate` and
   `profile` (`g` < `m` < `p`) and would have broken the literal-adjacency string match. The new
   check is unconditional on key order (loads JSON and reads `g["profile"]` directly).

## What broke — the hole

**Node's `review` command FABRICATES a model value (and silently corrupts the note) whenever
the refuter's own note/findings text contains the literal token `--model` — on BOTH `pass` and
`fail` verdicts — while Python's `review` correctly refuses the same input with a loud error and
records nothing.** This directly contradicts the phase's own stated invariant (`hb.js`'s new
comment: "`--model`: ... null when omitted: honest, never fabricated"; `review_policy.py`'s
docstring: "null when unknown — honest, never fabricated") and is a genuine node≡python
divergence on the exact new surface RE2 ships.

Root cause: `plugin/templates/hb.js`'s `review` case does positional/`indexOf` parsing —
`const mi = rest.indexOf('--model'); if (mi !== -1) { model = rest[mi + 1] ?? null;
rest.splice(mi, 2); }` — over the SAME `rest` array that also holds the free-text note. It
cannot distinguish "the reviewer's note happens to contain the word `--model`" from "the
reviewer passed the `--model` flag." Whichever token comes right after the FIRST occurrence of
the literal string `--model` anywhere in the argument list is silently promoted to the model
field and removed from the note.

Reproduced on a throwaway fixture (`G0` gated project, `HB_ACTOR=rev`), **fail** verdict:
```
$ node .hb/hb.js review G0 fail the code correctly parses a --model flag in all cases
# rc=0 (no error, no warning)
{"event":"review_failed","gate":"G0","model":"flag",
 "note":"the code correctly parses a in all cases", ...}
```
The reviewer never passed `--model`; node invented `model:"flag"` from the note text and
silently dropped `"--model flag"` out of the note.

Same input on python:
```
$ python3 -m heartbeat.cli review G0 fail the code correctly parses a --model flag in all cases --dir <d>
usage: hb ...
hb: error: unrecognized arguments: in all cases
rc=2   (no event written — refused, not corrupted)
```
Python's argparse also treats the literal `--model` token as the flag (so it isn't immune to
the *misinterpretation* itself), but because the remaining note tokens after the option can't
be reattached to a `nargs="*"` positional once an option has interrupted it, argparse hard-fails
loudly and writes NOTHING — fail-closed. Node has no such backstop: it always succeeds and
always writes an event.

Confirmed the same fabrication on the **pass** path too (not just fail): `node .hb/hb.js review
G0 pass --artifact art.md note: verified the --model flag works as documented` → rc=0,
`{"event":"review_passed","model":"flag","note":"note: verified the works as documented", ...}`
(note silently truncated, model fabricated). Python on the identical input: `unrecognized
arguments: works as documented`, rc=2, nothing written.

Why this matters for RE2 specifically, and isn't a pre-existing/out-of-scope quirk (unlike the
generic "node is lenient about extra args, python's argparse is strict" pattern I checked and
set aside during GATE_RE1's round 2 — verified there via `hb evidence GATE EXTRA_JUNK` behaving
the same way on an untouched command): this bug requires the `--model` splice logic that RE2
itself introduces (`mi = rest.indexOf('--model'); ...; rest.splice(mi, 2)`, new in this phase's
diff to `hb.js`'s `case 'review'`). Before RE2 there was no `--model` handling at all, so a note
containing the word "--model" was harmless free text. RE2's own new code is what turns that text
into a fabricated, silently-recorded provenance field — precisely the "never fabricated"
guarantee the phase claims to uphold. It's also a highly plausible input for THIS repository's
own review notes (a refuter reviewing an RE1/RE2-style gate would very naturally write findings
that mention "the `--model` flag" by name), and it silently corrupts the note (loses the exact
words describing the finding) in addition to fabricating provenance — a double failure mode
(wrong data recorded as if true, AND evidence text quietly destroyed) with no error, no
non-zero exit, nothing in `stderr`.

None of the shipped proof's assertions or `--selftest` construct a note containing the literal
substring `--model`, so this is untested and unguarded by anything currently in the suite.

## Round 2

Coordinator reports the round-1 catch was recorded as a review fail (`--model sonnet` — the
first provenance-stamped event in this log) and fixed at the root in BOTH runtimes: the note is
now a single (quoted) argument — `py/src/heartbeat/cli.py`'s `review` subparser changed
`note` from `nargs="*"` to `nargs="?"`, and `plugin/templates/hb.js`'s `case 'review'` now
counts `noteToks` after splicing `--artifact`/`--model` out, dying loudly on >1 token or a
lone flag-shaped token, before ever computing `note`. Re-verified adversarially, everything run
for real from `/home/curtism/Drums/lab/heartbeat`.

**Diff reviewed.** `git diff HEAD -- plugin/templates/hb.js py/src/heartbeat/cli.py` confirms:
node's new `noteToks = rest.slice(1)`, `if (noteToks.length > 1) die(...)`,
`if (noteToks[0] && /^--\S+$/.test(noteToks[0])) die(...)`, THEN `note = noteToks[0] || ''` —
the refusal happens strictly before any `mutate()` call, so a refusal cannot leave a partial
event. Python's `note` positional is now `nargs="?"` (was `nargs="*"`), so an unquoted
multi-token note is unrecognized-arguments (argparse hard error) rather than silently absorbed.

Also ran a full `bash tests/run-tests.sh` as extra due diligence beyond round 2's explicit ask
(a first attempt stalled/was reaped mid-suite around T146 with no clean completion; a clean
rerun in the background completed cleanly): `RESULT: 421 passed, 0 failed`, all 164 groups
(T1–T164, including the new T164) in `GROUPS-PASSED`, `GROUPS-RAN: 164 GROUPS-SKIPPED: 0`,
`✅ ALL GREEN`.

**1. Proof / selftest / parity / pytest, run fresh:**
- `bash docs/howto/gate-examples/refuter-model-provenance.sh` → `REFUTER-PROVENANCE-OK`, exit 0
  (now includes the new "1c" block: unquoted `--model`-in-note refused with **zero** events
  written on both runtimes, a quoted note mentioning `--model` stays accepted with `model: null`
  and the full text intact).
- `--selftest` → `SELFTEST-OK`, exit 0.
- `bash tests/parity.sh` → `✅ PARITY OK — node ≡ python` (includes `refuter-impact`).
- `cd py && PYTHONPATH=src .venv/bin/python3 -m pytest -q` → `115 passed`.

**2. Original repro re-run on both runtimes, both verdicts — now refuses, zero events:**
```
$ node .hb/hb.js review G0 fail the code correctly parses a --model flag in all cases
review: unrecognized flag-shaped token '--model' in the note position — quote the note ...
rc=1, events_after == events_before (no event written)

$ python3 -m heartbeat.cli review G0 fail the code correctly parses a --model flag in all cases --dir <d>
hb: error: unrecognized arguments: flag in all cases
rc=2, events_after == events_before (no event written)
```
Same result confirmed on the **pass** verdict (`pass --artifact art.md note: verified the
--model flag works as documented`): both refuse, zero events, on both runtimes. The original
fabrication (`model:"flag"`, truncated note) no longer occurs anywhere.

**3. Quoted note mentioning `--model` stays intact (not over-tightened):** `review G0 fail "the
--model handling has a hole somewhere in this code"` on both runtimes → `model: null` (not
fabricated), `note` is the full, un-truncated quoted string. Matches.

**4. Executor fail-and-pass paths still auto-stamp (stub backend, both executors):** built a
`refuted:true` stub (fail path) and a `refuted:false` stub (pass path) and ran `hb exec run`
(python) and `node .hb/hb-exec.js run` for each. All four combinations correctly stamp
`"model":"m-auto"` on the resulting `review_failed`/`review_passed` event — the executor's
single-element findings string + trailing `--model` flag is exactly the "legitimate" shape the
new arity rule is designed to keep parsing.

**5. Hunted for NEW holes in the arity rule** (fresh throwaway fixtures per case):

| case | python | node | fabrication/corruption? |
|---|---|---|---|
| empty note (`fail --model m-x`, no note) | `model:"m-x"`, no note key, rc=0 | same, rc=0 | no — matches |
| note exactly `--` | refuses to record a note (argparse's `--` end-of-options marker consumes the token; note absent), rc=0 | records literal `note:"--"`, rc=0 | no — cosmetic-only divergence, no model/note corruption |
| `--model` flag placed BEFORE the verdict (`review G0 --model m-early fail "..."`) | accepts, correctly recorded, rc=0 | refuses loudly (`verdict` positional resolves to the literal string `--model`, fails the pass/fail check), rc=1, **zero events** | no — node fails CLOSED, doesn't corrupt |
| `--model` with no value at argv end (`fail "..." --model`) | argparse hard error ("expected one argument"), rc=2, zero events | accepts, `model: null` (trailing flag with nothing after it defaults safely, exactly like omitting `--model`), note intact, rc=0 | no — node's default is `null`, never a fabricated value |
| pass verdict: quoted note + `--artifact` + `--model` all combined | recorded identically, rc=0 | recorded identically, rc=0 | no — matches |
| lone unrelated flag-shaped note (`fail --foo`) | refuses, rc=2, zero events | refuses, rc=1, zero events | no — matches, both safe |

Three genuine node/python **behavioral** divergences turned up (`--`-as-note, flag-before-verdict,
dangling valueless `--model`), but none of them reproduce the round-1 failure MODE: in every
case, the runtime that diverges from the other either (a) refuses loudly and writes **nothing**
(flag-before-verdict on node; dangling `--model` on python), or (b) accepts a harmless literal
value with no model implicated (`--` as note text on node). None fabricate a model, none
silently truncate note content, none leave a partial/corrupted event. These are consistent with
the same class of pre-existing, whole-CLI argparse-vs-manual-parsing strictness gaps already
catalogued (and set aside as out-of-scope) during GATE_RE1's round 2 — not a new instance of the
provenance-fabrication defect RE2's fix specifically targets.

**Conclusion:** the round-1 hole (an unquoted note containing the literal token `--model`
fabricating a model value and silently truncating the note, on both `pass` and `fail`, with
exit 0 and a written event) is fixed at the root in both runtimes, verified by re-running the
exact original repro (now refused, zero events, on both verdicts) and by six additional
adversarial scenarios targeting the new arity rule specifically. No new fabrication- or
corruption-class hole was found; the minor divergences documented above are strictness/UX gaps,
not safety violations.

## VERDICT: CLEAR
