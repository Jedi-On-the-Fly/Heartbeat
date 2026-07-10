# PLAN — Package HeartBeat as an easy-install Claude Code package

**Goal:** Make HeartBeat installable and usable on Claude Code with (a) a native
**plugin + local marketplace** and (b) a **fallback `install.sh`**. Adapt paths
away from NanoClaw (`/workspace/group/...`) and adapt scheduling from NanoClaw
`schedule_task` to Claude Code **`/schedule` routines**.

**Constraints (from user):**
- Ship **both** the plugin and the fallback script.
- **Publish nothing** — no marketplace publish, no git push, no uploads. Local only.
- Scheduling default = Claude Code `/schedule` routines.

**Design decisions:**
- Repo root == the plugin. `.claude-plugin/{plugin.json,marketplace.json}` added at
  root; `skills/heartbeat/SKILL.md` added; existing `templates/`, `bootstrap.sh`,
  `tests/` untouched. Minimises disruption to the passing test suite.
- `bootstrap.sh` is already relocatable (`TEMPLATES_DIR` is derived from `$0`), so
  it works unchanged from the plugin root or an install location.
- Skill body uses `${CLAUDE_PLUGIN_ROOT}` to locate `bootstrap.sh` + tools.
- Honest caveat documented: `/schedule` routines run in cloud and clone a GitHub
  repo → best when the HB project is a git repo; local-only projects use `/loop`
  or system cron. Routines remain the documented default.

**Cascade (phase dependency order):** P0 → P1 → P2 → P3 → P4
(P4 depends on P1, P2, P3 all being done.)

---

## Phase 0 — Baseline & green tests
**Cascade:** entry (no deps)
**Tasks**
- 0.1 Snapshot current suite (`bash tests/run-tests.sh`) → 42/43, one failure (T10.2).
- 0.2 Fix pre-existing T10.2: create `STATUS.md` documenting real v1.2 status +
  the 6 tick checks (incl. "Gate errors"), which the test asserts.
**Tests**
- `bash tests/run-tests.sh`
**Gate G0 (success checklist)**
- [ ] `bash tests/run-tests.sh` → 43 passed, 0 failed
- [ ] No source file other than the new `STATUS.md` changed in this phase
**Report:** test pass count before/after.

---

## Phase 1 — Plugin skeleton
**Cascade:** after P0
**Tasks**
- 1.1 `.claude-plugin/plugin.json` — name, version, description, author, license.
- 1.2 `.claude-plugin/marketplace.json` — local marketplace listing the plugin
  with `source: "./"`.
- 1.3 `skills/heartbeat/SKILL.md` — Claude Code skill (adapted from root SKILL.md),
  paths via `${CLAUDE_PLUGIN_ROOT}`; no `/workspace/group` references.
**Tests**
- `node -e "JSON.parse(require('fs').readFileSync('.claude-plugin/plugin.json'))"`
- `node -e "JSON.parse(require('fs').readFileSync('.claude-plugin/marketplace.json'))"`
- `test -f skills/heartbeat/SKILL.md`
- `! grep -R "/workspace/group" skills/ .claude-plugin/`
**Gate G1 (success checklist)**
- [ ] `plugin.json` and `marketplace.json` are valid JSON with required fields
- [ ] `skills/heartbeat/SKILL.md` exists with valid frontmatter (`name`, `description`)
- [ ] No `/workspace/group` path in any plugin-facing file (skill, manifests)
**Report:** files created; grep result for stray NanoClaw paths.

---

## Phase 2 — Path & schedule adaptation
**Cascade:** after P1
**Tasks**
- 2.1 Skill commands invoke `${CLAUDE_PLUGIN_ROOT}/bootstrap.sh` and the bundled
  `.hb` tools; help text in Claude Code terms.
- 2.2 `/heartbeat schedule` emits a Claude Code **routine** spec (cron + prompt
  acting on tick JSON), replacing the NanoClaw `schedule_task` YAML; include the
  cloud/git caveat + `/loop` and system-cron alternatives.
- 2.3 Update `CLAUDE-MD-SNIPPET.md` to Claude Code paths + routine protocol
  (keep the Tick Protocol table; drop `/workspace/group`).
**Tests**
- `bash bootstrap.sh /tmp/hb-p2 && test -d /tmp/hb-p2/.hb`
- `node /tmp/hb-p2/.hb/hb-lint.js /tmp/hb-p2/.hb/dag.json`
- `bash /tmp/hb-p2/.hb/tick.sh | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>JSON.parse(d))"`
- `! grep -q "schedule_task" skills/heartbeat/SKILL.md`
**Gate G2 (success checklist)**
- [ ] Fresh bootstrap creates a working `.hb/`; lint passes; tick emits valid JSON
- [ ] Schedule output references Claude Code routines, not `schedule_task`
- [ ] Cloud/git caveat + local fallbacks present in schedule output & docs
**Report:** bootstrap smoke result; schedule block preview.

---

## Phase 3 — Fallback install script
**Cascade:** after P1 (independent of P2 content, but sequenced after)
**Tasks**
- 3.1 `scripts/install.sh` — copies `skills/heartbeat/` → `~/.claude/skills/heartbeat/`,
  copies `bootstrap.sh` + `templates/` → `~/.claude/heartbeat/`, prints the
  CLAUDE.md snippet path, runs a bootstrap smoke test. Idempotent; supports a
  sandbox `HOME`. Optional `--uninstall`.
**Tests**
- `HOME=$TMP bash scripts/install.sh` → skill + templates present under `$TMP/.claude`
- `HOME=$TMP bash ~/.claude/heartbeat/bootstrap.sh $TMP/smoke && test -d $TMP/smoke/.hb`
**Gate G3 (success checklist)**
- [ ] Install into a sandbox HOME places skill + templates + bootstrap
- [ ] Post-install bootstrap smoke test creates a valid `.hb/`
- [ ] Re-running the installer is idempotent (no error, no duplication)
**Report:** installed paths; smoke result.

---

## Phase 4 — Docs & final verification
**Cascade:** after P1, P2, P3
**Tasks**
- 4.1 `INSTALL.md` — both paths (plugin marketplace add/install; script), prereqs,
  scheduling section with routine default + fallbacks.
- 4.2 README: add a short "Install on Claude Code" section linking `INSTALL.md`.
- 4.3 Extend `tests/run-tests.sh` with T15: plugin manifest validity, no hardcoded
  `/workspace/group` in plugin-facing files, and an install-script smoke test.
- 4.4 Final full run + end-to-end (bootstrap → lint → tick → report) on a temp project.
**Tests**
- `bash tests/run-tests.sh` (now includes T15)
- End-to-end temp project script.
**Gate G4 (success checklist)**
- [ ] `bash tests/run-tests.sh` → all green including new T15 group
- [ ] `INSTALL.md` documents plugin + script install and scheduling
- [ ] README has a Claude Code install section
- [ ] End-to-end temp project: bootstrap, lint OK, tick JSON valid, report renders
**Report:** final pass count; list of added/changed files; how-to-install summary.

---

## Success (overall)
A user can, with no publishing, either:
1. `/plugin marketplace add <this-dir>` → `/plugin install heartbeat` → use `/heartbeat`, **or**
2. `bash scripts/install.sh` → `/heartbeat` skill available,
and drive ticks via a Claude Code `/schedule` routine (with documented local fallbacks).
All regression tests green.
