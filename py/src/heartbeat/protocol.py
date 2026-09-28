"""The single source of truth for the tick protocol (reason -> action).

Rendered into the tick's self-describing `data.action`, `.hb/PROTOCOL.md`, and
`hb protocol`. Ported verbatim from the node hb.js PROTOCOL map so the two
implementations stay reason-compatible.
"""

PROTOCOL = {
    "next_task":          "hb start <id> -> do the work -> hb done <id> (or hb fail <id> if you could not complete it). Never hand-edit state.json.",
    "gate_pending":       "hb gate <gate> — a pass advances the phase, UNLESS the gate has a review block (then a review is owed next).",
    "review_pending":     "Spawn a skeptical reviewer to REFUTE that the phase is done (hollow tests? faked output?) — seed it with `hb refute-prompt <gate>` (the composed refute prompt: the gate's profile persona + a falsification question per criterion + the review angle). Spawn the refuter ON the profile's model: read it via `hb refute-prompt <gate> --json` (.model) and pass it to your agent-spawning tool; inherit the session model only when it is null. Write its full attempt to a findings file, then: hb review <gate> fail \"<holes>\" --model <that model>  OR  hb review <gate> pass --artifact <findings-file> --model <that model> (a pass MUST cite the refuter's written attempt — no rubber-stamps; --model records WHAT reviewed, so the per-model impact report has truth to count). CONSTRAINT-FIRST gate (plan-time review.constraints): BEFORE the refute, get the gate-time constraints — `hb constraints <gate> --prompt` (--json .model = the profile author_model) → an agent that did NOT do the work → HB_ACTOR=<author> hb constraints <gate> --record <file.json> --model <its model>; the refuter must then answer EVERY id on its own line (<ID>: VIOLATED | NOT-REPRODUCED | N/A — <evidence or reason>); when the profile sets free_review, run `hb refute-prompt <gate> --free` with another agent (the profile free_model) and record `HB_ACTOR=<free reviewer> hb review <gate> free --artifact <file> --model <its model>`. The pass is refused until every id is answered and none is VIOLATED.",
    "gate_blocked":       "Run: hb diagnose — fix the ROOT cause (do NOT weaken the gate), then re-run hb gate <gate>.",
    "at_capacity":        "Nothing to do — max tasks already in flight. No action.",
    "state_corrupted":    "hb rebuild (replays events.jsonl). The tick self-heals this; only surfaces if the log itself is unusable.",
    "dag_corrupted":      "Restore dag.json from git/backup — its structure is immutable.",
    "deadlock":           "Run: hb diagnose — active_orphan: free the IDs; dag_invalid: fix the DAG and re-lint.",
    "unsanctioned_drift": "Review the diff. If the change is intended: hb tick --freeze.",
    "gate_rot":           "Run: hb diagnose — a completed phase's gate references a deleted file; restore it or re-point the gate.",
    "build_stuck":        "Run: hb diagnose — woken repeatedly without progress; root-cause it or surface a blocker report for a human.",
    "review_stuck":       "The adversarial review never resolved — spawn the refuter, write its findings to a file, and record hb review <gate> fail \"<holes>\" or hb review <gate> pass --artifact <file>, or surface for a human.",
    "all_done":           "Write the final project report.",
}


def render_md():
    md = ("# HeartBeat — tick protocol\n\nWhen a tick returns `wakeAgent:true`, act on "
          "`data.reason`. The tick also embeds the action for the current reason in "
          "`data.action`. Full reference:\n\n| reason | action |\n|---|---|\n")
    for r, a in PROTOCOL.items():
        md += f"| `{r}` | {a.replace('|', chr(92) + '|')} |\n"
    md += ("\nNever hand-edit `state.json` — it is a projection of `events.jsonl`; mutate "
           "state only through the `hb` CLI.\n")
    return md
