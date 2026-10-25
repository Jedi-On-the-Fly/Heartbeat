# GATE_H2 refutation, cycle 3

Refuter: an independent agent; it did none of the work. All evidence below was gathered this round, in `mktemp -d` fixtures (bootstrap.sh / python `hb init`, `HB_NO_GIT=1 STUCK_TICKS=999`). The only repo-root commands run were `bash tests/horizon.sh` and the docs/howto/gate-examples checkers.

## Probes this round

- **G1 fix: schema path.**
  - `plugin/skills/heartbeat/SKILL.md:95` now reads "against the plugin's `${CLAUDE_PLUGIN_ROOT}/dag.schema.json` (bootstrap does not copy it into `.hb/`)". `${CLAUDE_PLUGIN_ROOT}` is the same convention SKILL.md:17-18 uses for plugin files. The plugin root is `plugin/` (`plugin/.claude-plugin/plugin.json`), and `plugin/dag.schema.json` exists.
  - A walk of the schema finds `/properties/phases/items` with `additionalProperties: False` and `horizon: {"type": "boolean", …}`.
  - The parenthetical holds for both runtimes. After `bash plugin/bootstrap.sh $T`, `.hb/` has no dag.schema.json (ABSENT). After python `hb init $T`, `.hb/` = dag.json, events.jsonl, executor.json, PROTOCOL.md, state.json (ABSENT).
  - `grep -rn "\.hb/dag\.schema"` over the repo (archives excluded) finds nothing. No doc points the planner at a nonexistent schema path. README.md:147 names `plugin/dag.schema.json`, which agrees.
  - horizon.sh n4 pins the boolean declaration, and `bash tests/horizon.sh` printed MARKER/CLOSE/APPEND/FLAGS/LIMITS/PARKED/LINT/AUDIT/REPORT-OK and HORIZON-OK.
- **Notifier claims vs. tick.sh code.**
  - The live `notify` calls are at tick.sh:204 gate_rot, :222/:404 build_stuck, :238 unsanctioned_drift, :261 gate_blocked, :292 all_done, :305 replan_pending, :312 deadlock and :360 review_stuck. That is exactly eight reasons, with no criteria_drift.
  - The tick.sh:42-44 header, dev-plugin.md:104, schedule-heartbeat-unattended.md:50-56 and parity-notes.md:154 all name those eight, exclude criteria_drift, and say python has no notifier.
  - `grep -rni notify py/src/heartbeat` returns nothing. The divergence is recorded under "Intentional divergences" in planning/parity-notes.md.
  - Behaviour, with `HB_NOTIFY_CMD` set:
    - A reached flagged horizon gave two node ticks: replan_pending, then replan_waiting. The ping log had one line, so it notified once.
    - Criteria drift (a hand-edited GATE_H1 cmd after the pass) gave two node ticks, both criteria_drift. The ping log was empty.
    - A python `hb tick` on the reached horizon woke replan_pending. The ping log was empty.
- **One 8-key human-needed stop set.** The same set appears on all four surfaces:
  - heartbeat-detect.sh:13-14 and mcp_server.py:81 (tick description): gate_blocked / build_stuck / deadlock / review_stuck / unsanctioned_drift / criteria_drift / gate_rot / replan_pending.
  - drive-heartbeat-over-mcp.md:62-63: the same set.
  - SKILL.md:221-223 (serial run): the same set, plus "a review_pending you can't clear".
- **Cycle-1 and cycle-2 fixes, re-verified.**
  - README.md:165-167 reads "the LAST LIVE phase is a flagged, unclosed knowledge horizon → replan_pending (once per horizon)", which agrees with the resolver and with c3/l2 (green).
  - dev-plugin.md audit table has `side_effecting` (warn) and `speculative_tail` (warn, "TRAILING live phases"). These match `F('warn','side_effecting')` and `F('warn','speculative_tail')` in hb-audit.js.
  - docs/howto/README.md:44-47 gives `hb horizon close --reason "<why>"`.
  - The auditor how-to's opening now says it "refuses" hollow, ungated and control-byte gates. Those are exactly hb-audit.js's three `F('error',…)` rules: hollow_gate, ungated, control_char. It "flags … as warnings or notes" vacuous, existence-only, nondeterministic, side-effecting, off-phase, unguarded and unconstrained gates, plus a speculative tail.
  - The auditor how-to's counts hold: "eleven" (:12), 11 table rows, `-> AUDIT-RULES-PROVEN:11`. The checker printed `AUDIT-RULES-PROVEN:11`.
- **The how-to's documented mechanics, run verbatim in a reached H1→H2(flag) fixture.**
  - Node and python ticks wake `replan_pending`. Each action text names both moves: append-continuation, and `node .hb/hb.js horizon close --reason <why>` (node) or `hb horizon close --reason <why>` (python).
  - `node .hb/hb-exec.js run` twice: both runs print `HB-EXEC STOP: replan_pending — H2` and exit 1, the second via replan_waiting.
  - Python `hb exec`: `HB-EXEC STOP: replan_pending — H2`.
  - The report line `Horizon: H2 REACHED — … append the next horizon's phases, or end the project with hb horizon close --reason <why>` is identical on both runtimes.
  - `HB_ACTOR=me node .hb/hb.js horizon close --reason we learned enough` takes trailing words: exit 0, and the event is `{"event":"horizon_closed","phase":"H2","reason":"we learned enough",…,"actor":"me"}`. The next tick is `all_done`, and the report then reads `Horizon: H2 closed by me: we learned`.
