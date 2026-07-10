# Installing HeartBeat on Claude Code

Two ways to install. The **plugin** is the native one-command path; the
**script** is a fallback that needs no plugin system. Pick one.

Prerequisites: **Node.js v18+**, **Claude Code**.

---

## Option A — Plugin (recommended)

Install from this directory as a local marketplace (nothing is published). Point
`/plugin marketplace add` at the **repo root** (the folder containing
`.claude-plugin/marketplace.json`); it discovers the plugin under `./plugin`:

```
/plugin marketplace add /absolute/path/to/heartbeat
/plugin install heartbeat
```

(`/plugin marketplace add` also accepts a GitHub `owner/repo` if you later host
it — not required.)

Then verify:

```
/heartbeat help
```

The plugin bundles the `/heartbeat` skill, the `bootstrap.sh` scaffolder, the
`templates/`, and the Tick Protocol — all resolved via `${CLAUDE_PLUGIN_ROOT}`.

To uninstall: `/plugin uninstall heartbeat`.

---

## Option B — Install script (fallback)

```bash
bash scripts/install.sh
```

This installs:
- the `/heartbeat` skill → `~/.claude/skills/heartbeat/`
- the tooling (`bootstrap.sh` + `templates/`) → `~/.claude/heartbeat/`

and runs a smoke test. It is idempotent. Optionally append the system
integration snippet (`CLAUDE-MD-SNIPPET.md`) to your `CLAUDE.md`.

Uninstall: `bash scripts/install.sh --uninstall`.

---

## Using it

```
/heartbeat init <project-dir>     # scaffold .hb/ into a project
# edit <project-dir>/.hb/dag.json  → phases, tasks, gates
/heartbeat lint <project-dir>     # validate the DAG
/heartbeat tick <project-dir>     # manual Stage A tick
/heartbeat status <project-dir>   # progress report
/heartbeat viz <project-dir>      # dag-view.html
/heartbeat schedule <project-dir> # ready-to-use /schedule routine
```

---

## Scheduling (driving the tick automatically)

HeartBeat's Stage A (`tick.sh`) is meant to run on a timer. On Claude Code:

1. **`/schedule` routine (default).** `/heartbeat schedule <dir>` emits a routine
   (cron + prompt) you create with `/schedule`. **Caveat:** routines run in
   Anthropic's cloud and clone a **GitHub repo**, so this fits when the project
   lives in a git repo the routine clones.

2. **In-session loop (local).** `/loop 20m /heartbeat tick <dir>` — runs only
   while a Claude Code session stays open.

3. **System cron (local, headless).** On your machine:
   ```
   */20 * * * * cd <project-dir> && claude -p "Run bash .hb/tick.sh and act on data.reason per the HeartBeat Tick Protocol; rm -rf .hb/.lock at end of session."
   ```

---

## Verify the install works

```bash
bash tests/run-tests.sh   # full regression suite (50 assertions) → SUITE VERTE
```
