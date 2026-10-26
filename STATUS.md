# STATUS — HeartBeat

**Version:** v1.39.0 (the discovery doctrine — plan to the horizon; criteria drift is loud)
**Regression suite:** `bash tests/run-tests.sh` · **Parity:** `bash tests/parity.sh`

## v1.39.0 — the discovery doctrine: plan to the knowledge horizon; drift in accepted criteria is loud

For discovery work — projects where later phases depend on what earlier phases will LEARN — part
of the plan is unknowable at planning time, and the field failure this wave answers is the gate
whose criteria hard-coded environment premises that died mid-project. The doctrine has two sides
and both now have teeth: plan only to the horizon and replan freely below it; above it, accepted
criteria change only through the rigor that created them.

- **The drift tripwire** (both runtimes): every real gate pass already pins `criteria:
  [{id, cmd, exit}]` on its `gate_passed` event. Doctor now walks each gate's criteria-pinned
  pass history plus the current dag criteria as a final element, comparing ordered `(id, cmd)`
  pairs canonically (strings byte-exact — the schema's domain; out-of-schema values as a type
  class, identically across runtimes; hostile log entries can never crash the walk). Any adjacent
  UNSANCTIONED difference is a PROBLEM (exit 1, twin-identical bytes, naming the cure). The
  LAUNDER — weaken, then plainly re-pass so a fresh pass pins the weakened bytes — still drifts:
  the pin history is truth. Bare/import passes never pin; a removed ever-pinned gate is the same
  problem; reorders drift; `desc`/`timeout_s` edits never do (unpinned — the honest limit).
- **The cure is a completed regate cycle** — declare, a DIFFERENT actor rearms with evidence,
  fresh pass, the whole cycle after the drift (late rigor is still rigor; the last cycle absolves
  all earlier drift on that gate; the unsanctioned window stays in the log). A bare declare,
  declare+rearm without the fresh pass, a cycle on another gate, and an old pre-drift cycle all
  cure nothing. Strengthening is also a revision — the tripwire pins change, not direction.
- **The loudness reaches every surface**: both sweeps (`gate.sh --all` ≡ `hb gate --all`) EXCLUDE
  a drifted gate from re-evaluation (running weakened criteria proves nothing) and count it
  FAILING, annotated — and parked now silences neither drift NOR a pending regate (the old
  parked exit-0 pin is flipped); both ticks wake the NEW human-needed `criteria_drift` reason
  every tick until cured, outranking dispatch; both exec drivers escalate and STOP; all protocol
  surfaces carry the reason (PROTOCOL.md template, hb.js table, protocol.py, hb-exec.js,
  the SKILL.md reason table, the detect-hook and MCP stop-lists).
- **The doctrine shipped**: the plan verb's HORIZON RULE (plan only phases whose spec is known
  now; end at an explicit replan point; fabricated far phases are the planning analogue of a
  hollow gate) + REPLAN-AS-REFUTATION-OUTCOME (an UNSOUND that refutes the plan resolves through
  sanctioned surface — append/edit unstarted phases, detach falsified claims, regate dead
  premises — never a weakened gate). New gated how-to: `docs/howto/plan-to-the-horizon.md`,
  every behavioral claim anchored to a named runnable proof.
- **Hardening chores shipped with the release**: (1) hostile criteria shapes (a non-object entry,
  a non-string cmd) crashed four of the six static readers, differently per runtime — now a LINT
  ERROR with identical bytes (the criteria-shape rule), skipped without crashing by both doctors,
  both artifact scans and both audits (parity case `hostile-criteria:lint`); an EMPTY cmd now
  classifies VACUOUS, never the behavioral criterion that saves a gate from `hollow_gate` (the
  runner evals `''` → exit 0 — a latent audit hole). (2) The T162.5/.6 suite flake: the one
  surviving red run proves .6 was a cascade artifact of .5's skipped unpark; the fixture restore
  moved outside the check, .5 asserts ONE captured sweep, and a failing suite check now prints a
  bounded tail of its output (390 pressure iterations + full suite green; the mechanism, if it
  ever recurs, will self-diagnose).
- Refuter record (5 reviews, 3 catches): sonnet (correctness lens, GATE_DS1) caught the
  degenerate-identity runtime splits twice — `String()`/`str()` coercions, then the 2^53/exponent
  float boundary (final design: type-class identity for out-of-schema values) — plus a py lint
  crash on id-less phases and structural py guard markers; the session model (default lens,
  GATE_DS2) caught a node-form command in the python-console doc, an exec claim riding an anchor
  that never tested it (now pinned in `case_tick`), and a mis-cited case. The plan itself took
  7 refutation rounds (F1–F27) before a line of code was written.
- Proof-driven: `tests/replan.sh` (T184: append/unstarted/quiet/verbs + drift/cure/sweep/tick,
  8 selftest sabotage classes across both runtimes), parity cases `drift:cross` +
  `hostile-criteria:lint`, 16 new pytest cases; six legacy checks re-specified to the new
  contract (behavior-flip regressions instead of hand-edits), never weakened.

**Plugin/marketplace → 1.39.0, Python package → 0.29.0.**

## v1.38.0 — detach: a dependency claim is retractable, never silently droppable

Companion to regate: where regate revises a gate's CONTENT through rigor, detach retracts a
phase's dependency CLAIM — the `gate_entry` edge that learning proved false (the discovery case:
a predecessor the plan no longer needs still locks the one phase that still makes sense). The
mechanism is one field — a null `gate_entry` already means unlocked in both resolvers, zero
resolver/tick/audit-ruleset change — the feature is the loudness around it.

- **`hb detach <PHASE|GATE> <reason…>`** (python: `--reason`): under the write lock, `gate_entry`
  → null with the claim recorded (`detached_from`/`detached_reason`/`detached_by`/`detached_at`,
  `HB_ACTOR` required) + audit-only `phase_detached`; refuses unknown/already-null/already-detached/
  completed phases and ids unusable as anchor file names. **`hb reattach`** restores from
  `detached_from` and refuses when that gate is not BOTH defined AND some phase's `gate_exit`
  (a bare restore would re-create the "phase locked forever" resolver brick).