- **Anchors.** Every case label the how-to cites exists in tests/horizon.sh: m1-m4, n1-n4, a1-a4, f1, f2, f4, c1-c7, p1, r1-r4, l1, l2, t1-t6. Each anchor's claim matches its case:
  - case_audit runs t1/t6 to exactly one ⚠ speculative_tail naming PB, PC and PA plus the cure, with node and python bytes equal.
  - t2/t3/t4/t5 are fully gated, single-unverified-final, no-gated-head and parked-tail, and all stay quiet.
  - r2 requires REACHED plus "append" plus "horizon close".
  - The parity case names `horizon:resolve/project/lint/audit` and `drift:cross` exist in tests/parity.sh.
  - T185 at run-tests.sh:2000-2006 is keyed on `^HORIZON-OK` and `^HORIZON-SELFTEST-OK`.
- **Verbs and prose.** Every backticked verb on an added line is a registered subcommand: hb constraints/done/fail/horizon/protocol/rebuild/regate/review/start/tick, and node hb.js diagnose/horizon/regate. hb.js has `case 'horizon'`, and the python argparse list includes `horizon`. `hb tick` is python-only and is used only in python context.
  - prose-check on the nine pinned docs → ALL-PROSE-OK:9. On schedule/drive-mcp/auditor → ALL-PROSE-OK:3. docs-currency → DOCS-CURRENT-OK.

## P2 reading

- SKILL.md:45-61 and plan-to-the-horizon.md:46-73 and 151-155 both state "exactly two" sanctioned moves. The reason is mandatory: c2 refuses a missing or empty reason with no event.
- The close is a fail-closed verdict:
  - refused when the horizon is unreached or unflagged (c1), already closed (c3/c5), every phase is parked (c7), or any open revision exists (c6);
  - so it cannot end an unreached horizon or step past a regate.
- Drift is cured only by a completed regate cycle, and "Replan is a refutation outcome … never a weakened gate, constraint, or review".
- Flag deletion and parking appear only under "honest edge" (l1, l2), immediately followed by "The recorded way to end a horizon is the close verb". They are never offered as a move, and never as equal to the close. The text never uses the literal word "unsanctioned" for them, but the "exactly two sanctioned answers" list excludes them.
- "park it past the wake": the replan list offers `hb park` only for "phases to shelve" in the context of unstarted phases. The flagged completed phase is never offered for parking.
- Fabrication is tied to `speculative_tail`, named as a warning with its cut point.

## Side notes (pre-existing, not owned by this wave or plan; not counted)

1. **SKILL.md:290-291 tells a routine to hand-edit state.json.** The `/heartbeat schedule` routine prompt says "Update .hb/state.json atomically (tmp + rename) and append a task_done event to .hb/events.jsonl". This contradicts SKILL.md:326 ("Never hand-edit `state.json`") and AGENTS.md rule 1. The sentence is byte-identical in HEAD (line 279). The wave only reflowed the reason list before it, which now also covers replan_pending. It is worth a follow-up fix. No horizon claim depends on it.
2. **README.md:302 is imprecise.** It describes HB_NOTIFY_CMD as "Command run on human-needed wakes". criteria_drift is human-needed and never notifies, and python has no notifier. This line is pre-wave and loosely worded. The precise statements live in dev-plugin.md:104, the schedule how-to and parity-notes.
3. **The hook's diagnose pointer list is short.** heartbeat-detect.sh:16-17 "When blocked (…) run diagnose" omits unsanctioned_drift and replan_pending. It is a pointer to diagnose, not the stop set.

## Constraint answers

P1: NOT-REPRODUCED — the claims and their anchors hold, the falsified rows now state the new truth, and every verb and link checks out:
- Every behavioral claim in SKILL.md's horizon rule and plan-to-the-horizon.md is anchored to a real horizon.sh label whose case asserts it. `bash tests/horizon.sh` → HORIZON-OK.
- The node and python close, exec STOP, action text and report line reproduced verbatim in fixtures.
- The falsified rows state the new truth: the dev-plugin resolver/types/PROTOCOL/once-flag/exec-loop rows, the dev-python twins, the README tick summary (:165-167) and reason table, the SNIPPET reason table (replan_pending plus criteria_drift), the dev-tests T185 row, and howto-list's "T184 + T185".
- Every backticked verb is registered. ALL-PROSE-OK:9, and DOCS-CURRENT-OK.

P2: NOT-REPRODUCED — the text holds the line:
- SKILL.md:45-61 and plan-to-the-horizon.md:46-73 give exactly two sanctioned moves, and `--reason` is mandatory (c2 refuses with no event).
- The close is refused when unreached or unflagged, already closed, all parked, or under any open revision (c1, c3, c5, c6, c7). Drift is cured only by a full regate cycle.
- Flag deletion and parking appear only as the pinned honest edge (l1/l2), beside "The recorded way to end a horizon is the close verb". They are never a path.
- Fabrication is tied to `speculative_tail`. "never a weakened gate, constraint, or review" holds.

G1: NOT-REPRODUCED — the skill now names a schema path that exists:
- SKILL.md:95 now names `${CLAUDE_PLUGIN_ROOT}/dag.schema.json`, and `plugin/dag.schema.json` exists.
- Its `/properties/phases/items` has `additionalProperties: false` and `horizon: {"type": "boolean"}` (n4 green).
- `.hb/dag.schema.json` is absent after both bootstrap.sh and python `hb init`, exactly as the parenthetical says.
- `grep -rn "\.hb/dag\.schema"` across the repo returns no hits, so no doc points at a path that resolves to nothing.

CLEAR
HOLES: none
