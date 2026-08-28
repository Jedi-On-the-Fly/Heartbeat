# Refutation attempt — docs/howto/tune-refuter-sensitivity.md

Actor: adversarial refuter (did NOT author the guide). Repo: /home/hamid/Téléchargements/heartbeat.
Target: `docs/howto/tune-refuter-sensitivity.md` ("My refuter always / never finds anything"),
SECURITY running example.

I tried to break every behavioral claim against shipped code, ran each command, resolved each
link, and ran both wired gates. Below is what held and the one place the guide teaches something
inert.

## Honesty boundary — HELD

The guide stays on the right side of the "does not guarantee better verdicts" line:

- Line 10-11: "You cannot *deterministically* prove a refuter reaches the 'right' verdict — that is
  an LLM judgment, measured on demand with a live model."
- Line 87-89 ("The honest limit"): "These levers change the *lens*; they do not guarantee a better
  verdict. Whether a given profile genuinely catches more real bugs than the default is a
  live-model question — run it against known-buggy and known-good phases and compare."

No claim that a profile/panel/model GUARANTEES catching more real bugs. It scopes the deterministic
part (resolves, persona+questions reach the refuter, distinct model routable, evidence-free verdicts
rejected) explicitly. PASS.

## Behavioral claims — each verified against code

1. `node .hb/hb.js refuters` → the four names.
   RAN (fresh `bash plugin/bootstrap.sh /tmp/tr`): output is
   `correctness / default / research-source / security`. Guide's inline comment (line 30) lists
   `# security, correctness, research-source, default`. All four names correct; the comment is an
   illustrative name list, not an ordered transcript, and the guide makes no ordering claim. NOT a
   defect (order differs but nothing claims order).

2. Shipped `security` profile names authz/injection/secret-leakage.
   `plugin/templates/refuters/security.json` persona hunts "auth bypass, missing authorization on a
   new path, injection (SQL/shell/template), secret or token leakage ... unsafe deserialization,
   SSRF, and TOCTOU"; questions name authz-skip, secret/token leakage, unescaped input injection.
   Guide (line 25-26, 63-64) matches. PASS.

3. "profile questions are APPENDED to the base checklist, never substituted."
   `refuter_profiles.js composePrompt`: builds `[persona, reviewQuestions(base), "Domain checks from
   the refuter profile:\n"+extra, prompt]`. Base checklist is always pushed; profile questions are a
   separate appended block. Python twin `compose_prompt` documented identical (parity). PASS.

4. `node .hb/hb.js refute-prompt GATE_P3` shows persona + questions.
   Added `GATE_P3` with `review.profile=security`, RAN. Output = SECURITY persona, then
   "Falsification checklist for GATE_P3", then "Domain checks from the refuter profile:" with the
   three security questions, then "Refute that GATE_P3 is truly complete." Confirms persona present,
   base-then-appended ordering, and that the domain questions are added, not substituted. PASS.

5. `{panel:3, refute_if:"any"}` and `"majority"` are real accepted forms.
   `hb-exec.js`: `rule = verdictCfg.refute_if || 'majority'`, `aggregateVerdict(verdicts, rule)` with
   any/all/majority. `refuter-panel.sh` selftest exercises the full truth table. `refute_if:"any"`
   (line 52) and `refute_if:"majority"` (line 60) both accepted. PASS.

6. Rule 6 evidence floor: "a REFUTED verdict must cite a real hole; a pass must cite a distinct-actor
   artifact; evidence-free verdicts rejected."
   - REFUTED floor: `hb-exec.js:389-391` — refuter pass with `findings.length < 40` escalates
     ("refusing to rubber-stamp"); a REFUTED with empty findings is caught.
   - Pass floor: `hb.js` review pass requires `--artifact`, rejects <40-char body, requires a real
     phase anchor (gate/task/criteria path), and rejects a self-review (reviewer who did the work).
   All three claims true. PASS.

7. `.hb/reviews/<gate>.attempt.md` stores the refuter's attempt.
   `hb-exec.js:394-396`: `path.join(HB_DIR, 'reviews', gate+'.attempt.md')` is written with the
   refuter's findings. Real path. PASS.

## Commands — every backticked `hb <sub>` is real

`refuters` and `refute-prompt` both in `hb.js` usage
(`start|done|fail|heartbeat|ready|review|doctor|diagnose|protocol|rebuild|state|refuters|refute-prompt|import`).
Both RAN successfully. PASS.

## Links — all 12 resolve

