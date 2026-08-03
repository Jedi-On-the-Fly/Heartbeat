# Installing HeartBeat on Claude Code

Two ways to install. The **plugin** is the native one-command path; the
**script** is a fallback that needs no plugin system. Pick one.

Prerequisites: **Node.js v18+** and **bash** (the runtime). **Claude Code is
optional** — it provides the `/heartbeat` skill UX, but a DAG can be executed fully
headless via `node .hb/hb-exec.js` on any machine without it (see
[Running without Claude Code](#running-without-claude-code)).

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

## Running without Claude Code

HeartBeat's runtime is **bash + node** (the tick, resolver, gates, and state). Claude
Code is just *one* Stage B. With the **executor** (`hb-exec.js`, v1.8), any project can
run on a machine that has never seen Claude Code — a server, a CI box, a teammate's
laptop. You need `node ≥18`, `bash`, `git` (optional, for restore points), and your
chosen backend's runtime.

1. **Copy the project folder** (the one containing `.hb/`) to the target machine. If
   `.hb/` predates v1.8, add the executor: copy `hb-exec.js` and `executors/` into it.
2. **Pick a backend** (`.hb/executor.json` `{ "backend": … }`, or `HB_EXEC_BACKEND`):
   - `ollama` — local models, **no API key**. Needs an Ollama server + `python3`.
     `HB_EXEC_BACKEND=ollama HB_EXEC_MODEL=qwen2.5:7b-instruct`
   - `agno` / `crewai` — `pip install agno` (or `crewai`); set `HB_EXEC_PROVIDER=ollama`
     for local models, or `=anthropic` with `ANTHROPIC_API_KEY` for Claude.
   - `script` — any command you point `HB_EXEC_CMD` at (no Python at all).
3. **Run the loop** — no Claude Code involved:
   ```bash
   node .hb/hb-exec.js run                 # serial, until all_done or a human is needed
   node .hb/hb-exec.js run --parallel 4     # worktree-isolated fan-out
   ```
4. **Drive it on a timer** with plain system cron (no cloud, no Claude Code):
   ```
   */20 * * * * cd <project-dir> && node .hb/hb-exec.js run >> .hb/exec.log 2>&1
   ```

The DAG is backend-agnostic — the same `dag.json` runs under any backend; only the
executor config picks the engine. See `tests/real-backend.sh` for a live example.

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
bash tests/run-tests.sh        # full regression suite (160 assertions) → ALL GREEN
bash tests/real-backend.sh     # optional: live end-to-end run with a local model (ollama)
```
