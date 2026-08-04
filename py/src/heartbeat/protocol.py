"""The single source of truth for the tick protocol (reason -> action).

Rendered into the tick's self-describing `data.action`, `.hb/PROTOCOL.md`, and
`hb protocol`. Ported verbatim from the node hb.js PROTOCOL map so the two
implementations stay reason-compatible.
"""

PROTOCOL = {
    "next_task":          "hb start <id> -> do the work -> hb done <id> (or hb fail <id> if you could not complete it). Never hand-edit state.json.",
    "gate_pending":       "hb gate <gate> — a pass advances the phase, UNLESS the gate has a review block (then a review is owed next).",
    "review_pending":     "Spawn a skeptical reviewer to REFUTE that the phase is done (hollow tests? faked output?), then: hb review <gate> pass|fail \"<findings>\".",
    "gate_blocked":       "Run: hb diagnose — fix the ROOT cause (do NOT weaken the gate), then re-run hb gate <gate>.",
    "at_capacity":        "Nothing to do — max tasks already in flight. No action.",
    "state_corrupted":    "hb rebuild (replays events.jsonl). The tick self-heals this; only surfaces if the log itself is unusable.",
    "dag_corrupted":      "Restore dag.json from git/backup — its structure is immutable.",
    "deadlock":           "Run: hb diagnose — active_orphan: free the IDs; dag_invalid: fix the DAG and re-lint.",
    "unsanctioned_drift": "Review the diff. If the change is intended: hb tick --freeze.",
    "gate_rot":           "Run: hb diagnose — a completed phase's gate references a deleted file; restore it or re-point the gate.",
    "build_stuck":        "Run: hb diagnose — woken repeatedly without progress; root-cause it or surface a blocker report for a human.",
    "review_stuck":       "The adversarial review never resolved — spawn the refuter and record hb review <gate> pass|fail, or surface for a human.",
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
