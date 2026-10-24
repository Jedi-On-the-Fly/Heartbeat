# Plan refutation — Wave 3 "discovery" (DS1 / DS2), ROUND 4 (post-third-fold)

Refuter: plan-level adversarial review of the round-3-folded dag
(/home/curtism/Drums/lab/heartbeat/.hb/dag.json, `_meta.refutation_rounds` = rounds 1–3).
All live probes in mktemp-style fixtures under the session scratchpad (`r4/fx1`,
bootstrapped via `plugin/bootstrap.sh`, HB_NO_GIT, phases completed only through the CLI:
`node .hb/hb.js start/done`, `bash .hb/gate.sh`, regate verbs HB_ACTOR-stamped). The repo
tree and the live `.hb/` were untouched; no repo-root .hb tool was run against the repo's
own .hb. Static evidence is cited file:line against today's main (7cc9595).

Round-4 focus: the ABSOLUTION semantics (the newest surface), the cure's interaction with
the reach, scope honesty at four folds, fold completeness, and fresh eyes on P2.

Verdict summary: the absolution core is sound — it composes correctly over multiple drift
pairs, cannot be assembled more cheaply than the sanctioned revision itself, is startable
and completable while doctor is red and even while the phase is PARKED, and the one-human-
two-actor-strings hole is the repo's existing, documented trust boundary, not a new channel.
But the absolution wording has one underdetermined anchor that two faithful implementations
can read apart (a launder becomes rigor-free absolvable under the losing reading), the
round-3 parked-pending-regate "adjacent fix" reverses a SIXTH pinned suite check and four
doc surfaces the re-spec list and ds2c do not own, the criteria_drift reason is missing its
one behavioral consumer surface (hb-exec's human-needed case table — named by round 3's own
F16 text and dropped by the fold), P2 has grown past what the house per-id answer format can
hold, and GATE_DS2's P1 does not cover the two how-tos ds2c rewrites. UNSOUND.

---

## 1. Absolution soundness — what HELD (probed against the real machinery)

Fixture r4/fx1 (node runtime; the machinery's parity is suite-pinned by T179/T180 both
runtimes, and the python doctor read the node-written fixture identically — verified live):

**The full cycle assembled exactly as the spec assumes.** CLI pass (pin A, `grep -q '^hello$'`)
→ hand-weaken (`grep -q h`) → plain re-run → pin B (the launder; gate.sh has no
already-passed guard — re-confirmed) → `HB_ACTOR=alice hb regate GATE_H1 <reason>` →
`HB_ACTOR=bob hb regate --rearm --artifact <file>` → `bash .hb/gate.sh GATE_H1` → pin C.
Event order in the log: `gate_passed(A)=3, gate_passed(B)=4, gate_regated=5, gate_rearmed=6,
gate_passed(C)=7`. Under the spec: pair A→B absolved (cycle 5-6-7 wholly after B), pair B→C
contemporaneously sanctioned (regated between), final pair C==current. Doctor healthy on BOTH
runtimes. The unsanctioned window (events 3-4) stays in the log forever. F13's cure is real.

