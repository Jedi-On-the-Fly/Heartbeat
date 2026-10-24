#!/usr/bin/env bash
# HeartBeat SessionStart hook (v1.7).
# If the current project uses HeartBeat, inject a tiny pointer so the agent always
# knows how to act on a tick — regardless of which skill version is loaded. Stays
# silent for non-HeartBeat projects (no context pollution).
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
if [ -f "$DIR/.hb/hb.js" ]; then
  cat <<'EOF'
This project uses HeartBeat (.hb/). When a tick returns wakeAgent:true, act on
data.reason — the exact next action is already in data.action.
To run a whole project, DRIVE the loop yourself: after each action, run
`bash .hb/tick.sh` again and act on the new reason. Keep looping until the tick
says all_done or a human-needed reason (gate_blocked / build_stuck / deadlock /
review_stuck / unsanctioned_drift / criteria_drift / replan_pending). An interactive session has no
external ticker — you are the loop; a single completed task does not mean the
project is done. When blocked (gate_blocked / build_stuck / deadlock / gate_rot /
review_stuck / criteria_drift), run
`node .hb/hb.js diagnose` for a computed root-cause and recovery steps. Mutate
state only via the hb CLI. Full protocol: `node .hb/hb.js protocol` or .hb/PROTOCOL.md.
EOF
fi
exit 0