- **THE DOCTRINE, enforced as loudness**: never detach to escape a blocked or revising predecessor
  gate — that is auto-weaken by topology. The declare WARNS per channel ("the claim is REMOVED,
  not satisfied") exactly when the detached-from gate is in trouble: a live `gate_failed`, a live
  `review_failed` (a later `gate_passed` does NOT clear the refuted steady state), a blocking
  regate marker, an unanswered `gate_regated` in the log, or a stale rearm.
- **Honest change reports**: a stamped detach-time anchor (`anchors/_detach_<PHASE>.json`,
  rewritten per declare) keeps `hb changed`'s base at the detach point instead of widening to
  `_start`; a missing OR stamp-mismatched anchor reads as missing — and doctor says so.
- **Surfaced everywhere**: `hb report` marks `⟂ detached from <gate> (by <actor>: <reason>)`
  (text render only, gone after reattach); doctor NOTES — never problems — the live detach and
  BOTH dag/log divergence directions (fields without a live log detach: a hand edit or fail-open
  restore; an unanswered `phase_detached` without fields: the silent re-lock); lint twins the
  shape rules and reserves the `_start`/`_detach_*` gate-id namespace.
- Refuter catches folded (2 holes across 4 reviews; sonnet on the mechanism gate, the session
  model on the surfacing + docs gate — each lens caught one): the reserved-name lint twins
  diverging on a gate named `"_start\n"` (python regex `$` matches before a trailing newline, JS's
  does not — both checks now regex-free exact-equality, the hostile name pinned in parity), and
  the doctor keying the anchor suffix on existence only (a tampered stamp widened silently — the
  doc's claim made TRUE, not weakened). Plus strip-unclean lock markers caught at round 1: guard
  markers never sit on structural lines; the lock's teeth are the 6-way race.
- Proof-driven: `tests/detach.sh` (T182, 10 guard-strip teeth incl. two python classes),
  `tests/detach-surfacing.sh` (T183, audit byte-identity + the stamp-mismatch doctor fixture);
  6 pytest cases; parity cases `detach:cross` / `detach:lint-malformed` / `detach:lint-reserved`
  with non-vacuity floors. Built as a HeartBeat wave (plan refuted to SOUND in three strong-model
  rounds before any code; constraint-first reviews under the signed-off tiering).
- Plugin/marketplace → **1.38.0**, Python package → **0.28.0**.

## v1.37.0 — regate: a gate changes only through the rigor that created it

Field report: a project's gates hard-coded environment premises (a dev-mode flag, specific data
volumes); the premises died mid-project, the gates failed as gate_blocked, every agent recited
"never weaken the gate" — and the human hand-edited the criteria. The revision happened anyway,
outside the system: no review, no re-audit, no record. The sanctioned path now exists.

- **`hb regate <GATE|PHASE> <reason…>`** (python: `--reason`) declares a revision: snapshots
  `prev_criteria` + the reviser (`HB_ACTOR` required) under the write lock, appends audit-only
  `gate_regated`. Editing the criteria in dag.json is now loud, attributed and gated.
- **Fail-closed perimeter while pending**: `gate.sh` exits a RESERVED **3** (single and `--check`);
  the `--all` sweep counts the gate FAILING whether armed or planned (parked is annotated, never
  hidden); review pass/fail/free, constraints recording and the internal anchor writer refuse at the
  CHOKEPOINTS (`eval_gate`, `accept_review`, `constraints.record` — so the CLI, the MCP tools, the
  executors and even `diagnose` are all covered); executors escalate and stop (never busy-loop,
  never fabricate a verdict); ticks sleep `regate_pending_waiting` (a sleep reason — no new PROTOCOL
  keys). Only a well-formed `pending: false` clears — `[]`/`{}`/`"yes"` block, because the two
  runtimes' truthiness rules disagree on empty containers.
- **`--rearm --artifact <findings>`**: a DIFFERENT actor than the declarer (case-insensitive),
  substantive cited evidence (≥ 40 code points — ONE explicit ASCII trim, `substantiveLen` ≡
  `substantive_len`), and the dag audit-clean re-checked INSIDE the write lock; the bytes land at
  `reviews/<G>.regate.md` with ONE sha256 pinned on the stored file, the `gate_rearmed` event and
  the dag record.
- **Acceptance still owes a fresh pass**: every verdict is refused until a PROVENANCED
  `gate_passed` (criteria/runtime stamped) lands after the rearm — node `import`'s bare synthetic
  pass never unlocks; the review cycle RESTARTS at the rearm (one cycle-start computation per
  runtime), so a pre-declare gate-time constraint set or free review never satisfies the post-rearm
  acceptance; and the event log outranks a hand-edited marker — clearing, deleting or fabricating
  `regate` in dag.json cannot launder an acceptance, and doctor flags each state.
- **Surfaced everywhere**: doctor (pending note; missing/thin/byte-changed rearm evidence;
  stale-accepted gates; log-vs-marker divergence), diagnose (a `regate_pending` branch, inferred and
  explicit, with `gate_blocked`/`review_stuck` routing so no branch prints a command the perimeter
  refuses), `hb report` (`⛔ revised — rearm pending (by <actor>: <reason>)`, gone after a rearm,
  text render only).
- Refuter catches folded (5 holes across 8 reviews; sonnet on the mechanism gates per the declared
  tiering, the session model on the whole-feature gate): a declare lock race; `park`'s unlocked
  dag rewrite erasing a fresh marker (park/unpark now lock); TWO cross-runtime divergences at the
  artifact thin boundary (JS `trim()` vs `str.strip()`, then UTF-16 units vs code points — every
  artifact thin check now shares one explicit trim); the hand-cleared-marker exploit (closed by the
  log-truth guard); the report marker absent from the runtime docs.
- Proof-driven: `tests/regate-fail-closed.sh` (T179, 11 guard-strip teeth), `tests/regate-rearm.sh`
  (T180, 10 teeth incl. the hand-clear exploit and the thin-boundary parity), `tests/regate-surfacing.sh`
  (T181); 23 pytest cases; parity cases `regate:lint-malformed` / `regate:declare-cross` /
  `regate:rearm-cross` with non-vacuity floors. Built as a HeartBeat wave (plan refuted to SOUND in
  four strong-model rounds before any code; every gate constraint-first reviewed).
- Honest limits, in the docs: the rearm bar is procedural evidence inside the self-declared
  `HB_ACTOR` trust model — the human reviews the `prev_criteria` diff; last-rearm-wins on the
  evidence file; a forged event log is outside the model; the node dag writer's number fidelity is
  recorded in parity-notes.
- Plugin/marketplace → **1.37.0**, Python package → **0.27.0**.

## v1.36.1 — constraints are claims, not the specification

A gate-time author may read the implementation and write down what the code does — defect included — as
what it should do; the refuter then held the phase to that. No path rule can catch it, so the review is
told not to trust it.

- **The claims rule** in every constrained refute prompt (both runtimes, byte-identical): a constraint is a
  claim, not the specification — check each against the phase's tasks and the plan-time (P) constraints; a
  gate-time (G) constraint that contradicts the plan, or pins what the code does rather than what the plan
  asks for, is itself a finding (REFUTED). The free and unconstrained prompts are unchanged.
- **Plan-time constraints are the anchor**: the plan instructions and the constraint-first how-to now say
  why — written before the work exists, they cannot copy a defect from the implementation.
- Proof: the constrained-refute proof requires the rule in constrained prompts and its absence elsewhere
  (T170); removing it goes red.
- Plugin/marketplace → **1.36.1**, Python package → **0.26.1**.

## v1.36.0 — constraints name what the phase changed

1.34.0 required each gate-time constraint to name a real path — but any real path passed, so an author
could point the review at a file the phase never touched while the phase's actual change went unchecked.

- **The rule.** `hb constraints <gate> --record` now requires each constraint to name at least one file in
  the phase's `hb changed` list (added, modified or deleted) or a directory holding one. Unchanged files
  and free-text areas may sit alongside. The refusal names the constraint and lists up to five changed
  paths to choose from. `.` never grounds (it would hold every change).
- **Fallback**: with no change list (a project whose entry anchor predates anchors) or an empty one, a
  project-relative path that exists is enough — in-flight projects are not stranded.
- **Everywhere**: CLI, MCP and `hb exec`'s author step, both runtimes; the author prompt states the rule
  (T177; parity case `constraints:subject-path`).
- **What it does not catch**: among several changed files, one that is changed but beside the point; and
  constraints that encode a defect as the specification — both remain the review's job.
- Plugin/marketplace → **1.36.0**, Python package → **0.26.0**.

## v1.35.1 — `mktemp` is not nondeterminism

The audit's `nondeterministic` warning listed `mktemp` (except `mktemp -u`). But `mktemp` randomises a
NAME, not a verdict — and isolating a check in a fresh temp directory is what keeps a gate deterministic;
the fixed `/tmp/x` the warning nudged toward is the one that flakes (stale files, two gates sharing a
path). In practice gate authors moved `mktemp` into helper scripts the audit cannot see, and the noise
diluted the warning's real hits. The exemption also let through `mktemp -u`, the race-prone form.

- `mktemp` is removed from the nondeterministic sources in both runtimes (with the `-u` special case);
  `curl`, `date`, `$RANDOM`, `shuf`, `/dev/urandom`, `$SECONDS`, `$$`, non-local URLs are unchanged. A
  verdict that compares against the random name is left to the refuter's review.
- Proof: `tests/fixtures/audit/tempdir.json` (a gate isolating in `mktemp -d`) trips nothing — the
  no-cry-wolf case of the audit proof and the audit parity set (7 fixtures).
- Docs: write-fast-deterministic-gates says to isolate in `mktemp -d` and assert on the result, never on
  the name; dev-plugin's rule row names what the rule does and does not flag.
- Plugin/marketplace → **1.35.1**, Python package → **0.25.1**.

## v1.35.0 — codex network opt-in

`codex exec -s workspace-write` has no network — not even loopback — so a codex refuter could not
exercise a server the phase starts locally (its `curl` to 127.0.0.1 fails).

- **Opt-in**: `HB_CODEX_NETWORK=1` (exactly `1`) adds `-c sandbox_workspace_write.network_access=true`
  to the codex adapter's execute and refute calls, in both runtimes; any other value, or unset, adds
  nothing. It opens the sandbox's network generally (outbound too), so it is off by default.
- **The author stays read-only**: the constraint author never gets network. The python codex backend
  gains its own read-only `author()` (it used to fall back to the refute call, workspace-write).
- Proof: a stub `codex` logs the argv of every call (T178); the override was checked live on
  codex-cli 0.157.1 (without it `curl` to a local server exits 7, with it the page is read).
- Plugin/marketplace → **1.35.0**, Python package → **0.25.0**.

## v1.34.0 — grounded constraints

A gate-time constraint author could name nothing real — "user management system", endpoints the
project does not have — and the set was recorded; the refuter was then held to constraints about a
system that does not exist.

- **The rule.** `hb constraints <gate> --record` refuses a set in which any constraint has no GROUNDED
  subject: a project-relative path that exists (file or directory) or appears in the phase's
  `hb changed` list (a deleted file counts). A `:12` / `:12-30` line suffix and a `::symbol` / `#anchor`
  suffix are stripped first; an absolute path or one with `..` never grounds. Free-text areas are still
  allowed alongside a real path. The refusal names the constraint and its subjects.
- **Scope**: gate-time (`G`) constraints only — plan-time (`P`) constraints are written before the work
  exists (spec-first) and are not checked.
- **Everywhere**: the CLI, the MCP tools and `hb exec`'s author step (an ungrounded author reply stops the
  run) in both runtimes; the author prompt states the rule (T177; parity case `constraints:subject-path`).
- Plugin/marketplace → **1.34.0**, Python package → **0.24.0**.

## v1.33.0 — HOLES: a pass without answers still states its result

A constraint-first review is backstopped by its per-id answers; an unconstrained review and the free
review had nothing comparable — a reply that argued a hole and still ended in a clean verdict line was
recorded as a pass. Now every review without per-id answers states its result in one checkable line.

- **The rule.** `hb review <gate> pass` on an unconstrained gate, and `hb review <gate> free`, require a
  visible `HOLES: none` line (markdown-, width- and case-insensitive; the same normalised visible text as
  the answers — a line inside an HTML comment does not count), and refuse any HOLES line that lists
  anything: a hole is a finding, recorded with `hb review <gate> fail`. Enforced at the shared layer, so
  the CLI, the MCP `review` tool and `hb exec` all apply it, in both runtimes (T176, parity fixtures).
- **Prompts ask for it**: the unconstrained refute prompt and the `--free` prompt end with a `## Holes`
  block (the constrained, answers prompt does not). The golden fixtures of unconstrained gates were
  re-captured on purpose.
- **Rot-checked**: an unconstrained pass records `holes: "none"` + the artifact's sha256, and `hb doctor`
  re-checks the stored artifact.
- **Panels keep their rule**: under `hb exec`, a panel's pass artifact is its CLEAR panelists' findings;
  an outvoted panelist's findings ride as the pass note, so `refute_if: majority` still means majority.
- **`hb exec` escalates a refused pass** with the validator's reason (node previously crashed out of the
  run on it).
- Plugin/marketplace → **1.33.0**, Python package → **0.23.0**.

## v1.32.1 — refutation fails closed

Running reviews through small local models exposed a fail-open in every refute adapter, and then a run
of verdict-parsing holes behind it.

- **A refuter that could not run passed the gate.** Every adapter (8 python, 3 shell, and the python
  backends) returned `{"refuted": false}` when the framework was missing, the server unreachable or the
  CLI failed — which the driver reads as "could not refute". Now a refutation that did not produce a
  verdict is `{"error"}`, and the driver escalates. Proven end to end: `hb exec` with an unreachable
  refuter no longer accepts a reviewed gate (T174).
