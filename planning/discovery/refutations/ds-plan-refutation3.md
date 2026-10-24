# Plan refutation — Wave 3 "discovery" (DS1 / DS2), ROUND 3 (post-second-fold)

Refuter: plan-level adversarial review of the round-2-folded dag
(/home/curtism/Drums/lab/heartbeat/.hb/dag.json, `_meta.refutation_rounds` = rounds 1–2).
All live probes in mktemp-style fixtures under the session scratchpad (`r3/fx*`), phases
completed only through the CLI (`node .hb/hb.js start/done` + `bash .hb/gate.sh`,
`HB_ACTOR`-stamped regate verbs). Repo tree and the live `.hb/` untouched; no repo-root
.hb tool was run against the repo's own .hb.

Round-3 focus: attack the NEW consecutive-pin spec the way round 2 attacked round 1's —
launder-proofness inside the trust model, false positives on the existing corpus, the reach
spec's blast radius (tick / --all / PROTOCOL), constraint quality, and fold staleness.

Verdict summary: the consecutive-pin core is launder-proof where round 2's spec was not —
rebuild cannot erase it (doctor projects from `readEvents()` + `readDag()` directly,
hb.js:238-240; doctor.py reads `evs_r`; rebuild rewrites state.json only), detach cannot
touch it (detach edits `gate_entry`, never `dag.gates`), a renamed gate is correctly the
removal-drift verdict plus a fresh history, and every sanctioned sequence I could construct
stays quiet (declare→edit→rearm→pass puts the `gate_regated` between the pins; a pin cannot
follow a pending regate without a rearm because evaluation refuses exit 3; marker-sync owns
hand-cleared markers). But the spec's positional sanction rule collides with its own mandated
problem message and with three real surfaces (the sweep's park/exclusion semantics, the
PROTOCOL key's action text, the existing suite's arming idiom), and the fold left ds1c/ds2b
behind the spec they serve. UNSOUND.

---

## F13 — BLOCKING. Positional sanction makes the mandated problem message FALSE and creates the house's first unclearable PROBLEM: a laundered (or honestly strengthened-then-re-run) pin pair can never be sanctioned by anyone, including through the full regate rigor

The spec (ds1b, P2): drift = "any ADJACENT difference with no gate_regated between those two
log points". The wording is tight — sanction is positional, not existential. I verified the
machinery end-to-end (fixture r3/fx2, node runtime):

    PIN  A  (grep -q "^hello$" …)        ← CLI pass
    PIN  B  (grep -q h …)                ← hand-weaken + PLAIN re-run (the launder)
    REGATE                               ← declared AFTER the launder (accepted by hb.js)
    REARM                                ← different actor, cited artifact, audit-clean
    PIN  C  (== B)                       ← fresh pass