**Absolution is NOT a cheaper laundering channel.** The cycle's cost is EXACTLY the
sanctioned revision's own bar, verified live and by code: declare needs HB_ACTOR + reason
(hb.js:1508-1527; no doctor consult, no audit consult — it succeeded over hand-edited
criteria, twice, including on a parked phase); rearm needs a DIFFERENT actor string
(same-actor refused live: "'alice' declared this revision — the rearm must come from a
DIFFERENT actor", hb.js:1463-1464), a readable artifact ≥40 substantive code points CITING a
real phase anchor (hb.js:1468-1480 — a 130-char note naming GATE_H1 passed), and an
audit-clean dag re-audited inside the write lock (hb.js:1488-1489 — a hollow weaken cannot
rearm, round-3's live defense). The fresh pass must actually pass. Compared to the front
door (declare→edit→rearm→pass) the launderer pays the SAME rigor and leaves MORE record:
the drift problem was loud until cured, the regate reason is logged, the artifact is stored
sha-pinned and doctor rot-checks it (hb.js:383-388).

**Same-human-two-actors is the existing trust boundary, and the house already says so.**
HB_ACTOR is self-declared everywhere (review pass, constraints author, rearm). The repo's
own words: "the rearm bar is PROCEDURAL evidence inside the self-declared HB_ACTOR trust
model, never mechanical proof — the human reviews the prev_criteria diff; … a forged event
log is outside the model" (docs/dev-plugin.md:150). A self-rearmed absolution cycle is that
boundary, not a new one. The plan's docs are honest enough by reference (ds1c records the
forged-log limit; dev-plugin.md:150 carries the actor limit) — recommendation N8 below adds
one clause, not a requirement.

**The order requirement is mechanically genuine.** A pin cannot land between declare and
rearm (evaluation refuses exit 3 — gate.sh:314-315, pinned by T179.2); a rearm requires a
pending regate on THAT gate (hb.js:1460 — live refusal matrix T180.1); cross-gate halves
cannot assemble (gate-scoped events + per-gate pending). A bare `hb import` pass
(hb.js import writes `{event:'gate_passed', gate}` only) is not criteria-pinned, so it can
neither shadow a pin nor complete a cycle — and staleRearm keeps the stale-accepted problem
loud over it (hb.js:396, 852-864).

**Composition verified by simulator** (r4/sim.js — the spec encoded pairwise, run over
synthetic gate-scoped logs):
- S1 (the task's construct: pin A, pin B drift, cycle, hand-edit): exactly ONE live drift —
  A→B absolved by the later cycle, B→C sanctioned, final pair C→dag drifts. "Absolves all
  EARLIER drift" + "after the later point" compose correctly pair-by-pair.
- S4 (cycle completes pinning C, then another hand-edit before any pass): the last-pin-vs-
  current pair DRIFTS — nothing can be "after now", and the only exit is a new cycle whose
  fresh pass re-pins. Correct under every reading.
- S3 (a cycle wholly BEFORE the drift, no later pass): drift stays under every reading.

**The cure is reachable in every drift shape.** Launder pair and final-element: cycle cures
(live). Removal/rename: `hb regate` refuses an unknown gate (hb.js:1443), and the mandated
message says "git-restore first to retract the content" — restore makes pin==current (cure)
or re-enables the cycle; internally consistent, F13's contradiction is gone. PARKED: declare,
rearm and the single-gate fresh pass all ran on a parked phase live (park's skip list is
resolver/audit/report/--all, hb.js:1634; gate.sh's single path checks only unknown-gate and
regate-pending) — a parked drifted gate is curable without unpark.

## F20 — BLOCKING. One underdetermined anchor in the absolution wording: a prior innocent cycle plus one later plain re-run absolves a launder under a faithful alternate reading, and no spec case or probe discriminates

ds1b: "(ii) a COMPLETED regate cycle for that gate — gate_regated then gate_rearmed then a
fresh criteria-pinned pass, in order — exists after the later point"; P2: "(a completed
regate cycle for that gate — declare, rearm, fresh criteria-pinned pass, in order — after
the later point)"; the gloss: "the last completed cycle absolves all earlier drift on that
gate". Two implementations both defensible from this text:

- **Reading A** (whole-cycle-after-L, the state-machine idiom the codebase uses for
  staleRearm/unansweredRegate/reviewCycle): scan only events after the later point for
  declare→rearm→pin. 
- **Reading B** (triple-scan anchored on the PASS — the shape "find the last completed
  cycle, absolve all drift earlier than it" invites): any reg<arm<pin triple in the log
  whose PIN postdates the later point.

Simulator S2 — `[reg, arm, pinA] … hand-edit … pinB (launder) … pinC (plain re-run)` —
DIVERGES: A = pair A→B DRIFTS (correct: no rigor was spent after the launder); B = pair A→B
ABSOLVED (the old cycle's declare/rearm predate the drift; pinC is just a routine re-run).
The sequence is realistic: a gate legitimately revised once early in its life, later
hand-weakened and re-run, then re-run once more ("prove it still passes" is the house's own
habit). Every cure case ds1a enumerates (bare declare; declare+rearm; different gate;
new-edit-after-cure) and every prompt (e) probe yields the SAME verdict under both readings
— only S2 discriminates, and neither ds1a nor the prompt contains it. Two runtimes +
spec-first = the F19 coin-flip class, and drift:cross's single fixture is not specified to
contain the S2 shape.

Required dag change (one phrase + one case + one probe):
- ds1b/P2: say the anchor — "the WHOLE cycle (the declare, the rearm and the fresh pass)
  lies after the later point" (equivalently: the declare postdates the later point).
- ds1a cure list: add "a cycle completed BEFORE the drift absolves nothing — even when
  later plain re-runs land after the drift".
- Prompt (e): add the S2 probe to the cured-while-never-reviewed hunt.

## 2. The cure × the reach — VERIFIED, one statement owed (folded into F22)

- **The single-gate path can run a drifted gate, so the cure is possible.** gate.sh's
  single-gate path consults no doctor (gate.sh:295-317: unknown-gate check + regate-pending
  exit 3 only; py gate twin likewise per dev-python.md:71's chokepoint list), and the plan
  never accidentally mandates one: ds1b scopes exclusion to "gate.sh --all and the py sweep
  twin", P2 to "both sweeps", prompt (f) to "--all". Verified live: the fresh pass ran
  through `bash .hb/gate.sh GATE_H1` in both the plain and the parked fixture.
- **No deadlock mid-cure.** The cure never needs the tick: declare/rearm/fresh-pass are
  direct CLI + gate.sh calls (live). The every-tick criteria_drift wake preempts the
  next-task handout (the rot-block position) — intended loudness, not a deadlock. Mid-cure
  semantics are coherent: a final-element drift goes quiet at the DECLARE (the regate now
  lies after the last pin — sanction (i)), and the pending-regate note + exit-3 perimeter
  own the window; a launder PAIR stays loud until the cycle completes — correct, late rigor
  is owed in full.
- **Escalate-and-stop is implied ("human-needed, like gate_blocked") but never stated, and
  the node driver would mislabel it** — see F22. Not contradicted anywhere: node hb-exec
  stops on every unhandled reason (default branch), py executor stops naming the reason
  (executor.py:586-588).

## F21 — BLOCKING. The parked-pending-regate count flip breaks a SIXTH pinned check and four doc surfaces the plan does not own; "removed-but-ever-passed" needs the round-3 word

ds1b (the round-3 "adjacent fix"): "a parked gate's PENDING REGATE must also stay in the
failing count"; P2: "(a parked pending regate likewise)". Today's pinned contract is the
opposite, by TEST and by DOCS:

- **tests/regate-fail-closed.sh case_park (:351-364), wired as T179.4's second half**
  (run-tests.sh:1910): `[ "$rc" -eq 0 ] || fail "park: a PARKED pending regate failed the
  sweep (park retirement contract broken)"` — it pins `--all` EXIT 0 over exactly the state
  ds1b flips to counted-FAILING. T179.4's own title says "parked sweep listing annotates,
  never fails". The re-spec list ("the five existing checks: T160.3/.4, T161.2 node; the two
  py gate tests") does not contain it, so a ds1a/ds1b author following the dag's letter
  reddens T179.4 and has no mandate to touch it ("updated, never weakened" covers only the
  five). The py half of case_park pins annotation only (grep, exit unpinned) — the break is
  node-side, deterministic.
- **docs/dev-tests.md:183** (T179 row): "park composes (annotated, never failing the sweep)".
- **docs/dev-plugin.md:150** (Regate section): "a parked one stays retired but its pending
  regate is annotated in the parked line".
- **docs/dev-python.md:70** (park row): "resolver/audit/report/sweep all skip it, loudly".
- **docs/howto/park-a-phase.md:34-35, 52**: "parking a completed phase retires its gate from
  the sweep"; "`--all` skips an armed parked [gate]".

ds2c names none of these (its dev-doc mandate is "tick/doctor/sweep tables gain the
criteria_drift reason and the drift problem row"), and ds2w's 8-file prose list omits
park-a-phase.md. All four files pass prose-check today (verified: dev-plugin.md,
dev-python.md, park-a-phase.md, parity-notes.md each ALL-PROSE-OK:1), so widening is cheap.

Also in the same sweep sentence: ds1b/ds1a say "removed-but-ever-passed gates appear via the
log walk" / "an ever-passed gate REMOVED from the dag drifts" — round-3 N3's ambiguity is now
OPERATIVE text: the existing sweep seen-set is ANY `gate_passed` (gate.sh:243-245, bare
import passes included) while the doctor walk ds1b specifies is "each gate ever
criteria-pinned". An imported (bare-passed) gate later dropped from the dag counts failing
forever under the any-pass sweep reading while the doctor stays quiet under the pinned scope
— two surfaces and two runtimes left to a coin flip. Say "ever criteria-pinned" in the sweep
mandate too (one word).

Required dag change: add T179.4/case_park to ds1b's re-spec list (six checks, updated to the
new contract, never weakened — and note the selftest's regate-guard strip map may need the
case's new expectations); extend ds2c to the four doc surfaces (and ds2w's count if the list
grows); pin "ever criteria-pinned" in the sweep walk.

## F22 — BLOCKING. criteria_drift's consumer surfaces: the fold dropped the one behavioral fourth surface round 3 itself named (hb-exec's human-needed case table), and escalate-and-stop is nowhere stated

ds1b's protocol-surface list: "PROTOCOL.md template, hb.js protocol table, protocol.py".
The repo has more surfaces that ENUMERATE reasons, found by sweep:

- **plugin/templates/hb-exec.js:531-540 — behavioral, and the round-3 F16 text named
  hb-exec.js:535 explicitly** ("// escalate-only: every human-needed reason stops the run
  and notifies" — a case line per reason: gate_blocked, build_stuck, deadlock,
  unsanctioned_drift, dag_corrupted, state_corrupted, gate_rot, review_stuck;
  `default: escalate('unknown_reason', reason)`). Unchanged, a criteria_drift wake stops the
  run (safe, fail-closed) but escalates as **unknown_reason**: HB_NOTIFY_CMD consumers get
  the wrong `$1`, the STOP line misnames a reason PROTOCOL.md documents, and the node driver
  diverges from the py executor, which names it correctly by fallthrough
  (executor.py:586-588 `else: print(f"HB-EXEC STOP: {reason}")`). One case line; ds1b must
  name it (and P2's subjects gain hb-exec.js if claimed — the F17 precedent).
- **The driver stop-lists** that make a reason "human-needed" in each harness:
  plugin/hooks/heartbeat-detect.sh:13-16 (the SessionStart loop contract: "keep looping
  until … all_done or a human-needed reason (gate_blocked / build_stuck / deadlock /
  review_stuck / unsanctioned_drift)") and py/src/heartbeat/mcp_server.py:81 (the `tick`
  tool description's loop-exit list). Both already lag today (gate_rot missing from the
  hook's first list and from the MCP list), so the house tolerates drift here — but this
  wave's reason is one an obedient looping driver cannot resolve alone and the plan pins
  "fires every tick until cured": name the two surfaces in ds1b (both are runtime/template
  files) or record their exclusion explicitly.
- **Docs tail for ds2c**: docs/howto/drive-heartbeat-over-mcp.md:62 (same human-needed
  enumeration) and CLAUDE-MD-SNIPPET.md:42-56 (a condensed reason→action table, already two
  reasons stale today — update it or record that the snippet is deliberately condensed).
- Clean: plugin/dag.schema.json carries no reason keys; tick.sh's case table is ds1b's own
  file; SKILL.md's row is ds2c-owned (named); hb-report.js INCIDENTS counts events, not
  reasons, and the rot precedent (gate_rot_detected) is likewise uncounted — no change owed.

And one sentence of intent: ds1a/ds1b say "human-needed, like gate_blocked; fires every tick
until cured" — the DRIVER policy (escalate and stop; the agent never self-cures past the
different-actor bar; interactive drivers surface it) is implied by analogy only. State it in
ds1b (one clause), since the wake pattern chosen ("every tick") is otherwise the shape
tick.sh:305-306's own comment warns against for unattended runs.

## 3. Scope honesty at four folds — no phase split required; one criterion hole noted

DS1 is still one coherent surface (the tripwire + its reach), 3 tasks, well under the task
ceiling; the alternative (split detection/reach) would sever the parity case from half its
subject. GATE_DS1's four criteria + P1-P3 + the prompt hold it, with ONE honest gap: the
node-side re-specified checks (T160.3/.4, T161.2 — and T179.4 once F21 lands) are verified
by NO deterministic criterion at GATE_DS1 (ds1q covers the two py tests; replan.sh/parity
don't run run-tests.sh), only by prompt (f) at review time and by ds2y one phase later.
run-tests.sh has NO group filter (verified: no argument parsing), so the full 13.5-min suite
is the only in-suite option — but `bash tests/regate-fail-closed.sh park` IS standalone and
outcome-keyed (PARK-OK): with F21's re-spec, adding it as a fifth GATE_DS1 criterion is
cheap and recommended. Not blocking by itself; F23 is the constraint-quality change that is.

## F23 — BLOCKING (fresh eyes). P2 has outgrown the per-id answer format: 199 words, ~8 contracts in one id — split into P2a/P2b

Measured: GATE_DS1 P2 claim = 199 words (violation 85, subjects 7) vs the house precedent
maxima — GATE_RG1 P3 = 107w, the regate wave's norm 51-94w, and that wave split a COMPARABLE
surface into FOUR constraints per gate. The gate-time answer format is one line per id
("<ID>: VIOLATED | NOT-REPRODUCED | N/A — <evidence or reason>", enforced by checkAnswers)
— P2 packs ~8 separately falsifiable contracts (unstarted silence; pin identity + sanction +
absolution; cure completeness; severity/bytes/message; sweep exclude+count+park+removed;
tick wake + keys + action text; desc/timeout honest limit; sanctioned-mutation quiet) into
ONE evidence line, collapsing exactly the per-id discipline the constraint machinery exists
to enforce. A reviewer cannot cite evidence for eight contracts in one answer line, and a
NOT-REPRODUCED on P2 asserts all eight at once.

Required dag change: split P2 → P2a (the boundary core: unstarted silence; the pin-sequence
identity; sanction (i) / absolution (ii) with F20's anchor; cure completeness; the
desc/timeout_s honest limit; sanctioned mutations quiet) and P2b (the reach: doctor problem
severity + twin-identical bytes + cure-naming message; sweep exclude-and-count incl. parked
and removed; tick criteria_drift keys/action until cured), partitioning the violation clause
and subjects accordingly (P2a: hb.js, doctor.py, replan.sh; P2b: gate.sh, gate.py, tick.sh,
tick.py, + hb-exec.js if F22's case line is claimed).

## F24 — BLOCKING (fold completeness). GATE_DS2's P1 does not cover the two how-tos ds2c rewrites

P1(DS2)'s claim scopes "the skill's new sections and the how-to [plan-to-the-horizon.md]";
its subjects are SKILL.md, plan-to-the-horizon.md, dev-tests.md. But ds2c rewrites
re-verify-completed-gates.md and block-pushes-on-failing-gates.md with NEW behavioral claims
(drifted gates excluded-and-counted; parked not silenced; pushes blocked over drift) — and
nothing but the prompt's one question pins their truth or anchoring. The house standard this
wave itself set (round-1 F3: prompt-only coverage is insufficient; rounds 1/3 F5/F17:
subjects must match claims; the gated-docs method: every behavioral claim anchored) requires
the constraint to name them. Fix: extend P1's claim ("…and the changed how-tos'
sweep/push claims…") + subjects with the two files (and park-a-phase.md if F21 lands).

## Minor (fold with the above; not independently blocking)

- N7: `_meta.design` still ends "so GATE_DS2 pins ALL-PROSE-OK:6" — ds2w pins :8 since the
  round-3 fold (rounds[2] records the supersession, but the design paragraph now contradicts
  the criterion it describes). One-line fix at the next fold.
- N8 (recommendation): ds2b's honest-limits list (and/or ds1c's paragraph) may add one
  clause: the cure's rigor is PROCEDURAL within the self-declared HB_ACTOR trust model —
  the house wording already exists at dev-plugin.md:150; the how-to documenting the cure is
  the natural second reader of it.
- N9: ds2w's desc says "every doc the wave touches or may touch" but its cmd omits
  wave-touched dev-plugin.md, dev-python.md (ds2c) and parity-notes.md (ds1c) — all three
  pass prose-check today, so either add them (cheap) or scope the desc to the how-to/skill
  surfaces (the round-1 F4 class, desc-only).

## Fold completeness — the rest CHECKS OUT (verified live this round)

- ds2a's citation of the how-to is sufficient: the skill cites the document that carries the
  tripwire/cure section; the SKILL protocol row is ds2c-owned; the ds2a→ds2b order leaves a
  dangling link only mid-phase (GATE_DS2 evaluates at phase end). No inconsistency with the
  never-weaken rules found.
- ds2w is reachable: the 6 existing listed files pass prose-check TODAY in one run
  (`ALL-PROSE-OK:6`), and SKILL.md still fails on the placeholder class only (the l.244
  'fill in' phrase ds2a rewords). The two round-3 additions re-verified clean.
- ds2z still non-pre-satisfied: all three greps MISS today (no T184 in dev-tests.md, no
  plan-to-the-horizon in howto-list.md, no `grp "T184` in run-tests.sh); T184 absent
  repo-wide. ds2y's idiom still correct: `GROUPS-PASSED:$_gp ` with trailing space at
  run-tests.sh:1971; no group-filter mode exists, so the full-suite 1500s budget stands.
- docs/heartbeat.md still has no doctrine enumeration (ds2c's conditional line still
  self-cancels or motivates — both implementable).
- Protocol surfaces audited beyond ds1b's three: dag.schema.json clean; hb-report.js/
  report.py INCIDENTS are event-keyed with the rot precedent uncounted (no change owed);
  hb.js diagnose is not referenced by the planned action text (no change owed). The real
  misses are F22's.

---

Five findings require dag text: F20 (one anchor phrase + one spec case + one probe), F21
(sixth re-specified check + four doc surfaces + one word), F22 (hb-exec case line + driver
stop-lists or recorded exclusion + the escalate-and-stop sentence), F23 (split P2 into
P2a/P2b), F24 (P1(DS2) claim+subjects gain the two rewritten how-tos). The absolution
doctrine itself survived its hardest probes: it composes pair-by-pair, costs the full
sanctioned bar, cures every drift shape including parked and removed, and its trust boundary
is the one the house already wrote down.

UNSOUND
