---
name: heartbeat
description: HeartBeat tick-driven agent orchestration — bootstrap projects, run ticks, validate DAGs, generate reports and visualizations. Use when user mentions HeartBeat, /heartbeat, or wants to orchestrate a multi-phase project with gates.
env_keys: []
---

# HeartBeat Skill

Tick-driven agent orchestration. Stage A (bash) runs every 15-30 min. Stage B (LLM) wakes only when real work exists.

Templates: `/workspace/group/projects/heartbeat/templates/`
Bootstrap: `/workspace/group/projects/heartbeat/bootstrap.sh`

---

## Commands

### `/heartbeat init <project-dir>`

Bootstrap a new HeartBeat project:

```bash
bash /workspace/group/projects/heartbeat/bootstrap.sh <project-dir>
```

Then tell the user:
- Edit `<project-dir>/.hb/dag.json` to define phases, tasks, and gates
- Run `node <project-dir>/.hb/hb-lint.js <project-dir>/.hb/dag.json` to validate
- Schedule with `schedule_task` (see `/heartbeat schedule`)

### `/heartbeat status <project-dir>`

Show project progress:

```bash
node <project-dir>/.hb/hb-report.js <project-dir>/.hb
```

Read `<project-dir>/.hb/state.json` for current phase and task counts.

### `/heartbeat lint <project-dir>`

Validate DAG structure:

```bash
node <project-dir>/.hb/hb-lint.js <project-dir>/.hb/dag.json
```

Reports: duplicate IDs, cycles, broken `requires`, undefined gates, phases > 8 tasks.

### `/heartbeat viz <project-dir>`

Generate standalone HTML visualization:

```bash
node <project-dir>/.hb/hb-viz.js <project-dir>/.hb
```

Output: `<project-dir>/.hb/dag-view.html` — self-contained, zero external dependencies.

### `/heartbeat tick <project-dir>`

Run a manual tick (Stage A):

```bash
bash <project-dir>/.hb/tick.sh
```

Returns `{ wakeAgent, data }`. If `wakeAgent: true`, act on `data.reason` per the HeartBeat tick protocol.

### `/heartbeat schedule <project-dir>`

Read the tick.sh config section from `<project-dir>/.hb/tick.sh`, then output this ready-to-use block (fill in `<project-dir>` and `<slug>`):

```
schedule_task:
  prompt: |
    HeartBeat tick — projet <slug>.
    Résultat du script dans {{data}}.
    Agis selon {{data.reason}} — voir HeartBeat Tick Protocol dans CLAUDE.md.
    OBLIGATOIRE en fin de session : rm -rf <project-dir>/.hb/.lock

  script: |
    bash <project-dir>/.hb/tick.sh

  schedule_type: cron
  schedule_value: "*/20 * * * *"
  context_mode: isolated
```

### `/heartbeat help`

Reply with:
```
*HeartBeat v1.2 — commandes :*
• /heartbeat init <dir>     — bootstrap un nouveau projet
• /heartbeat status <dir>   — rapport d'avancement
• /heartbeat lint <dir>     — valider le DAG
• /heartbeat viz <dir>      — générer dag-view.html
• /heartbeat tick <dir>     — tick manuel
• /heartbeat schedule <dir> — bloc schedule_task prêt à l'emploi
• /heartbeat help           — cette aide
```

---

## Reference

- Templates: `/workspace/group/projects/heartbeat/templates/`
- Tests: `bash /workspace/group/projects/heartbeat/tests/run-tests.sh`
- README: `/workspace/group/projects/heartbeat/README.md`
- FTP zip: `https://chez.lavaillais.fr/mid_share/Homie/heartbeat/heartbeat-templates-v1.2.zip`