The `gate_regated` sits between pins B and C. No future event can ever sit between A and B,
so the A→B adjacent diff is drift FOREVER — after the full sanctioned rigor was followed to
the letter. Both remedies the spec mandates in the problem message ("naming … the sanctioned
paths (regate to revise; git-restore to retract)") were tried and cannot clear it:
- regate (above): sanctions only the B→C / final-element window; A→B persists;
- git-restore: restoring criteria to A makes the FINAL element differ from the last pin with
  no regate after it — a NEW unsanctioned diff on top of the old one.

(For the NOT-yet-re-passed case — final element only — both remedies DO work: declare-now is
positionally "between the last pin and now", and restore makes pin == current. Verified in
analysis against the fx2 event order. The message is only false for the adjacent-pair case —
which is exactly the launder case ds1a mandates as a RED test.)

Why this is a dag defect and not a feature ("the log remembers the launder forever",
`_meta` round-2 text):
1. **Internal contradiction.** ds1b simultaneously mandates permanence (positional window)
   and a message naming "regate to revise" as the sanctioned path out. For the adjacent-pair
   problem that recommendation is impossible — the runtime would ship a recovery hint that
   cannot recover. House precedent: every existing doctor PROBLEM has a working recovery path
   (rearm-artifact rot → restore the file, regate-rearm.sh case_doctor restores from backup
   and asserts clean; marker-sync → "re-declare and rearm properly" hb.js:399; stale-accepted
   → "re-run the gate" hb.js:396; missing tag → re-tag). This would be the first problem with
   none.
2. **The permanence compounds through the reach spec into a project-killer.** doctor exit 1
   forever → gate.sh --all exit 1 forever → the bootstrap-installed pre-push hook blocks
   EVERY push forever (docs/howto/block-pushes-on-failing-gates.md: hook blocks iff --all
   exits nonzero; opt-out is --no-verify per push) → and the tick either busy-wakes
   `unsanctioned_drift` every tick (the WATCH_PATHS pattern, tick.sh:221-236 — the exact
   busy-loop tick.sh:306's own comment forbids) or, if wired like the rot precedent the plan
   cites (tick.sh:188-202; tick.py:95-101), wakes once then `sleep_out`s BEFORE the next-task
   lookup — the tick never hands out work again. A permanently-drifted project is permanently
   dead on every channel, with no sanctioned exit.
3. **The honest-iteration case lands in the same permanent bucket.** Pass → notice the
   criterion is weak → STRENGTHEN it → re-run is (a) the suite's own arming idiom
   (run-tests.sh T28:410, T160:1772, T161:1786-88; py test_gate.py:223-225, 249-250) and
   (b) the natural solo-iteration flow. Doctrinally, strengthening IS a revision ("a gate
   changes only through the rigor that created it", release 1.37) — requiring declare-first
   is coherent with tier-the-refuter/regate doctrine and the plan may say so. But under this
   spec, FORGETTING the declare once is an infinite-cost mistake (permanent problem, dead
   project), which no doc currently owns and the plan's how-to task (ds2b) doesn't mention.

Required dag change — pick ONE and say it in ds1a/ds1b/P2 and the review prompt:
- **Retroactive absolution exists**: e.g. a gate_regated FOR THAT GATE positioned after the
  later pin of an adjacent diff sanctions the latest preceding unsanctioned diff (loud,
  recorded, full rearm rigor — the launder is then absolvable only through the same bar the
  honest reviser pays, which is the doctrine's actual goal: loudness, not a death sentence).
  Prompt (e) then probes that the absolution clears EXACTLY one pair and later drift re-fires.
- **Permanence is intended**: then the problem message must stop recommending the impossible
  (split wording by case: final-element → "regate to revise / git-restore to retract";
  adjacent-pair → "this record is permanent; the criteria now in force must be re-grounded
  via regate; the record stays"), the terminal tick/sweep state must be defined (see F16),
  ds2b must document "strengthen = revision; declare BEFORE editing accepted criteria; a
  forgotten declare is a permanent record", and the prompt must stop implying regate clears it.

Side nuance confirmed live (r3/fx1): the rearm-audit bar refuses rearming a HOLLOW weaken
(criteria `true` → "the DAG is not audit-clean — a hollow revision cannot rearm") — a real
defense worth citing in the how-to, but it does not help: the fx2 weaken (`grep -q h`) rearms
fine.

## F14 — BLOCKING. The sweep spec's cited precedent breaks five existing green checks; the corpus-safe alternative contradicts the precedent's rationale — the dag must pick explicitly and own the consequence

ds1b: "gate.sh --all counts drifted gates FAILING in the sweep summary (the pending-regate
precedent, both runtimes' sweeps)". The pending-regate precedent is EXCLUDE from evaluation +
count failing: gate.sh:253-259 filters regated gates OUT of the evaluated list and :277 adds
them to TOTAL_FAIL without running them ("running them proves nothing", gate.sh:310-315).
The two plausible implementations diverge on the EXISTING corpus:

Under the precedent-literal reading (exclude + count), these go RED today:
- **T160.3** (run-tests.sh:1772-1775): G1/G2 hand-edited post-pass (drift-state) → excluded
  → `two.txt` gets 0 lines, not 2.
- **T160.4** (:1776-1779): all three gates drift-state → excluded → `f.txt` 0 lines, `✗ [c]`
  count 0, not 3.
- **T161.2** (:1788-1794): GDET pin `true` vs current `false` → excluded → no criterion runs
  → no "reproduced" label. (T161.1/.3 survive: GFLK's single pin == current, still evaluated.)
- **py test_all_dedup_respects_timeout_and_failure** (test_gate.py:220-229): GA/GB drift-state
  → `f.txt` count 0, `sum(failed)` 0.
- **py test_sweep_flake_probe_labels_but_never_absolves** (test_gate.py:249-257): GDET
  drift-state → "reproduced" absent.

Under the evaluate-AND-count reading the corpus stays green (checked assertion-by-assertion:
T28.7, T160.1-4, T161.1-4, T159, T162.5, park-phase.sh:56-61, pre-push proofs, py gate tests,
test_cli --all — the red-exit expectations already hold or exit codes are ignored where drift
would add counts). But that reading RUNS unsanctioned criteria in the sweep — the exact thing
the cited precedent refuses to do, for the same doctrinal reason (a weakened criterion's pass
proves nothing). The dag cites the precedent without resolving this tension, so the spec-first
test author (ds1a) and both runtimes get a coin flip whose wrong side reddens five suite
checks. Also unpinned: whether a REMOVED ever-passed gate reaches the sweep at all — today
--all iterates `dag.gates` keys only (gate.sh:249-260), so removal silently leaves the sweep;
"counts drifted gates FAILING" is ambiguous over removal-drift.

Required dag change: name the sweep semantics (evaluate-and-count, departing from the regate
precedent's exclusion, with the reason — or exclusion, plus an explicit task to rewrite the
T160/T161/T28.7 and py fixtures to arm through declared regates, a suite change the plan must
then scope); and say whether removal-drift is counted by the sweep or is doctor-only.

## F15 — BLOCKING. Park silences the sweep channel in one sanctioned command, and the spec is silent on park × drift for every channel

Live probe (r3/fx3): an EVER-PASSED gate with a PENDING REGATE, parked → `gate.sh --all`
prints `— skipped 1 parked gate(s): G0 (regate pending: G0)` then `✅ ALL GATES PASS` exit 0.
The very precedent ds1b cites for "counted FAILING" yields to park retirement (gate.sh:248,
:258-260, :283-288: a parked regate-pending gate is annotated, never counted). `hb park` is a
one-command sanctioned verb (hb.js:1608-1635) whose own message promises "the --all sweep
skips it".

So under the spec as written: hand-weaken → re-run → `hb park <phase>` → sweep green, pushes
unblocked. Doctor is NOT park-filtered today (the park skip list names resolver, audit,
report, --all — hb.js:1634), so doctor presumably stays red — and then the TICK (doctor-
filter-based) wakes forever over a phase the user deliberately retired, or respects park if
the implementer guesses the other way. Three channels × park = three unpinned coin flips,
none probed by the prompt or ds1a's quiet list (park is absent from "every sanctioned
mutation is quiet": declared regate window, rearm+fresh pass, detach/reattach, append).

Required dag change: pin park × drift per channel (suggested by house logic: doctor problem
PERSISTS (park retires work, not evidence integrity), sweep retires-with-annotation naming
the drift (the regate-annotation precedent at gate.sh:285), tick follows doctor), add it to
ds1a's case list and the prompt's probes, or record it as an honest limit if park is allowed
to retire the sweep reach.

## F16 — BLOCKING. Reusing the EXISTING unsanctioned_drift key makes the protocol lie, and the tick's wake pattern is unpinned where F13 makes the choice project-fatal

The existing key's action text — the single source of truth that drives `data.action`,
`hb protocol`, and the skill's response table — is:
- hb.js:57: `Review the diff. If the change is intended: bash .hb/tick.sh --freeze.`
- protocol.py:17: `Review the diff. If the change is intended: hb tick --freeze.`
- SKILL.md:333: same row; dev-plugin.md:98/156 document the key as WATCH_PATHS-sha semantics.

tick.sh's wake_out injects that action verbatim into the wake JSON (tick.sh:104-115). For a
criteria-drift wake this action is wrong three ways: (1) on a default project it literally
fails — live probe: `bash tick.sh --freeze` with WATCH_PATHS="" → "WATCH_PATHS is not set —
nothing to freeze.", exit 1; (2) with WATCH_PATHS set it re-baselines an unrelated sha and
cannot clear a doctor problem → the next tick re-wakes with the same dead advice; (3) "if the
change is intended: freeze" is a ONE-ACTOR self-sanction — for accepted-criteria drift the
doctrinally correct action is regate (different-actor rearm) or git-restore, and telling the
woken agent to freeze is precisely the auto-weaken rule 5/the doctrine forbids. The plan's
"no new PROTOCOL keys" + "action text is runtime-specific by design" does not resolve this:
the shared key's TEXT must be rewritten to cover both semantics, which is runtime + skill +
docs surface (hb.js:57, protocol.py:17, SKILL.md:333 and the :256 reason list context,
dev-plugin.md:98/156, tick.sh:232's hardcoded hint, plus hb-exec.js:535's escalate path to
re-verify) that ds1b nowhere scopes and no constraint subjects name.

Also unpinned, and fatal in combination with F13: the wake PATTERN. The rot precedent the
plan leans on (tick.sh:188-202 / tick.py:95-101) wakes ONCE (flag file) then `sleep_out`s
BEFORE the next-task lookup until the problem clears — for an unclearable drift problem the
tick never serves work again. The WATCH_PATHS drift precedent (tick.sh:221-236) wakes EVERY
tick — the busy-loop tick.sh:306's own regate-guard comment names as the failure mode to
avoid. ds1a pins only tick #1 ("wakes unsanctioned_drift instead of proceeding"); tick #2's
behavior is a coin flip between halt-forever and wake-forever. The dag must pin: wake-once
flag + whether the drift state blocks the handout (and if F13 resolves to permanence, define
the terminal state a human can live with). Confirmed fine: cost and determinism — the tick
already runs doctor once per tick for rot (HB_ROT_CHECK=1 default); widening is one more grep
over the same static output.

## F17 — P2's subjects miss the python twins its claim pins (round-1 F5 class)

P2 claims "counted FAILING by gate.sh --all … both runtimes" and "wakes the tick … identical
reason keys", but its subjects list only node-side gate.sh and tick.sh. The python twins are
real, nameable files: `py/src/heartbeat/gate.py` (run_all, :226 — the sweep twin, surfaced
through cli.py:140) and `py/src/heartbeat/tick.py` (:95-101 — the rot-filter twin). If F16's
action-text fix is mandated, `py/src/heartbeat/protocol.py` and `plugin/templates/hb.js`
(PROTOCOL table) join the subject set, and SKILL.md's table row falls under DS2's docs.
P3's three strip classes (doctor/sweep/tick) are consistent with ds1b's marker classes and
its subjects are right for what it claims — no change needed there. Dag change: add the two
py subject paths (plus protocol files if F16 lands as text rewrite).

## F18 — The fold left ds1c and ds2b stale against the spec they serve, and the wave's stale-docs blast radius is unowned

(a) **ds1c**: the review prompt (d) instructs the reviewer to "check parity-notes records it"
(the desc/timeout_s honest limit) and ds1b says "the honest limit, recorded" — but ds1c's
enumerated parity-notes paragraph (append-continuation, editability boundary, rebuild
determinism, drift:cross) OMITS the honest limit (and the severity/permanence contract).
The spec-first chain breaks: a ds1c author following ds1c's letter writes a paragraph the
gate-time reviewer must then fail on prompt (d).

(b) **ds2b**: round-2 F12's recorded fix mandated "an honest clause in ds1c's parity-notes
paragraph + ds2b's how-to". ds2b's text is byte-unchanged from round 1 — no tripwire, no
honest limits (desc/timeout_s invisibility), no severity, no "strengthening is also a
revision — declare before editing accepted criteria" guidance, no permanence/absolution
story (F13), and GATE_DS2's prompt and P1/P2 never probe whether the how-to documents the
tripwire at all. The wave's one documentation artifact for the boundary can skip the
boundary's new mechanism entirely and still pass GATE_DS2.

(c) **Stale-docs scope**: ds1b changes the documented contracts of two shipped surfaces, and
no task owns the docs: docs/howto/re-verify-completed-gates.md (the --all contract: "non-zero
if any would block", regression semantics — a drifted gate that PASSES its current criteria
now fails the sweep), docs/howto/block-pushes-on-failing-gates.md ("blocks exactly when … a
gate no longer passes"), dev-plugin.md's tick check table (:90-100) and gates/--all section,
dev-python.md's tick/gate rows (:31, :58), SKILL.md:333's protocol row (F16), and
docs/howto/park-a-phase.md if F15 changes park's sweep story. AGENTS.md rule 7 (current-state
docs) binds the wave; ds2c's list (dev-tests row, howto-list, heartbeat.md line) and ds2w/ds2x
cannot catch any of these going stale. Dag change: extend ds1c/ds2c (or ds1b's mandate) to
name the owed doc updates.

## F19 — Pin-a-word: the sanction event is never gate-scoped, and multi-gate interleaving is unprobed

ds1b/P2 say "no gate_regated between those two log points" without "FOR THAT GATE". The event
carries a gate field (hb.js:1527: `{event:'gate_regated', gate, reason}`), so the natural
implementation filters — but under the unscoped reading, a sanctioned regate of gate B that
happens to land between gate A's two pins sanctions A's launder (interleave: hand-edit A →
declare+rearm+pass B → re-run A). Two runtimes must land identically and the prompt never
probes cross-gate interleaving. One word in ds1b/P2 + one probe in the prompt.

## Minor notes (fold into the fixes; not independently blocking)

- N3: "an ever-passed gate absent from the dag" — "ever-passed" is ambiguous between
  any-gate_passed and criteria-pinned-pass (a bare import pass for a gate later dropped).
  Say "criteria-pinned" for consistency with the pin selection, or "any gate_passed" and why.
- N4: "problem message bytes twin-identical" cuts against the house style of runtime-specific
  remedies inside messages (hb.js:396 embeds `bash .hb/gate.sh` where doctor.py:132 embeds
  `hb gate`). Satisfiable with runtime-neutral verb wording ("regate to revise") — flag it so
  the implementer doesn't copy the diverging house pattern and fail the byte check.
- N5: the prompt's probe (c) asserts "cmd whitespace-only" drifts (correct: byte-exact entails
  it) but ds1a's spec-first case list omits the whitespace case — the test author writing from
  ds1a alone won't pin it; add it to ds1a's drift list.
- N6: events-log truncation (the between-waves archive workflow — the live repo's events.jsonl
  was reset to one `initialized` event by the detach-wave archive; there is no `hb archive`
  verb, it is a repo-level operation) erases pin history by construction. Outside the runtime
  trust model (git-visible), but it is the one total bypass — worth one honest-limit sentence
  in ds1c's parity-notes paragraph and ds2b's how-to.

## Probed and SOUND (the new spec's load-bearing mechanics that held)

- **Rebuild cannot launder**: doctor projects from `readEvents()` + `readDag()` directly
  (hb.js:238-240; doctor.py reads evs); rebuild rewrites state.json only; prompt (h) already
  pins the survival probe. Verified data path by code.
- **Detach cannot silence**: detach/reattach edit the dependent phase's `gate_entry` and
  detach fields only (hb.js:1540-1553); `dag.gates` and the pin history are untouched; the
  drifted gate's problem persists through any detach of its phase or its dependents.
- **A renamed gate** = removal-drift (old name ever-passed, absent from dag) + a fresh,
  pin-free history for the new name — the right verdict, and the spec's removal rule covers
  it. Nuance for F13's message fix: `hb regate` refuses a gate not in the dag (hb.js:1443,
  :1519), so removal/rename-drift's ONLY remedy is git-restore — the message's "regate to
  revise" is impossible there too; the split-message fix should cover it.
- **Sanctioned sequences quiet** under positional semantics: declare→edit→rearm→fresh-pass
  puts the regate between the pins (verified event order, r3/fx2); a pin cannot follow a
  pending regate without a rearm (evaluation refuses exit 3), so "pin after regate implies
  rearm" holds mechanically; hand-cleared markers stay owned by the existing marker-sync
  problems; post-cycle re-edit (pin C → edit → re-pass) correctly drifts again (no regate
  after C).
- **Bare-pass immunity protects the corpus**: py test_tick fixtures and parity.sh resolver
  fixtures hand-write bare `{"event":"gate_passed","gate":…}` events (test_tick.py:17-20,
  :36-39; parity.sh:223-229, :271) — never pins under the criteria-pinned selection → no
  false positives there. The doctor-channel corpus is clean of post-pass criteria edits
  (regate-rearm.sh's case_doctor declares BEFORE editing — sanctioned; detach-surfacing's
  doctor_note fixtures edit detach fields, never criteria; restore-points/constraint-author/
  review-answers tamper artifacts/tags/anchors; recovery-demo/doctor-parity use file-removal
  rot; py doctor fixtures same; parity-fuzz never touches doctor or the sweep).
- **Tick cost/determinism**: doctor already runs once per tick (HB_ROT_CHECK=1,
  tick.sh:188-202); the widened filter is one more grep over the same static output — cheap
  and deterministic. (The wake pattern and action text are F16.)
- **The rearm-audit bar** refuses rearming a hollow weaken (live: criteria `true` → "a hollow
  revision cannot rearm") — an existing defense the how-to can cite.

---

Four findings (F13, F14, F15, F16) put an internally contradictory or corpus-breaking spec
inside ds1a/ds1b/P2 — under the plan's own spec-first premise the dag text is the spec, and
the test author cannot write the mandated RED tests until the dag says which side of each
coin flip is correct. F17/F18 are fold-hygiene and stale-scope gaps requiring dag text;
F19 is one word plus one probe.

UNSOUND
