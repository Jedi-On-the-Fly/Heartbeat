# HeartBeat — tick protocol

When a tick returns `wakeAgent:true`, act on `data.reason`. The tick also embeds
the action for the current reason in `data.action`. Full reference:

| reason | action |
|---|---|
| `next_task` | hb start <id> → do the work → hb done <id> (or hb fail <id> if you could not complete it). Never hand-edit state.json. |
| `gate_pending` | bash .hb/gate.sh <gate> — a pass advances the phase, UNLESS the gate has a review block (then a review is owed next). |
| `review_pending` | Spawn a skeptical sub-agent to REFUTE that the phase is done (hollow tests? faked output?) — seed it with `node .hb/hb.js refute-prompt <gate>` (the composed refute prompt: the gate's profile persona + a falsification question per criterion + the review angle). Write its full attempt to a findings file, then: node .hb/hb.js review <gate> fail "<holes>"  OR  node .hb/hb.js review <gate> pass --artifact <findings-file> (a pass MUST cite the refuter's written attempt — no rubber-stamps). |
| `gate_blocked` | Run: node .hb/hb.js diagnose — fix the ROOT cause (do NOT weaken the gate), then re-run bash .hb/gate.sh <gate>. |
| `at_capacity` | Nothing to do — max tasks already in flight. No action. |
| `state_corrupted` | node .hb/hb.js rebuild (replays events.jsonl). The tick self-heals this; only surfaces if the log itself is unusable. |
| `dag_corrupted` | Restore dag.json from git/backup — its structure is immutable. |
| `deadlock` | Run: node .hb/hb.js diagnose — active_orphan: free the IDs; dag_invalid: fix the DAG and re-lint. |
| `unsanctioned_drift` | Review the diff. If the change is intended: bash .hb/tick.sh --freeze. |
| `gate_rot` | Run: node .hb/hb.js diagnose — a completed phase's gate references a deleted file; restore it or re-point the gate. |
| `build_stuck` | Run: node .hb/hb.js diagnose — woken repeatedly without progress; root-cause it or surface a blocker report for a human. |
| `review_stuck` | The adversarial review never resolved — spawn the refuter, write its findings to a file, and record hb review <gate> fail "<holes>" or hb review <gate> pass --artifact <file>, or surface for a human. |
| `all_done` | Write the final project report. |

Never hand-edit `state.json` — it is a projection of `events.jsonl`; mutate state
only through the `hb` CLI.