writing-behavioral-gates.md, write-a-refuter-profile.md, cross-model-verification.md,
handle-a-successful-refutation.md, refute-high-risk-claims.md,
add-refutation-to-a-sensitive-gate.md, ../dev-tests.md, ../heartbeat.md, and the four
gate-examples/refuter-*.sh — every relative link exists on disk. PASS.

## Test IDs cited — all real

T145 (refuter-profile-resolve.sh), T146 (refuter-library.sh), T147 (refuter-compose.sh),
T148 (refuter-panel.sh), T73 (cross-model), T60 (howto scoping) — all present in
`tests/run-tests.sh` matching their descriptions. PASS.

## Gates — both green

- `bash docs/howto/gate-examples/prose-check.sh docs/howto/tune-refuter-sensitivity.md` →
  `PROSE-OK:tune-refuter-sensitivity.md / ALL-PROSE-OK:1` (exit 0).
- `bash docs/howto/gate-examples/index-coverage.sh` → `INDEX-COVERAGE-OK` (exit 0).

## JSONC copy trap — NOT present (no landmine)

The two fenced ```jsonc blocks are line 34 (`"GATE_P3": { "review": { "profile": "security" }, ... }`)
and line 52 (`"verdict": { "panel": 3, "refute_if": "any" }`). `grep '//'` over the guide returns
nothing — neither block contains a `//` comment, so a user cannot paste a //-commented fragment into
dag.json and break it. (Line 34 uses a `…` ellipsis and is an obvious fragment.) The sibling
write-a-refuter-profile.md's warning about `//` in real JSON is not needed here because this guide
ships no commented JSON. No defect on this axis.

## THE HOLE — the panel lever is placed where the code never reads it

Guide Case A step 2 (lines 47-52):

> **2. Add perspectives (a panel).** If one lens still misses it, run several and refute if *any* of
> them does — the most sensitive setting:
> ```jsonc
> "verdict": { "panel": 3, "refute_if": "any" }
> ```

The guide presents this as a bare fragment with NO statement of where the `"verdict"` key lives. The
only other fragment in the guide (line 34) established the fragment convention as *gate config*:
`"GATE_P3": { "review": { "profile": "security" }, "criteria": [ … ] }`. By parallel structure a
reader naturally reads `"verdict": {...}` as another gate-level key to add alongside `review`/
`criteria` in the gate.

But the code reads panel config ONLY from the resolved refuter profile, not from the gate:

`plugin/templates/hb-exec.js:357`
```js
const verdictCfg = (prof && prof.verdict) || {};
const panelN = parseInt(verdictCfg.panel || 1, 10) || 1;
...
const rule = verdictCfg.refute_if || 'majority';
```

`prof` is the resolved refuter profile (`gateProfile(...)`). A `grep` for any read of a gate-level or
`review`-level `verdict` in hb.js / hb-audit.js / hb-exec.js finds nothing — the ONLY reader is
`prof.verdict`. The sibling `write-a-refuter-profile.md` gets this right: its `verdict` is a field
INSIDE `.hb/refuters/security.json` (its line 54:
`"verdict": { "panel": 3, "refute_if": "majority" }` inside the profile object).

Consequence: a reader who follows this guide's Case A step 2 and adds `"verdict": {...}` to their
GATE (the placement the guide's own fragment convention implies) gets `panelN = 1` — the panel is
silently inert. No error, no warning; the "most sensitive setting" the guide sells does nothing. The
guide's own Case B (line 59) and "Confirm the change took effect" section never tell the reader the
panel is a PROFILE field, so there is no counter-signal that would rescue the misplacement.

Fix: the step must say the `verdict` block is a field of the refuter profile JSON
(`.hb/refuters/<name>.json`), not a gate-config key — mirroring write-a-refuter-profile.md — OR show
it in-context inside the profile file the way the sibling does.

## Tree

Bootstrapped /tmp/tr (removed). Wrote only this attempt file. `git status` shows no
review-caused changes (the howto-list.md index entry and the untracked guide file predate this
review and are part of the guide being added).

VERDICT: UNSOUND — the panel lever (Case A step 2, lines 51-52) shows `"verdict": { "panel": 3,
"refute_if": "any" }` as a bare gate-config fragment, but hb-exec.js reads panel config only from the
resolved refuter profile (`const verdictCfg = (prof && prof.verdict) || {}`), never from the gate. A
reader who follows the guide's own fragment convention places it at the gate and the panel is
silently inert (panelN=1). The guide must state that `verdict` is a field of the refuter profile JSON
(as its sibling write-a-refuter-profile.md does), not a gate key.