- **One exact verdict contract.** A verdict is read only from the reply's last non-empty line, and only
  when that line is the verdict alone (optional markup or a `Verdict:` label); the line before it must not
  be another verdict. Everything else — "unclear", `NOT yet CLEAR`, `CLEAR would be premature`, a copied
  template `REFUTED | CLEAR` or a list of both — is no verdict. The contract is a shared case table
  (`py/tests/verdict_cases.json`) that every parser copy (python package, python adapters, the shell
  adapters' node `verdict_of`) is checked against; every adapter's prompt asks for exactly that line.
  Residual, by design: a last line that is only a verdict is taken at face value.
- **OpenCode**: the verdict comes from the model's text parts, never a tool's output; `--standalone` /
  `--auto` are passed when `opencode run --help` advertises them.
- **Ollama**: the backend requests an explicit context (`HB_OLLAMA_NUM_CTX`, default 16384) and refuses a
  reply whose prompt filled it — Ollama's 4096 default truncated silently.
- **A gate blocked by a failed review says so**: `hb exec` stops with `<gate>: review_failed — <finding>`
  and `hb diagnose` prints `Cause: review_failed` with the findings (T175), both runtimes.
- **Audit**: a JS arrow (`=>`) in an inline `node -e` is no longer read as a file redirect.
- Plugin/marketplace → **1.32.1**, Python package → **0.22.1**.

## v1.32.0 — constraint-first review, gate anchors, loud restore points

- **Gate anchors** (`hb changed <gate>`): HeartBeat records the tree itself (path set + sha256) at the first
  task start and at every gate acceptance; a phase's changes include uncommitted and untracked work.
- **Loud restore points**: a failed commit/tag at acceptance is reported and recorded
  (`restore_point_failed`), a failed commit skips the tag, and `hb doctor` flags missing anchors/tags.
- **Constraint-first review**: plan-time constraints in `review.constraints` (lint/audit), a gate-time
  author (`hb constraints --prompt/--record`, write-once per review cycle, not a doer), a constrained refute
  prompt (every id + answer format + triage rule; `--free` for the breadth review), and enforcement at
  `hb review pass` (every id answered, no VIOLATED, evidence/reasons, the reserved word, a free review from
  another actor when the profile asks). `hb exec` runs the same pipeline unattended; every shipped adapter
  handles `author`, refuses unknown modes and passes the role's model to its CLI.
- How-to: [constraint-first-review.md](docs/howto/constraint-first-review.md). Proofs T166–T173.
- Plugin/marketplace → **1.32.0**, Python package → **0.22.0**.

## v1.31.1 — gate stdin immunity: the slurper that ate the gate

A field report (a downstream project running v1.31.0) caught the sharpest defect yet: `eval_gate`
streams criteria into its `while read` loop **over stdin**, and `run_criterion`'s PRIMARY
(`timeout(1)`) branch ran criteria **without redirecting stdin** — so any criterion that reads
stdin (`docker compose exec -T`, `psql`, `ssh`, anything slurping) consumed the remaining criteria
records. Those criteria were never executed, never reported, never counted: the gate printed
`N passed, 0 failed` and **passed** on partial evidence — silent, fail-open, and
position-dependent (everything after the first slurper was lost; reordering a DAG silently changed
which safety properties were enforced). The bitter detail: the v1.29.2 fallback branch always
carried `</dev/null` *with a comment naming the exact hazard* — the guard lived in the branch that
almost never runs, while the branch that runs wherever coreutils exists was open. The reporter's
real 5-criterion gate ran 3 and passed; their archived 16-criterion gate would have run 1.

- **The fix.** The reporter's one-line local patch, upstreamed verbatim: `</dev/null` on the
  `timeout(1)` branch too — both branches now match.
- **Python mirrored.** `_run_cmd` gains `stdin=DEVNULL`: python never streamed criteria over stdin
  (no record-eating) but inherited the *caller's* stdin — nondeterministic input, or a hang on a
  TTY. One contract on both runtimes: a criterion sees EOF, period.
- **Proof-driven, with the reporter's "option 3" built in stronger.** `gate-stdin-immune.sh`
  (T165) reproduced the bug red-first (2 of 3 evaluated, would pass), pins all-criteria-evaluated
  + block + count honesty on both runtimes — and its `--selftest` strips the guard from a copy and
  **requires the skip to reappear**, so a plugin refresh that loses the redirect turns the suite
  red instead of silently reverting. `gate-parity.sh` gains `G_SLURP` (both runtimes must block —
  pre-fix, node passed while python blocked: a real divergence, now contractual); `test_gate.py`
  pins EOF-not-caller-stdin.
- Node 423 / py 116 / parity OK. Plugin/marketplace → **1.31.1**, Python package → **0.21.1**.

## v1.31.0 — refuter economics: route the refuter, record the model, read the impact

A downstream transcript showed three refutations burning ~540k tokens on the session's strongest
model — because a profile's `model` binding reached only the exec dispatch (T147): an interactive
host had **no machine-readable binding at all** (the composed prompt carries no model line), review
events recorded reviewer/artifact/citations but **not which model reviewed**, and no how-to framed
the economics. Built **the HeartBeat way**: planned as a gated DAG, plan refuted twice before a line
of code (round 1 UNSOUND — 2 blocking + 9 findings, incl. a demonstrated-hollow exit-bar criterion
and a factual error in the plan's own premise — round 2 SOUND), then driven tick-by-tick with every
gate adversarially reviewed. Archive: [planning/refuter-economics/](planning/refuter-economics/).

- **RE1 — the interactive last mile (T163).** `hb refute-prompt <gate> --json` emits
  `{prompt, model, provider, panel, refute_if}` from the gate's resolved profile — `prompt`
  byte-identical to the text compose (one compose, pinned for profiled AND profile-less), all null
  with no profile, flag-order-safe. The skill + both PROTOCOL `review_pending` texts instruct the
  host BOTH halves: spawn the refuter on the profile's model, record the verdict with `--model`.
  Parity cases `refute-prompt:json` / `:json-order`.
- **RE2 — model provenance (T164).** Review events carry `model` on both verdicts — CLI (both
  runtimes), MCP tool argument, and the executors **auto-stamp** the resolved profile model
  (config-derived); null when unknown, never fabricated. Hardened en route: the note must be ONE
  quoted argument — a flag-shaped token inside an unquoted note *fabricated provenance and
  truncated findings on both runtimes* (node loudly caught by review; python's argparse doing the
  same quietly, caught by the fix's own proof). Refuter impact gains a per-model caught/cleared
  breakdown — JSON and both text renders — with nulls bucketed under `(none)`, parity-pinned on a
  mixed fixture.
- **RE3 — the guide.** [tier-the-refuter.md](docs/howto/tier-the-refuter.md): bind the model per
  profile, route by review KIND (plan refutation strong, gate-checklist cheap), verify by observing
  the event, four honest limits (cheaper ≠ differently-failing; watch per-model impact; never
  downgrade to buy a pass; the field's trust boundary — interactive/MCP `--model` is a self-report,
  only the exec stamp is config-derived), deferrals loud (interactive panel fan-out;
  `audit --agent` routing).
- **The dogfood is the data.** The plan's own gates reviewed under the tiering: `correctness`
  bound to a cheap model caught **two real defects** (the flag-order divergence; the provenance
  fabrication), the strong `default` reviewer took the whole-feature gate and caught the guide
  **overclaiming its own evidence** twice (fixed by making the claim true — the text renders gained
  the breakdown — and the history honest). This repo's own impact report now shows it: RE1's cycle
  in `(none)` (predates the flag — the ordering debt visible), RE2 stamped `sonnet`, RE3 stamped
  `fable`. The three phase commits + `GATE_RE1/2/3` tags were written by HeartBeat at review
  acceptance.
- **Suite-level hardenings the exit bar forced.** `run-tests.sh` / `parity.sh` / `parity-fuzz.sh`
  no longer inherit a calling gate's `HB_DIR`/`PROJECT_DIR` (a suite run inside a gate criterion —
  the dogfood pattern — silently pointed dozens of fixtures at the calling project's `.hb`; the
  incident also injected 182 foreign events into the plan's log, recovered forensically — see
  `GATE_RE3.attempt.md`). `GROUPS-PASSED` membership now requires registered checks. `--selftest`
  teeth on both new proofs; node 421 / py 115 / parity OK.
- Plugin/marketplace → **1.31.0**, Python package → **0.21.0** (minor: new CLI surface + review-event field).

## v1.30.0 — park/unpark: a CLI path to retire a phase (minor: new command + DAG field)

There was no CLI path to retire or park a gate — it meant hand-editing `dag.json` under time
pressure, and naive deletion dangles `gate_exit` (phases reference it; `lint` catches exactly
that). A downstream project invented an undocumented placeholder-and-tripwire pattern instead.
Two clarifications ship with the feature: the "mutate state only via the CLI" rule governs
`events.jsonl`/`state.json`, *not* the plan — `dag.json` is meant to be edited; and since v1.29.4
a planned gate no longer blocks pushes, so what parking actually solves is the resolver frontier
(a drafted phase's tasks keep being offered; `all_done` never fires), audit-clean (a refuted gate
keeps failing `hb audit`, and rule 3 blocks the DAG), and armed-gate retirement.

- **The command.** `hb park <PHASE|GATE> [--reason …]` / `hb unpark` (python) and
  `node .hb/hb.js park/unpark` (node). A gate id resolves to the phase carrying it as
  `gate_exit`; unknown ids are refused; `parked: true` (+ `parked_reason`) is set on the phase —
  nothing is deleted, everything is reversible. Schema'd.
- **The semantics.** Resolver: tasks never offered, no `gate_pending`/`review_pending`,
  `all_done` computed without it — while `gate_passed` still counts *all* phases, so parking a
  completed phase never re-blocks downstream `gate_entry` references. Audit: the phase's gate is
  skipped (an unsound-but-parked gate no longer blocks audit-clean), reported
  `⏸ skipped N parked phase(s) … (unpark to re-audit)` — unpark restores the findings, the debt
  returns with the phase. Sweep: `--all` retires even an **armed** parked gate, loudly. Report:
  listed under `parked`, marked ⏸, excluded from the progress denominator — never silently gone.
- **Loud, reversible, rule-preserving.** Every skip is reported; no new audit rule (the skip is a
  summary note, keeping the rule-completeness meta-test contract intact); parking is the safe
  atomic move the placeholder-and-tripwire improvisation was reaching for.
- **Proof-driven.** New how-to [park-a-phase.md](docs/howto/park-a-phase.md) gated by
  `park-phase.sh` (T162.1: park by gate id, audit skip + reversibility, resolver skip, honest
  report, armed retirement, unknown-id refusal) + node twins T162.2–6 + 3 python tests + `parked`
  parity cases (`next`/`ready`/`report`) in `parity.sh` — red before, green after. The first
  suite run caught a missing brace in T162's own fixture (the fixture never wrote; park correctly
  refused the unknown gate; four checks cascaded) — fixed and re-verified in the exact harness.
  Node 417 / py 115 / parity OK.
- Plugin/marketplace → **1.30.0**, Python package → **0.20.0**.

## v1.29.9 — the flake probe: flake ≠ regression, but both still block

A transient failure was reported exactly like a real regression, and blocked the push either way
with no signal (a downstream project saw one of 15 identical invocations fail once and never
reproduce). The originally proposed note — "this criterion passed elsewhere in this run" — became
structurally unavailable with v1.29.8's dedup: the identical cmd now runs *once* and its failure
fans out to every referencing gate. So the discriminator is re-execution.

- **The fix.** In a `--all` sweep, a failing criterion is re-run **once**. Pass on re-run →
  labeled `FLAKY: failed (10s), then passed on re-run (10s) — still FAILED (a criterion must be
  deterministic)`, counted in the verdict (`…, 1 flaky`), and surfaced by both pre-push hooks in
  the block message. Fail again → the affirmative label `(failure reproduced on immediate
  re-run)`. node ≡ python.
- **The verdict never changes — fail-closed, by doctrine.** Observed nondeterminism is itself a
  gate-contract violation: the probe is the *behavioral* complement of the auditor's static
  `nondeterministic` rule, and a retry-then-pass would be the runner silently absolving a flaky
  gate — the exact "auto-weaken" move the driver is forbidden. The probe labels; it never
  absolves.
- **Scoped and evidence-preserving.** Sweep-only (a single-gate `--check` runs the cmd exactly
  once); the probe writes to a second capture file so the *first* failure's output tail — the
  evidence — is preserved; the dedup memo carries the flaky flag so fanned-out reuses are
  labeled too.
- **Proof-driven.** T161.1–4 (flaky labeled + sweep still blocks; reproduced labeled; verdict
  counts; probe is sweep-only) + T160.4 updated (a failing cmd now executes run + probe = 2) +
  mirrored `test_gate.py` cases — red before, green after. Node 411 / py 112 / parity OK.
- Plugin/marketplace → 1.29.9, Python package → 0.19.8.

## v1.29.8 — sweep dedup: the same proof runs once, not once per gate

`--all` re-ran a byte-identical criterion once per gate that referenced it. In a downstream
project, 15 of 44 criteria were the identical `php "$PROJECT_DIR/tests/run.php"` — the sweep ran
the same 10-second suite fifteen times, ~2.5 min of a ~3 min pre-push, to learn one bit.

- **The fix.** Within one `--all` sweep, identical (`cmd`, **effective timeout**) pairs run once
  and reuse the verdict. The key includes the effective timeout deliberately: a pass under a 60s
  budget proves nothing about a 1s one, so the same `cmd` under a different `timeout_s` is *not*
  deduped. node ≡ python.
- **Loud, never silent.** Every reuse prints `(deduped, Ns)` with the original run's duration and
  the verdict counts them (`✅ ALL GATES PASS (read-only: 12 gate(s) in 45s, 14 deduped)`); a
  cached FAILURE still fails every referencing gate — the output tail is shown at the first
  occurrence and later ones point back to it.
- **Scoped to the sweep.** No cross-run cache to rot — the memo lives and dies inside one
  read-only sweep. Soundness leans on the determinism contract the auditor already enforces
  (`nondeterministic` / `side_effecting` criteria are flagged upstream).
- **Portable.** bash-3.2 on node (parallel indexed arrays + linear scan — stock macOS has no
  associative arrays). Single-gate and normal (event-recording) runs are byte-unchanged.
- **Proof-driven.** T160.1–4 (single execution observed via a counter file; loud + counted reuse;
  different-timeout not deduped; cached failure fans out to every gate) + two `test_gate.py`
  cases — red before, green after. Node 407 / py 111 / parity OK.
- Plugin/marketplace → 1.29.8, Python package → 0.19.7.

## v1.29.7 — progress + timing: slow ≠ hung, and the hook is never silent

Two linked gaps. A multi-minute sweep printed nothing per-criterion as it went and never reported
how long anything took — no way to tell "slow" from "hung" from inside the run (the python CLI was
worse: it dumped all lines only after the whole gate finished). And the pre-push hook ran the entire
sweep captured, printing only its final reason — for ~3 minutes a blocked push was indistinguishable
from a dead terminal. Real pushes were killed on that assumption; each was working, and killing them
yielded exit 144 and no explanation. The v1.29.6 default (60s) lengthened the worst-case silence,
making this pair the necessary follow-up.

- **Durations everywhere.** Every result line carries its elapsed time (`✓ [b] onesec (1s)`) — node
  via bash's builtin `SECONDS` (portable to the coreutils-less T156 PATH), python via
  `time.monotonic`. node ≡ python.
- **A TTY sees what's running now.** A transient `⏳ [id] desc (≤60s)` line with the criterion's
  budget, cleared before the result prints — piped/captured output (hooks, tests) never carries it,
  pinned by T159.4.
- **The sweep announces itself.** `--all`'s first line is `— re-verifying N ever-passed gate(s)…`
  and its verdict reports the total (`✅ ALL GATES PASS (read-only: N gate(s) in Ss)`).
- **The hook speaks at both ends.** Preamble *before* the sweep starts; the timed ✅ verdict
  surfaced on success — completion is visible, never silent. The load-bearing proof matches the
  field failure exactly: T117 runs the hook against a **hanging** stub sweep and requires the
  preamble to already be visible mid-run.
- **Python streams.** `eval_gate` gains `emit(line)` (lines as produced) and
  `progress(id, desc, effective_timeout)` callbacks; the CLI wires both, so single-gate runs
  stream and show the transient line on a TTY. Library callers (executor, MCP) are unchanged.
- **Proof-driven.** T159.1–4 + the T117 dead-terminal/verdict additions (node), three cases across
  `test_gate.py` / `test_cli.py` (python) — red before, green after. Node 403 / py 109 / parity OK.
- Plugin/marketplace → 1.29.7, Python package → 0.19.6.

## v1.29.6 — timeouts sized for real criteria (60s default, per-criterion `timeout_s`)

`GATE_TIMEOUT_S` defaulted to **5s** — which kills any real criterion (a ~10s `php tests/run.php`
run fails on every count), and authors had no per-criterion dial. Worse, pre-v1.29.2 the two
failure modes pointed opposite ways *silently*: with `timeout`/`gtimeout` on PATH the 5s kill bit;
without them criteria ran unbounded — so behavior depended on whether coreutils happened to be
installed. (v1.29.2's portable bound closed the unbounded half; a downstream project still on an
older per-project `gate.sh` reported exactly that pre-fix asymmetry — its gates passed *only
because* coreutils was absent, and `brew install coreutils` would have broken every push.)

- **The fix.** Default **60s**, both runtimes — sized for a real test-suite criterion. A criterion
  sets its own budget with `timeout_s` in `dag.json` (schema'd, integer ≥ 1), and it **wins** over
  `GATE_TIMEOUT_S`: the DAG (versioned config) outranks the environment (a blunt global). No
  warning tier needed for a missing timeout binary — since v1.29.2 the shell-level bound gives
  identical semantics either way.
- **Loud floor.** An invalid `timeout_s` fails the criterion at runtime with
  `invalid timeout_s: … (must be a positive integer)` — the zero-criteria-floor precedent; a
  passing `cmd` cannot absolve it, and there is no silent fallback to the default.
- **Transport.** `timeout_s` travels as the 3rd `\x1f` field; `cmd` stays last so it keeps
  swallowing any remainder (the T153 newline-safety contract is untouched).
- **Proof-driven.** T158.1–3 (default survives a real 6s criterion; a criterion's own 1s kills its
  hang even under a generous default; invalid fails loud) + three `test_gate.py` cases +
  `gate-parity.sh` gains G_CRIT_WIN / G_CRIT_BAD (override direction and invalid floor agree
  across runtimes, T83) — red before, green after. All timeout-sensitive tests already pinned
  `GATE_TIMEOUT_S` explicitly, so the default change broke none.
- Plugin/marketplace → 1.29.6, Python package → 0.19.5.

## v1.29.5 — failing criteria surface their output (the WHY, not just the WHICH)

A blocked gate printed the failing criterion's id, desc, and cmd — and not one word of the actual
error: `gate.sh` ran every criterion `>/dev/null 2>&1`, so every diagnosis began by copying the cmd
out and re-running it by hand. The discard had a reason (a chatty test runner × 15 criteria would
bury the gate summary), but the answer is a bounded tail, not silence. The python runner had already
fixed half of this — it surfaced failing output, never mirrored to node — and printed the FULL
output, the very bury-the-summary problem that motivated the discard.

- **The fix.** On failure only, both runtimes print the criterion's `cmd` plus a TAIL of its captured
  stdout+stderr — `GATE_OUT_LINES` (default 20) — with a **loud** truncation marker
  (`… (+N earlier output lines)`), never a silent cut. A passing criterion's output stays quiet.
  node ≡ python (python also gained the `cmd:` line).
- **Capture-to-file, deliberately.** `$(…)` capture would re-introduce an unbounded hang: a timed-out
  criterion's surviving grandchildren hold a command-substitution pipe open past the kill; a file has
  no EOF wait.
- **Portability held by the suite's own gates.** The first draft used `mktemp`/`wc`/`tail`/`sed`;
  T156's coreutils-less curated PATH (the stock-macOS proof from v1.29.2) went red. Final: mktemp
  with a `$$`-file fallback and a pure-bash tail (read-loop, no external tools).
- **Proof-driven.** T157.1–3 (node: stderr surfaced, passing output quiet, tail + marker,
  `GATE_OUT_LINES` tunes) and two `test_gate.py` cases (python, same semantics) — red before, green
  after. Node 396 passed / py 103 / parity OK.
- Plugin/marketplace → 1.29.5, Python package → 0.19.4.

## v1.29.4 — a planned gate is not an armed gate (regression-sweep filter)

`gate.sh --all` / `hb gate --all` re-verified every gate **defined** in `dag.json`. DAGs are authored
with future phases up front, so a gate was armed the moment its phase was drafted — its criteria name
files that don't exist yet — and with the pre-push guard installed, that blocked every push on work
unrelated to the change. Found live in a downstream project: a gate drafted, refuted as unsound, and
parked blocked pushes from that day on, costing ~an hour to diagnose because the hook named no gate.
The fresh seed template itself shipped with the mine armed (T122 relied on it).

- **The gap.** A never-passed gate has nothing to *regress* from — including it in a regression check
  is a category error the system's own words contradicted: the runner header ("--all make a **passed**
  gate keep acting as a gate"), the how-to ("Re-verify **completed** gates"), and the hook ("a gate
  **no longer** verifies").
- **The fix.** `--all` arms only gates with a recorded `gate_passed` event — filtered on the **event
  log** (truth), not the projection, so a once-proven gate stays armed through a recorded
  `gate_failed`. The skip is **loud** (`— skipped N planned gate(s) (never passed): …`), never silent
  — "all gates pass" never overstates coverage. An explicit `gate <G> --check` still probes any gate,
  planned or not. Both pre-push hooks now **name the failing gate(s)** in the block message. Mirrored
  node ≡ python.
- **Proof-driven.** `gate-reverify.sh` gained the planned-gate case (skip + loud + an armed regressed
  gate still caught — the filter never over-skips); T28.5–7 pin the node semantics; T118/T122 moved to
  the honest pass-then-regress scenario. Red before, green after.
- Plugin/marketplace → 1.29.4, Python package → 0.19.3.

## v1.29.3 — rot-guard tokenizer: quote-aware literal stripping + unresolved-var rejection

*(Backfilled note — this release shipped in `b57f7a7`/`944e908` without a STATUS entry.)* Two
false-positive classes survived the tokenizer's filters, found live in a downstream project where they
flagged every completed phase as rot and blocked all commits: a single-quoted grep/sed **literal**
(`'@import "blocks/dock.css" …'`) is text the command searches *for*, yet slash tokens inside it were
rot-checked as repo files; and an **unresolved variable** mid-token (`blocks/$n.css`) passed the
extension check and rot-tripped on a path that never exists statically. Fix, node ≡ python: strip
single-quoted spans before tokenizing — quote-aware, not a blind regex, so
`"require('$PROJECT_DIR/f.js')"` still yields its path — and reject tokens still carrying `$`/`{`/`}`
after `$PROJECT_DIR` stripping. Three `test_lint` cases pin the behaviors. Plugin/marketplace → 1.29.3.

## v1.29.2 — portability fixes from stock-macOS testing (no coreutils, silent-stdin callers)

Two defects a collaborator hit running the suite on stock macOS (bash 3.2, no coreutils), each fixed
spec-first with a portable, self-bounded proof.

- **Bootstrap no longer hangs on a silent-but-open stdin (T155).** Re-bootstrapping a project that
  already has `.hb/` prompted `Overwrite?` guarded for EOF (`read ... || REPLY="n"`) but not for a
  non-terminal caller holding stdin open on a pipe that never delivers a byte and never reaches EOF (a
  test harness / agent / CI / inherited-stdin cron) — `read` blocked forever (state `S`, read as "slow").
  It stalled the suite itself. Fix: prompt only when `[ -t 0 ]`, else refuse; `--force` still overwrites.
  Python `hb init` is flag-driven (no interactive read) → was never affected.
- **gate.sh bounds every criterion even with no `timeout(1)`/`gtimeout` (T156).** The runner applied a
  per-criterion timeout only when a timeout binary was on PATH; stock macOS ships neither, so criteria
  ran UNBOUNDED (a hang froze the tick/suite). Fix: a portable shell-level bound (background + poll +
  kill past `GATE_TIMEOUT_S` → ✗) — parity with the python runner, which was already always-bounded.
- Both proofs carry their own `run_bounded` (never `timeout(1)`). Plugin/marketplace → 1.29.2, Python → 0.19.2.

## v1.29.1 — rot-lint precision: path-shaped non-files no longer false-trip gate_rot

`doctor` rot-detection feeds each gate `criteria[].cmd` through `extractPaths`, which guessed at file
paths from a raw bash one-liner. Absolute tokens (`/dev/null`, `/admin` route args) were already
excluded, but *relative* path-shaped non-files still leaked through and, on a **completed** phase,
false-tripped "no longer reproducible" → a permanent, non-actionable `gate_rot_waiting` tick.

- **The gap.** `require.resolve('playwright/test')` → `playwright/test`, `curl host:3000/health` →
  `3000/health`, `node app.js api/v1/users` → `api/v1/users` — module specifiers, URL paths, and route
  args, none of them files on disk, all flagged as rotted artifacts.
- **The fix.** A token is rot-checked only when its basename looks like a produced FILE: it has a file
  extension, or is a known extensionless artifact (`Dockerfile`/`Makefile`). One mirrored line in
  `hb-lint.js` / `lint.py`; node ≡ python (parity + T126). Accepted tradeoff: a custom *extensionless*
  binary (`bin/hb`) is no longer rot-tracked — real code artifacts carry an extension.
- **Proof-driven.** Extended `rot-lint-precision.sh` (T126) with the three reproducers + a `Makefile`
  keep-case, and `py/tests/test_lint.py` with reject/keep cases — red before, green after.
- Plugin/marketplace → 1.29.1, Python package → 0.19.1.

## v1.29 — the refuter, made first-class (profiles · authoring · impact) + a silent-miscount fix

The adversarial refuter graduates from prompt-craft to a real surface: **named profiles** you select
per-gate, a **scaffolder** to author your own, and a **post-run report** that answers the honest
end-of-run question — *did a refuter actually catch anything, or was it theatre and lost tokens?* Plus
a genuine gate-runner bug (a newline in a `cmd` silently miscounted a blocked gate as passed) fixed at
the transport and backstopped by a loud audit rule. Each item proof-driven and refuted by a distinct actor.

- **Refuter profiles (RS/RL/RC/RP/RH → T145–T148).** A refuter is now a named
  `{persona, questions[], model, provider, verdict}` bundle resolved from `.hb/refuters/`, selected
  per-gate via `review.profile` or `HB_REFUTER`. One `hb refute-prompt <gate>` composes the prompt across
  all three refute surfaces (node exec, python exec, interactive skill) so they can't drift. `hb refuters`
  lists what's installed. Ships `default` / `security` / `correctness` / `research-source`. node ≡ python.
- **Authoring, the skill-creator way (T150/T151).** `hb refuters new <name> [--from <starter>] [--lite]`
  scaffolds a refuter in canonical folder form (`<name>/SKILL.md`) or lite (`<name>.md`), aligned with
  Anthropic's skill-creator format (flat frontmatter + `## Checklist`, one shared no-YAML parser,
  byte-parity node ≡ python). The `refuter-authoring` skill documents the loop; how-to
  `write-a-refuter-profile.md`.
- **"Always / never finds anything" + impact (T149/T152).** How-to `tune-refuter-sensitivity.md` teaches
  verdict placement (a security domain example) for a refuter that's too eager or too meek. `hb report`
  now renders a **Refuter impact** section derived from the event log (`review_failed` = a catch,
  `review_passed` = a clear, lensed by `review.profile`) — caught/cleared counts + finding classes per
  gate. The planned refuter-**bench** was cut by decision: benchmarking a blind-spot catcher against
  planted ground truth measures the wrong thing.
- **Silent gate miscount, fixed at the transport (T153).** `gate.sh` transported a gate's criteria to bash
  `\x1f`-joined + newline-`read` — so an embedded newline (a heredoc `cmd`) split one criterion into bogus
  extra records and a *blocked* gate could report a pass. Now record-terminated (`\x1e`, `read -d $'\x1e'`):
  a multi-line `cmd` runs verbatim and a failing gate reports its real count. Proof `gate-newline-cmd.sh`;
  node/bash ≡ python.
- **Loud > silent — the `control_char` audit rule (T154).** The one residual fragility (a raw `\x1e`/`\x1f`
  byte in a `cmd`/`desc`) is now a **loud audit error** (exit 1), not a silent miscount — defense in depth
  behind the transport fix. Wired into the rule-completeness self-audit; zero false positives across every
  repo DAG; node ≡ python.
- **Version bump + docs currency.** Plugin/marketplace → **1.29.0**, Python package → **0.19.0**
  (independent cadence, by design). Dev docs (dev-plugin/dev-python/dev-tests/parity-notes) swept current
  for the refuter surface, the transport contract, and the audit rule. Gated by `docs-currency.sh`.

## v1.28 — closing the review loop (lock scope, snapshot parity, docs current)

The final residuals from the v1.27 adversarial review, each proof-driven and refuted by a distinct actor.
The two prior fix-waves (critical-fixes RV/RB/DC + critical-fixes-2 KB/SP/PT/HN/DR) fixed every headline
bug and drift item; this release closes what was left and re-affirms the docs as source of truth.

- **Write-lock scope, proven + documented (LK).** `tick.sh` appends informational events
  (`wake`/`lease_expired`/`review_wake`/`log_event`) via a raw `>>` outside the write-lock — safe by
  design (atomic O_APPEND short-line writes + `reproject` is a full re-fold, so `state.json` is eventually
  consistent; the lock guards only the state.json read-modify-write, proven by T139). New proof
  `tick-append-safe.sh` (**T140**): 60 concurrent appends stay valid & complete, real concurrent ticks
  don't corrupt the log, and a `--selftest` non-atomic writer *does* lose updates (teeth). Documented in
  parity-notes "Write-lock scope" + dev-plugin/dev-python.
- **git-snapshot cross-runtime parity (GS).** The snapshot-on-acceptance (`hb.js review` ≡
  `gate._git_snapshot`) is a deliberate pair that can't be code-shared across bash/Python. New proof
  `git-snapshot-parity.sh` (**T141**) drives the real review-acceptance path in both runtimes and asserts
  each produced the commit + force-tag; a missing tag is RED (teeth verified both directions).
- **Version bump + docs currency (VD).** Plugin/marketplace → **1.28.0**, Python package → **0.18.0**
  (independent cadence, by design). Dev docs swept current — `review_policy.accept_review` as the single
  review-acceptance source, the `GROUPS-SKIPPED` coverage-floor marker, moved fixtures under
  `tests/fixtures/`. Gated by `docs-currency.sh` (**T142**): positive current-state assertions (false
  until the sweep) + no stale moved-fixture paths + version consistency, with a `--selftest` for teeth.
- **Skill-prose commands kept by decision.** `/heartbeat …` stays documented skill-prose (no
  `plugin/commands/` directory) — the right shape for a skill-based plugin.

## v1.27 — the research adapter's full loop (source → stamp → ground → refute → write)

The research adapter graduates from a single grounding check to the **whole evidence lifecycle for
facts**: an internet-sourced writeup is accepted only when every claim is backed by a real, stored
source and survives an adversarial refuter — the same bar HeartBeat holds code to. The web **fetch stays
on-demand and non-gated** (it's non-deterministic by design); everything downstream of the stored
snapshot is deterministic and gates.

- **A grounding verifier (the gate).** `ground-check` verifies OFFLINE that every claim's verbatim
  excerpt is present in its stored source and the source still matches its recorded sha (**STALE**
  detection), catching hallucinated citations and fabricated quotes. Advisory; `--strict` blocks. Both
  runtimes (**T110/T111**).
- **Honest hashes — `stamp-evidence`.** Records each source's sha256 from the **stored bytes** into the
  evidence map (a one-time, at-store-time step), so an agent-supplied hash can't lie and a later edit
  surfaces as STALE. node ≡ python same map (**T113**).
- **Grounded context for the writer — `research-context`.** Renders **only** a given section's grounded
  claims (id + text + source url + verbatim excerpt) as the Seam-2 block fed to Stage B — no
  cross-section leak. node ≡ python byte-identical (**T112**).
- **The skill documents the full loop.** `research-grounding` now walks source → stamp → ground →
  refute (a distinct-actor review seeded by `hb-audit --questions`) → write, handing off to
  `docs-authoring` (ordering) and `gated-docs` (prose). Two gated how-tos ship
  (`source-and-ground-research.md`, `run-a-grounded-research-project.md`). Honest throughout: **it
  verifies grounding, not truth** — HeartBeat does not fetch or fact-check for you.

## v1.26 — the evidence lifecycle, made first-class

HeartBeat's differentiator, stated plainly (now the README lead): **a proof-driven development method —
work is accepted only when its claims are backed by executable evidence and survive an adversarial
attempt to refute them.** This release makes the *lifecycle* first-class rather than implicit.

- **A checkpoint only certifies a REVIEWED state.** A review-gated phase's commit+tag `GATE_x` is now
  created only at **review acceptance** (`hb review pass`), not at the deterministic pass — so the tag
  never marks an un-reviewed / later-refuted state, and a refute→fix cycle no longer churns the tag or
  doubles the checkpoint. `git reset --hard GATE_x` always restores a state that passed BOTH the gate
  and the review. Both runtimes (**T103**).
- **Falsification questions, generated from the gate's own claims.** `hb-audit --questions <gate>`
  (node) / `hb audit --questions` (python) derives, from each criterion's class, a targeted "how could
  this FALSELY pass?" question + a general phase question — seeding the adversarial review
  deterministically instead of relying on prompt craft. Node ≡ python (**T104**); referenced from the
  `review_pending` guidance.
- **Evidence provenance on every gate pass.** The `gate_passed` event records per-criterion
  `{id, cmd, exit}`, the git **commit** tested, and the **runtime** — and `hb evidence <gate>` reads it
  back (with the review artifact when present). The evidence is now auditable/reproducible, not implicit
  (**T105**).
- **Graph blind-spots surfaced.** `codegraph-coverage` reports each task's resolved-symbol count and
  lists the **GRAPH-BLIND** tasks (zero symbols — dynamic/framework bindings or not-yet-existing files
  the static graph can't model → read manually), so code context isn't trusted equally (**T106**). Both
  runtimes; in the code-aware-planning skill.

## v1.25 — domain adapters (the method, made domain-aware without leaving the method)

The method stays domain-agnostic; a **domain adapter** plugs in at two seams — plan authoring
(dep-lint a DAG's `requires` against a real dependency graph) and context assembly (feed Stage B
the slice a task needs) — over one small `codemap` contract (`docs/adapters.md`). Two adapters ship,
in **both runtimes**, so the capability is native to the Python/framework path, not just the node plugin.

- **Two shipped adapters, both seams.** **code** (a CodeGraph symbol graph) and **docs/research**
  (a markdown citation graph) each provide Seam 1 (`deplint`) + Seam 2 (a `context_cmd` provider).
  Proofs: `code-deplint.sh` / `code-map.sh` / `code-context.sh` (T87/T88) and `docs-deplint.sh` /
  `docs-map.sh` / `docs-context.sh` (T90/T91). Boundary is enforced: adapters live under
  `plugin/adapters/` (+ `py/src/heartbeat/adapters/`), are **not** scaffolded into any `.hb/`, and
  import nothing from core — the suites stay green without them.
- **Adapters are a PARITY SURFACE — node ≡ python.** Both adapters are ported to Python and
  cross-checked: **byte-equal** for the deterministic outputs (dep-lint findings incl. the em-dash;
  context renderers — Python matches JS `.trim()` exactly via `js_trim`) and **set-equal** for the
  maps (**T94**/**T95**). The capability runs with **zero Node** (**T96**, `adapters-nodefree.sh`
  drives a `python3 -m heartbeat.adapters…` `context_cmd` with node off `PATH`). One deliberate impl
  divergence (node shells to the `sqlite3` CLI, Python uses the stdlib module) — same output — is
  recorded in `planning/parity-notes.md`.
- **Frictionless + enforced.** Each adapter ships a skill (`code-aware-planning`, `docs-authoring`)
  so a user never touches the raw `node plugin/adapters/…` commands; **skill-integrity** (**T92**)
  fails the suite unless every adapter is declared by a skill that names real, **wired** proofs.
  Guide: `docs/howto/build-a-domain-adapter.md`.
- **Code adapter, beyond the two seams** (all node ≡ python): **discovery** — `codegraph-discover`
  gives the transitively-affected set from entry symbols (`dependents` = change impact) to scope a
  change before authoring the DAG (**T98**); **deplint-accept** auto-surfaces dep-lint at plan
  acceptance, resolving the codemap (explicit → `codemap.json` → `.codegraph` db-build → skip),
  advisory / `--strict` (**T100**); **exclude-hb** keeps CodeGraph off HeartBeat's own `.hb/` scaffold
  (**T102**); dep-lint no longer false-flags REDUNDANT for a task with no resolved symbols (**T101**);
  and `resolve_task_symbols` is ported to Python (parity gap closed).
- **MCP adapter tools.** The Python MCP server exposes the now-native adapters as tools — `deplint`,
  `code_context`, and `code_discover` — so a framework/MCP client gets the code-aware capability
  in-session, node-free (**T97**/**T99**, `mcp-adapters.sh` / `code-discover-mcp.sh` drive real
  `mcp-serve` and compare each tool result to the adapter).
- **Live viz dashboard.** `hb-viz.js --serve` runs a loopback-only HTTP server that re-reads
  `dag.json`+`state.json` fresh per request (no regenerate), refusing a non-loopback bind and
  validating `Origin` (DNS-rebinding) — alongside the point-in-time snapshot (**T86**,
  `viz-serve.sh`). Guide: `docs/howto/watch-a-run-live.md`.
- **Docs held to the code's bar.** Whole-`docs/` prose gating (**T93**) extends prose-integrity to
  every guide, and the `T55.2` executor test was de-flaked (deterministic, no timing race). Built the
  gated way throughout: plan/phase refutations caught real defects each phase (a cross-adapter context
  leak, a BOM/NEL `trim` divergence, a nonzero-exit `context_cmd` divergence, stale "node-only" adapter
  docs) before they shipped.

## v1.24 — cross-runtime parity hardening (and the bug it surfaced)

Auditing parity coverage across every feature — prompted by asking "where is the parity
cross-check?" — turned up a real liveness bug and four uncovered surfaces.

- **Python `review_stuck` fix (HIGH).** `tick.py` lacked node `tick.sh`'s `review_stuck`
  escalation, so a never-resolving adversarial review stalled **forever** in the Python runtime
  (a liveness violation) instead of escalating past `STUCK_TICKS`. Now mirrored (count `review_wake`
  since the last verdict; single-alert flag; `review_stalled` event). It hid because the tick's
  *decision* was never cross-checked — only the projector/resolver and the protocol reason *keys*.
- **Four new cross-runtime parity proofs**: the tick's `data.reason` (**T82** — next_task /
  gate_pending / all_done / review_stuck / build_stuck), the gate-runner verdict (**T83** —
  pass/fail/hollow-floor/timeout), doctor/rot detection (**T84**), and the backends registry
  (**T85**, python-only `claude` alias normalized). Each drives both runtimes.
- **Intentional divergences documented** so they're not future false-positives: node-only
  `unsanctioned_drift` (opt-in drift detection, off by default) + `no_next_task_script`, the `claude`
  alias, the scaffold default `.hb`, node-only `import`, and `diagnose` recovery-command text.
- Built + double-checked the gated way: plan/phase refutations caught a vacuous-pass hole, a
  grep-a-filename wiring check, an unbuildable registry assertion (the `claude` alias), and an
  incomplete tick mirror; a pre-commit sweep confirmed 0 consequence-bugs and 0 further missed gaps
  (all other tick reasons verified identical across runtimes).

## v1.23 — scheduled self-audit (corpus coherence + runtime parity)

The drift/overclaim audit we'd been running by hand, made a standing, schedulable capability —
the compounding step from v1.22's gated docs.

- **Deterministic self-audit** (`docs/howto/gate-examples/self-audit.sh`, **T81**) — one command
  checking three project-wide invariants: **prose-integrity** (every guide), **referenced-proof
  integrity** (every `gate-examples/*.sh` a guide names in its body exists AND is wired in the
  suite — the gap `prose-check` misses because those are code-fence paths, not markdown links, and
  exactly how a proof can vanish/go dormant), and **runtime parity** (`node ≡ python` via
  `tests/parity.sh`, failing on divergence). Count-pinned (no vacuous `0/0`); `--selftest` has teeth
  (catches a missing AND an unwired proof). Guide `docs/howto/run-a-scheduled-self-audit.md` with a
  cron/`/loop` schedule recipe that escalates on non-zero.
- **Adversarial tier (on-demand, non-gating)** — the distinct-actor refutation sweep for
  overclaims, documented as a capability probe (needs a model). Fittingly, the phase refutation
  caught an overclaim in the self-audit's *own* guide — an invalid cron the deterministic tier
  structurally can't parse — the exact defect class the adversarial tier exists to find.
- Built the gated way (plan-refuted: a vacuous-pass hole + a grep-a-filename wiring check, both
  tightened; phase-refuted: the cron). The parity cross-check was added after review flagged that a
  "self-audit" omitting node ≡ python isn't auditing the project's core contract.

## v1.22 — gated-docs skill + a fully-gated how-to library + a bug the method caught

Applying HeartBeat's "refute, don't confirm" to the documentation itself — a doc is a claim, so
gate it, wire it to re-verify, refute it, and bend the doc to the code.

- **`gated-docs` skill** (`plugin/skills/gated-docs/`) — the method as a plugin skill: pick
  mechanism-proof vs prose-check, write the proof spec-first (must be able to go red), wire it so
  the suite runs it, refute it; for a batch, orchestrate with `/heartbeat plan`. Enforced by **T78**.
- **Six Tier-1/Tier-2 operational how-tos** — run tasks in parallel (+worktree isolation), add
  HeartBeat to an existing repo, write dependencies that don't over-constrain, review an unsafe gate
  (each a runnable proof, **T77**), plus run fully locally and schedule unattended (prose, **T62**).
- **Whole-library prose gate (T79)** — `prose-check` now runs over *every* `docs/howto/*.md`
  (count-matched), closing the coverage gap where ~half the guides were ungated. Its placeholder
  rule was tightened to marker-based (a false positive on the word "TODO" in prose), with a
  regression-guard selftest.
- **Level-3 refutation sweep** of the existing library — 3 of 5 batches came back clean; it caught
  a **flagship-quickstart bug** (`heartbeat-in-5-minutes.md` didn't run as written — a relative
  `--dir` the proof never exercised) and two `review_stuck` misattributions, all fixed.
- **Relative-`--dir` fix (T80)** — the bug the sweep surfaced: the Python runtime resolved a
  relative `--dir` to a relative `PROJECT_DIR`/`HB_DIR`, so gate criteria and the git worktree
  double-nested (`<proj>/<proj>/…`) and blocked. `gate.py`/`executor.py` now absolutize (matching
  the node runtime, already correct). Behavioral parity in `parity-notes.md`; regression tests in
  `test_gate.py` + `test_exec.py`. Refutation caught two incomplete-fix holes (the `HB_DIR` twin and
  the worktree path) before it landed.

## v1.21 — parity differential-testing oracle + verifiable-reward / model-regression

Two more capabilities that cascade from HeartBeat's own primitives — two implementations of one
spec are each other's oracle, and the event log's gate verdicts are a deterministic label.
Python port + shared test harness; **plugin templates are unchanged** this release.

- **Parity as a differential-testing oracle** — `tests/parity-fuzz.sh` feeds *seeded, generated*
  cases (`tests/gen-parity-case.py`, deterministic xorshift32) through *both* runtimes on every
  shared surface and asserts node ≡ python — so any disagreement on any generated input is a real
  bug, not just the fixtures you thought of. `--selftest` binds the teeth: it must pass clean on the
  real runtime *and* catch an injected divergence on a mutant in one run. It immediately caught a
  **real latent parity bug the fixed fixtures missed** — `report` percent rounding (node
  `Math.round(100*done/total)` vs Python `int(done/total*100)`: `5/8` → 63 vs 62), fixed in
  `report.py` (match node's operand order + round half up). Enforced by **T75**; method in
  `docs/howto/keep-the-runtimes-in-parity.md`.
- **Verifiable-reward + model-regression** — `hb reward` extracts one labeled record per gate
  evaluation from the event log (`{gate, phase, passed, actor, ts}`); `passed` is the deterministic
  log verdict (never a self-report) and `phase` is derived from the dag. `hb bench --baseline <L>`
  adds a per-candidate regression verdict (fewer gates / fewer phases / more failures than the
  baseline). Both are pure functions over the log/scorecards — Python-delivered analytical tooling
  (like `hb bench`; python-only divergence recorded in `parity-notes.md`). Enforced by **T76**;
  guide `docs/howto/benchmark-agents.md`. Honest scope: the extraction/comparison is deterministic;
  a real model's run isn't → a signal, not a leaderboard.
- **Discipline note.** Built through the full plan→refute→build→refute loop; the distinct-actor
  refuters caught five real defects before commit (the latent rounding bug, a float op-order in the
  first fix, an LCG low-bit generator that barely varied, missing review-owed/gate-pending fuzz
  coverage, and a `bench --json` back-compat regression) — the method finding bugs in its own work.

## v1.20 — cross-model refuter + agent benchmark harness

Two capabilities that cascade from HeartBeat's own primitives — refute being a separate backend
method, and the DAG/gates being backend-agnostic and deterministic.

- **Cross-model refuter** — the adversarial `refute` can run on a *different* backend/model than
  the `execute` doer (`HB_REFUTE_BACKEND` / `HB_REFUTE_MODEL` / `HB_REFUTE_PROVIDER` /
  `HB_REFUTE_CMD`, or `executor.json refute_*`; each falls back to the doer's, so it's opt-in and
  backward-compatible). A model doesn't refute its own blind spots. The distinct-actor review
  guarantee is preserved and the refuter's identity is recorded in the review artifact
  (provenance). Both runtimes; `hb exec config` prints the settings. Enforced by **T73**; guide
  `docs/howto/cross-model-verification.md`.
- **Agent benchmark harness** — `hb bench --dir <p> --backend <spec>…` runs the *same* DAG under N
  backends on isolated copies and scores each behaviorally from the event log (gates are the
  rubric; completed phases / attempts / escalations are the metric). The scorer is a pure function
  over the log — never the backend's self-report. Python-delivered analytical tooling. Enforced by
  **T74**; guide `docs/howto/benchmark-agents.md`. Honest scope: the scorer is deterministic
  (suite-proven); real-model runs are non-deterministic → a capability probe, not a leaderboard.

## v1.19 — MCP server (drives, or is driven) + Codex/OpenCode backends

HeartBeat now works in both directions: it drives agents (new `codex`/`opencode` backends), and it
*is* an MCP server that agents drive. Three MCP-client hosts (Codex, Claude Code, OpenCode) on one
server.

- **MCP server (`hb mcp-serve`, Python port)** — a minimal, **stdlib-only** JSON-RPC server (no SDK)
  exposing the read (`tick`/`next`/`state`/`report`/`diagnose`/`doctor`/`lint`/`audit`) and act
  (`gate`/`start`/`done`/`fail`/`review`) tools. Act tools route through the log, so the
  mutate-only-through-the-log invariant holds. Enforced by **T67**.
- **Dual-stacks the 2026-07-28 spec** — the classic `initialize` handshake for today's hosts and
  the 2026 revision (via `server/discover` + per-request `_meta`; `resultType`/cacheable-list) for
  new ones; old responses stay byte-identical. Verified against the official MCP Python SDK v2
  client (`tests/mcp-interop.sh`, `[mcp-test]` extra). Enforced by **T70**.
- **Streamable-HTTP transport** (`--http`) — unauthenticated by design, hardened: loopback-only
  default, refuses a non-loopback bind without `--allow-remote`, exact-IP Origin validation
  (DNS-rebinding). Enforced by **T68**; security note in `docs/howto/secure-the-mcp-server.md`
  (**T71**).
- **Plugin registers the server** (`plugin/.mcp.json`) — installing the HeartBeat plugin wires
  `hb mcp-serve` for Codex *and* Claude Code (one manifest, both hosts). Enforced by **T69**.
- **`codex` backend** — headless `codex exec` (stdin closed; `HB_EXEC_PROVIDER=oss` → keyless
  Ollama). Enforced by **T66**.
- **`opencode` backend** — headless `opencode run --format json` (SST's provider-agnostic agent;
  `HB_EXEC_MODEL=provider/model`) + the opencode.json MCP wiring. Enforced by **T72**.
- Both backends: both runtimes + registry (a new shared surface → parity), stub-on-PATH suite
  proofs + honest on-demand live tiers. Guides under `docs/howto/`.

## v1.18 — agent-framework how-tos + reproducible Docker proof harness

Guides for driving HeartBeat with each of the seven agent frameworks, on a pinned, reproducible
Docker harness — plus one real packaging fix the harness surfaced.

- **Framework proof harness (`tests/frameworks/`)** — one parametrized Dockerfile
  (`ARG FRAMEWORK`/`ARG VERSION`) + a pinned matrix + `run.sh`. `run.sh --check` validates the
  harness **Docker-free** (valid set derived from the backend registry ∩ pyproject extras);
  `run.sh <fw>` builds the pinned image and drives the real adapter against local Ollama.
  RESULTS.md captures live outcomes. Docker is the on-demand LIVE tier — it never gates the suite.
- **Seven framework guides (`docs/howto/use-heartbeat-with-*.md`)** — CrewAI, LangGraph, Agno,
  OpenAI Agents SDK, AutoGen, smolagents, pydantic-ai. Each written for that framework's typical
  user (division of labor: the framework is Stage B / the reasoner, HeartBeat is the harness that
  verifies — not a replacement), with real `HB_EXEC_*` config, the bring-your-own-agent seam, and
  a containerized live proof. Six reached a strict behavioral-gate pass live against Ollama
  qwen2.5:7b; autogen is honestly recorded as wiring-ok (real run; strict miss was model-luck).
- **agno packaging fix** — agno's Ollama path needs the `ollama` client; added to the `[agno]`
  extra (a user hit the same gap).
- Enforced by suite groups **T64–T65** (Docker-free: harness `--check` + conformance + prose).

## v1.17 — runnable how-to library + exec-config parity

A documentation release: a `docs/howto/` library where every guide is CI-enforced, plus one
runtime fix the doc work surfaced.

- **How-to library (`docs/howto/`)** — guides organized by job (roadmap in
  `docs/howto/howto-list.md`). Mechanism guides are each backed by a runnable, self-verifying
  proof under `docs/howto/gate-examples/` (weakness catalogue, refutation, parity self-test,
  recovery, untrusted-Stage-B, liveness, auditor, portability, conformance, diagnose,
  re-verify, restore points, tick economics, CI, event log, embed, quickstart, DAG authoring,
  stop/resume, backends). Launch-prose guides (sizing, runtime/backend choice, when-not) are
  integrity-checked (links resolve, only real commands) + adversarially clarity-reviewed.
  Enforced by suite groups **T53–T62**.
- **`hb exec config` parity fix** — the Python `hb exec` CLI ignored its `action` arg, so
  `hb exec config` ran the executor instead of printing config (the plugin already printed it).
  The handler now honors `config` / `run` / unknown. Behavioral parity locked by **T63**;
  intentional key-format divergence recorded in `planning/parity-notes.md`.
- **Coherence** — `__version__` now single-sourced from package metadata; docs, the test-group
  map, and the architecture diagrams (version stamp removed) brought current.

## v1.16 — gate-quality strengthening

Three fixes so a gate can't pass on unverified work — from an audit of our own gates.

- **Outcome-asserting coverage.** `tests/run-tests.sh` now tracks per-group pass/fail
  (`grp` helper) and prints a machine-checkable `GROUPS-PASSED:` line listing only groups
  with zero failing checks. A coverage gate keyed on `GROUPS-PASSED:.* Tnn ` asserts the
  group actually PASSED, closing the old `run-tests.sh | grep Tnn` hole (a bare-header grep
  passes on a red suite because the header prints before the run fails and the pipe hides
  the exit code). +T52.
- **Behavioral over source-grep.** Rewrote our `planning/*.dag.json` gates: source-string
  greps (`grep 'def X' file`) → import + assert callable/shape or exercise the entrypoint
  and check protocol output; every coverage gate → the outcome marker. All lint- and
  audit-clean.
- **Clean exemplar.** The default template (`plugin/templates/dag.json`) now audits with
  0 warnings (the `GATE_P1` gate_offphase is resolved — a P1 task produces the artifact the
  gate checks). `/heartbeat plan` guidance documents both rules.

## v1.15 — AutoGen + smolagents + pydantic-ai backends

- Three more Stage-B backends in both runtimes (in-process `backends/` + subprocess
  `executors/`): **`autogen`** (AutoGen AssistantAgent, FILE-block writer),
  **`smolagents`** (ToolCallingAgent + `save_file` tool), **`pydantic-ai`** (Agent +
  `save_file` tool). Same two-method contract, graceful degrade, keyless via Ollama.
- Hardened path handling: `_fileblocks.norm_rel` (strip `$PROJECT_DIR`, map absolute →
  relative-under-cwd/basename) now backs both the FILE-block writer and every `save_file`
  tool, so a model that emits an absolute or prefixed path can't nest files.
- All three proven to drive their framework end-to-end against local Ollama (agent writes
  a file, a behavioral gate runs it). Backends now: claude-code · agno · crewai ·
  langgraph · openai-agents · autogen · smolagents · pydantic-ai · ollama · script.
- Not a parity surface — parity unaffected. +T49/T50/T51 (node), +3 python degrade tests,
  pyproject extras `[autogen]` / `[smolagents]` / `[pydantic-ai]`.

## v1.14 — LangGraph + OpenAI Agents SDK backends

- Two more Stage-B backends in both runtimes (in-process `backends/` + subprocess
  `executors/`): **`langgraph`** (LangGraph ReAct agent + `save_file` tool) and
  **`openai-agents`** (OpenAI Agents SDK Agent + function tool). Same two-method contract,
  graceful degrade when the lib is absent, FILE-block fallback.
- Keyless-testable via Ollama (`HB_EXEC_PROVIDER=ollama`; the OpenAI SDK uses Ollama's
  OpenAI-compatible `/v1`). Both **proven live end-to-end** (model writes code, a
  behavioral gate runs it). Backends: claude-code · agno · crewai · langgraph ·
  openai-agents · ollama · script.
- Backends aren't a parity surface — parity unaffected. +T47/T48 (node degrade/validity),
  +test_backends_frameworks.py (python), pyproject extras `[langgraph]` / `[openai-agents]`.

## v1.13 — review-evidence hardening (both runtimes)

Closes the "grade your own homework" hole: a review **pass** is now reducible to evidence
the deterministic layer can re-inspect.

- **Artifact-backed pass.** `hb review <gate> pass` requires `--artifact <file>` — the
  refuter's written attempt. It must be substantive, **cite a real phase anchor** (gate id
  / task id / a path the gate's criteria reference), and be recorded by a **different actor**
  than the doer (`HB_ACTOR`) — self-reviews are rejected. The artifact is stored under
  `.hb/reviews/` and re-checked by `doctor` (a vanished/thin artifact is Sev-1 rot).
- **Runtime hollow-gate floor.** A zero-criteria gate now fails at `gate.sh`/`gate.run_gate`,
  not just in audit — an un-audited or post-audit-mutated DAG can't buy a free advance.
- **Auditor reach.** New **side_effecting** rule (a gate that writes/creates files can
  fabricate its own pass) + broader nondeterminism (`RANDOM`, `shuf`, `/dev/urandom`,
  `SECONDS`, `$$`, `mktemp`).
- **Driver enforcement.** `hb-exec` persists the refuter's findings, passes `--artifact`
  (escalates on an empty pass), and stamps **distinct worker/refuter actors** so the
  self-review guard is enforced in the automated path.
- **Symmetric + parity-locked.** Mirrored in the Python port; `tests/parity.sh` gains a
  `side-effect` fixture that exercises the new audit rules, so a node/python divergence now
  fails T43 (no false-green).

## v1.11 — audited plan step + full-coverage parity

- **`/heartbeat plan` now audits and refutes before proposing.** Its acceptance step runs
  `hb-lint` (structure) **and `hb-audit` (gate quality)**, then refutes the DAG (skeptic
  agent, or `hb audit --agent` in the port) — so no plan is proposed until it's lint-clean,
  audit-clean, AND a skeptic comes back SOUND.
- **Full-coverage parity.** `tests/parity.sh` now checks node ≡ python across every shared
  surface: lint, audit, **protocol (reason keys)**, **resolve (`hb next`)**, **ready**,
  **report** (progress), **diagnose** (inferred blocker), and the state projection. It
  encodes the one intentional divergence — protocol *action text* is runtime-specific (node
  cites `.hb/hb.js`/`gate.sh`, python cites the `hb` console) — by comparing reason keys.
- Added `hb next` (resolve) to the Python CLI; `--json` to `hb lint`.

## v1.10 — agent DAG review + node↔python parity

- **`hb audit --agent` (Python).** The deterministic auditor catches structural
  weakness; the agent layer catches semantics — a gate that asserts the *wrong*
  behaviour, a phase whose gate doesn't exercise the task's real requirement. It
  dispatches a refutation of the DAG to a configured backend and exits non-zero if the
  reviewer refutes the plan. The node/Claude side has a concrete refuter prompt in the
  skill.
- **Exemplary default template.** The scaffold's gates are now behavioral (the DAG
  lints clean; output reports success) instead of `test -f` — `hb audit` on the template
  is clean, and it still bootstraps green.
- **Parity test (`tests/parity.sh`, ratcheted as T43).** The node plugin and the Python
  port are checked to AGREE on lint (errors), audit (findings), and the state projection
  for shared fixtures. node ≡ python.

## v1.9 — adversarial DAG review (gate quality)

- **`hb-audit.js` + `/heartbeat audit`.** Where `lint` checks structure, `audit` checks
  **gate quality** — the thing that actually bounds HeartBeat's value. It applies
  refute-don't-confirm to the *plan* before you run it, flagging **hollow_gate** (a phase
  whose gate has no behavioral criterion), **ungated**, **unguarded_phase**,
  existence-only / vacuous criteria, **nondeterministic** gates, and **gate_offphase**.
  Exit 1 on any hollow gate. The agent-refutation layer (a skeptical second read of the
  whole DAG) sits on top, documented in the skill.
- **Ported to both runtimes** — `hb-audit.js` (node) and `heartbeat.audit` (`hb audit`,
  Python) share one ruleset and are checked for **parity** on shared fixtures
  (`tests/fixtures/audit/`, see `planning/parity-notes.md`).

## v1.8 — pluggable Stage B

- **`hb-exec.js` executor driver + `/heartbeat exec`.** Stage B is now pluggable. The
  driver runs the same serial loop as `/heartbeat run` but dispatches each task to a
  **backend agent** (`claude-code`, `agno`, `crewai`, or a raw `script`) over a tiny
  JSON wire protocol — so an unattended process can do the work. HeartBeat stays the
  deterministic brain: the tick decides what/when, the gates verify, and the driver
  mediates **every** state transition (the backend never touches `state.json`/`gate.sh`).
- **Wire protocol.** `driver → backend`: `argv[last]=execute|refute`, stdin = payload
  JSON. `backend → driver`: `execute → {ok,summary}`, `refute → {refuted,findings}`.
  A backend is ~two methods; shipped adapters live in `.hb/executors/`.
- **Driver owns the hard parts** (framework-blind): the lease **heartbeat pump** during
  a task, **context assembly** from settled reality (dag + state + git log + gate
  criteria), **escalate-only** on a blocked gate (never auto-fixes), a per-task
  **attempt cap** (`HB_EXEC_ATTEMPT_CAP`, default 3), and **strict mode**
  (`HB_EXEC_STRICT=1`) that refuses non-behavioral gates / lint-warning DAGs.
- **Parallel fan-out** (`HB_MAX_CONCURRENCY > 1` / `run --parallel N`): the runnable
  set (`hb ready N`) runs concurrently, **each task in its own git worktree** so writes
  can't collide; the **merge-back is serialized** and a failed task's worktree is
  discarded. Falls back to concurrent in-place without git.
- **Backends**: `claude-code` (default), `agno`, `crewai`, `ollama` (local models,
  stdlib-only), or a raw `script`. Each degrades to protocol-valid JSON when its
  runtime is absent. `tests/real-backend.sh` drives a live end-to-end run against a
  local model (verified with `qwen2.5:7b-instruct`: the model writes code, a
  behavioral gate compiles and runs it).

## v1.7 — never left guessing

- **Self-describing ticks.** Every wake embeds the exact next action in
  `data.action`, so any driver (cron, headless, another harness) knows what to do
  from the JSON alone.
- **One-source protocol.** A single `reason → action` map in `hb.js` drives
  `data.action`, `hb protocol`, and `.hb/PROTOCOL.md` (written at bootstrap, versioned
  with the project) — no more drift across skill / README / snippet.
- **`hb diagnose`.** For a blocked state, computes the root cause where the substrate
  can — which criteria fail, the commit that deleted a gate's file (git backward-trace),
  the deadlock cause — plus ordered recovery steps. Read-only.
- **SessionStart hook.** Detects a `.hb/` project and injects a tiny pointer, so a
  Claude Code session is always current regardless of installed skill version.
- Fixed a latent bug: `hb.js` is now safely `require`-able (CLI guarded).

## v1.6 — gate liveness

- **`review_stuck`** — an adversarial review that never resolves (agent doesn't run
  it / session died) is now caught by the objective no-progress breaker and escalated
  instead of silently stalling.
- **Automatic rot detection** — the tick runs `doctor` each tick and wakes `gate_rot`
  on rot; a **pre-commit hook** blocks a commit that deletes a file a completed gate
  depends on (bypass: `git commit --no-verify` / `HB_NO_HOOK=1`).

## v1.5 — gate integrity

- **`hb doctor`** — static integrity check. Headline: *rot detection* — a completed
  phase whose gate references a now-deleted file (that gate can no longer be
  reproduced). Also flags DAG errors, state/log drift, stale leases. Read-only.
- **Re-verifiable gates** — `gate.sh --check <GATE>` re-evaluates a gate read-only
  (no state change); `gate.sh --all` re-evaluates every gate (regression check). A
  passed gate keeps acting as a gate instead of a one-shot checkpoint.

## v1.4 — quality & throughput

- **Adversarial gates (second agent).** A gate may carry a `review` block; after the
  deterministic gate passes, the tick emits `review_pending` — a skeptical second
  agent must fail to *refute* completion (`hb review <gate> pass|fail`) before the
  phase advances. Closes the "grade-your-own-homework" hole. Review-less gates behave
  as before.
- **Parallel-when-no-conflict.** `hb ready [N]` surfaces the concurrently-runnable
  (eligible, unleased, requires-independent) set; fan it out as worktree-isolated
  sub-agents. `/heartbeat run` drives serial or parallel.
- **hb-lint advisory warnings.** Flags leftover template/placeholder text and gate
  criteria that reference files no task produces.
- **Notify hook.** `HB_NOTIFY_CMD` fires once on human-needed wakes (build_stuck,
  gate_blocked, deadlock, unsanctioned_drift, all_done). Timeout-bounded, fail-safe.
- **dag.schema.json** for editor validation; **per-task durations** in the report.
- **Git-aware.** Bootstrap runs `git init`; every gate pass commits and force-tags
  the gate id, so each phase is a restore point (`git reset --hard GATE_PN`). Opt out
  with `--no-git` / `HB_NO_GIT` / `HB_GIT_AUTOCOMMIT=0`.

## v1.3 — reliability hardening

- **Event-sourced state (`hb.js`).** `events.jsonl` is authoritative; `state.json`
  is a deterministic projection. Agents mutate state only via the `hb` CLI
  (`start`/`done`/`fail`/`rebuild`/`state`/`import`) — never by hand-editing JSON.
- **Objective no-progress detection.** The tick flags an agent that is woken
  repeatedly without progressing (`build_stuck`, `signal: no_progress`), independent
  of the agent's self-report.
- **Gate criterion timeout.** Each gate criterion runs under `GATE_TIMEOUT_S` (5s
  default) — a hanging criterion blocks the gate instead of hanging the tick.
- **Per-task leases + bounded concurrency.** `HB_MAX_CONCURRENCY` (default 1 =
  serial) lets independent DAG branches run in parallel; stale leases from crashed
  sessions are reclaimed automatically.
- **Mid-session heartbeat.** `hb heartbeat <id>` refreshes a lease during long
  work; a heartbeated lease that goes silent is reclaimed after `HEARTBEAT_STALE_S`
  (default 180s) instead of the slow `LOCK_STALE_S` — hung agents are caught in
  minutes. Leases that never heartbeat keep the slow fallback (no false reclaims).

## Stage A — tick.sh priority checks (order matches tick.sh)

1. **Lock** — atomic `mkdir` lock; guards concurrent ticks and the agent
   session. Stale locks (> `LOCK_STALE_S`, default 1800s) are auto-broken.
2. **Integrity** — a `dag.json` that is unreadable or structurally malformed → wake
   `dag_corrupted` (checked FIRST, every tick); then a corrupt `state.json` self-heals by rebuild,
   else wakes `state_corrupted`.
3. **Circuit breaker** — `build_stuck_count >= 5` → single wake `build_stuck`,
   then silence until human reset.
4. **Drift detection** — SHA256 of `WATCH_PATHS`; baseline auto-frozen on first
   run; unsanctioned change → wake `unsanctioned_drift`.
5. **Gate errors** — a previously failed gate (`gate.errors > 0`) → wake
   `gate_blocked`.
6. **Next task** — eligible pending task → wake; all tasks done but gate unpassed
   → `gate_pending`; project finished → single `all_done`; nothing actionable on
   an unfinished project → single `deadlock` with diagnostic.

Output is always `{ "wakeAgent": true|false, "data": { "reason": "...", ... } }`.

## Tooling (v1.2)

- `hb-next-task.js` — gate-aware resolver with deadlock diagnostics.
- `hb-lint.js` — static DAG validation (dup IDs, cycles, broken `requires`,
  undefined/unreachable gates, oversized phases).
- `hb-report.js` — progress report (text / `--json`).
- `hb-viz.js` — standalone `dag-view.html`.
- `gate.sh` — behavioural gate runner.

## Packaging

Distributed as a Claude Code plugin (local marketplace) and a fallback
`scripts/install.sh`. See `INSTALL.md`.
