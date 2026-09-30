# Dev — Plugin (node + bash)

Backend reference for the Claude Code plugin implementation. Concept: [heartbeat.md](heartbeat.md). Python port: [dev-python.md](dev-python.md). Tests: [dev-tests.md](dev-tests.md).

Two stages. **Stage A** (`tick.sh`, bash) reads settled reality and decides whether to wake **Stage B** (a model/agent). State is an event-sourced projection. A project is a DAG. Runtime is bash + node; Python appears only inside the backend adapters (`executors/*_exec.py`).

## Layout

| Path | Role |
|---|---|
| `plugin/.claude-plugin/plugin.json` | Plugin manifest (name, version) |
| `.claude-plugin/marketplace.json` | Local marketplace descriptor (`source: ./plugin`) |
| `plugin/.mcp.json` | Registers the HeartBeat MCP server (`hb mcp-serve`) so installing the plugin wires it (both hosts) |
| `plugin/bootstrap.sh` | Scaffolds `<project>/.hb/`; git init + hooks |
| `plugin/skills/heartbeat/SKILL.md` | `/heartbeat` command surface + Tick Protocol |
| `plugin/skills/gated-docs/SKILL.md` | docs-as-verified-claims method (gate a guide with a proof/prose-check, refute it) |
| `plugin/hooks/hooks.json` + `heartbeat-detect.sh` | SessionStart pointer when a `.hb/` exists |
| `plugin/adapters/code/` + `plugin/adapters/docs/` + `plugin/adapters/research/` | **Domain adapters** — code (dep-lint + context + **discovery** + **deplint-accept** + **exclude-hb** + **coverage**/blind-spots), docs (citation-graph dep-lint + context), and research (**ground-check** the gate + **stamp-evidence** honest hashes + **research-context** Seam 2) — a **parity surface** with `py/src/heartbeat/adapters/` (node ≡ python, T94/T95/T98/T100/T106/T110–T115). Code exposed over MCP as `deplint`/`code_context`/`code_discover`. NOT scaffolded into `.hb/`, imports nothing from core. See [adapters.md](adapters.md) |
| `plugin/skills/code-aware-planning/` + `docs-authoring/` + `research-grounding/` | the per-adapter skills (enforced by skill-integrity, T92) |
| `plugin/templates/*` | Per-project tooling, copied into `.hb/` at bootstrap |

Every project owns copies of the templates under `.hb/`. `HB_DIR` = the `.hb/` dir; `PROJECT_DIR` = its parent.

## Templates → responsibility

| File | Responsibility | Module exports |
|---|---|---|
| `tick.sh` | Stage A: priority checks → wake/sleep JSON | — |
| `gate.sh` | Run a gate's shell criteria; commit+tag on pass | — |
| `hb.js` | State CLI + projector + `PROTOCOL` + doctor/diagnose | `project, phaseByGateExit, initialState, PROTOCOL, renderProtocolMd` |
| `hb-next-task.js` | Gate-aware resolver | `resolve, readyTasks` |
| `hb-lint.js` | Structural DAG validation | `lint, extractPaths` |
| `hb-audit.js` | Gate-quality audit (adversarial plan review) | `audit, classify, isNondet` |
| `hb-report.js` | Progress report (`--json`) + refuter-impact (catches/clears per gate + lens, from the event log) | `refuterImpact` |
| `hb-viz.js` | Standalone `dag-view.html` | — |
| `hb-exec.js` | Executor driver (pluggable Stage B) | `run, config, assembleContext, nonBehavioral, strictBlock` |
| `refuter_profiles.js` | Resolve a refuter-profile NAME → normalized dict | `resolve, DEFAULT_PERSONA, searchDirs, normalize` |
| `executors/*` | Backend adapters (wire protocol) | — |
| `dag.json`, `state.json` | Default templates seeded into `.hb/` | — |

## Data model

**`dag.json`** (immutable at runtime; restore from git if corrupt):

| Level | Fields |
|---|---|
| root | `_meta?`, `gates{}`, `phases[]` |
| phase | `id`, `title`, `gate_entry` (gateId\|null), `gate_exit` (gateId), `tasks[]` |
| task | `id`, `title`, `description`, `requires[]` |
| gate | `desc`, `review?{prompt}`, `criteria[]{id, desc, cmd}` |

`criteria[].cmd` is a one-line shell command; exit 0 = pass. `$PROJECT_DIR`/`$HB_DIR` in env.

**`events.jsonl`** — append-only, authoritative. State-mutating events:

| event | fields | projection effect |
|---|---|---|
| `initialized` | — | reset all |
| `task_started` | `task` | → active (unless already completed) |
| `task_done` | `task` | → completed; `build_stuck_count = 0` |
| `task_failed` | `task`, `reason?` | drop active; `build_stuck_count += 1` |
| `lease_expired` | `task` | drop active (reclaim) |
| `gate_passed` | `gate` | gate `det = true`; clear errors |
| `gate_failed` | `gate` | gate `det = false`; `errors = 1`; stuck += 1 |
| `review_passed` | `gate` | gate `rev = true` |
| `review_failed` | `gate` | gate `det = rev = false`; `errors = 1`; stuck += 1 |

Audit-only events (ignored by projector): `wake`, `review_wake`, and `log_event` markers (`stale_lock_broken`, `architecture_frozen`, `circuit_breaker_tripped`, `project_complete`, `deadlock_detected`, `gate_rot_detected`, `review_stalled`, `state_reprojected`, `unsanctioned_drift`).

**`state.json`** — projection of the log (never hand-edit):

| Field | Meaning |
|---|---|
| `current_phase` | first phase not in `completed_phases` (else last) |
| `active_tasks`, `completed_tasks` | task sets |
| `completed_phases` | phase `det` AND (no review OR `rev`) |
| `pending_reviews` | gates with review, `det` true, `rev` false |
| `build_stuck_count` | consecutive failures; circuit-breaker at 5 |
| `gate.errors` | 1 after a failed gate/review, else 0 |
| `last_event`, `last_updated` | audit |

Phase completion rule: a phase closes only when its `gate_exit` has `det` AND (the gate has no `review` OR `rev`). This is the projector invariant shared with the port ([parity-notes.md](../planning/parity-notes.md)).

## Stage A — `tick.sh`

Output contract (single JSON line): `{ "wakeAgent": bool, "data": { "reason": <string>, "action"?: <string>, ... } }`. On wake, `data.action` is injected from `hb.js` `PROTOCOL[reason]`. Invoke: `bash tick.sh` | `bash tick.sh --freeze` (re-baseline `WATCH_PATHS`).

Priority order (first match wins):

| # | Check | Wake reason (else) |
|---|---|---|
| 1 | Handout lock (`mkdir .lock`, stale > `LOCK_STALE_S`) | `already_running` (sleep) |
| 2 | `state.json` parseable (else reproject) | `state_corrupted` |
| 2 | `dag.json` parseable | `dag_corrupted` |
| 2.5 | Reclaim stale leases (`beat` > `HEARTBEAT_STALE_S`, else dir > `LOCK_STALE_S`) → `lease_expired` | (continues) |
| 2.6 | `HB_ROT_CHECK` → `hb.js doctor` rot | `gate_rot` (once), then `gate_rot_waiting` |
| 3 | `build_stuck_count >= 5` | `build_stuck` (once), then `stuck_waiting_human` |
| 4 | `WATCH_PATHS` sha changed | `unsanctioned_drift` |
| 5 | `gate.errors > 0` | `gate_blocked` |
| 6 | resolver (`hb-next-task.js`) | `next_task` / `gate_pending` / `review_pending` / `all_done` / `deadlock` / `at_capacity` (busy) / `no_pending_tasks` |

`next_task` path: enforce `HB_MAX_CONCURRENCY` (in-flight leases); no-progress guard (`STUCK_TICKS` consecutive `wake` events without a `task_*` → `build_stuck signal:no_progress`); else lease the task (`mkdir leases/<id>`), append `wake`, emit. `review_pending` appends `review_wake` and applies the same no-progress guard (→ `review_stuck`). "Once" reasons use flag files (`.stuck-alerted`, `.rot-alerted`, `.deadlock-alerted`, `.all-done-alerted`, `.noprogress-alerted`, `.review-stuck-alerted`, `.gate-notified`, `.drift-notified`) cleared on progress. `HB_NOTIFY_CMD` fires once per blockage on human-needed reasons.

## Gates — `gate.sh`

| Invocation | Effect | Exit |
|---|---|---|
| `gate.sh <GATE>` | eval criteria; on pass append `gate_passed`, reproject, git snapshot, announce review if any; on fail append `gate_failed` | pass 0 / blocked 1 / unknown 2 |
| `gate.sh --check <GATE>` | eval read-only, no state change | would-pass 0 / would-block 1 |
| `gate.sh --all` | eval every **ever-passed** gate read-only (regression sweep); never-passed/planned gates are skipped and reported | 0 / 1 |

Each criterion runs under a timeout (timeout → fail): its own `timeout_s` from `dag.json` when set (the DAG outranks the environment), else `GATE_TIMEOUT_S` (default 60 — sized for a real test-suite criterion). An invalid `timeout_s` fails the criterion loudly at runtime (T158), never silently falls back. Criteria run with stdin at `/dev/null` on BOTH timeout branches — the criteria stream rides the loop's stdin, so a slurping criterion (`docker exec -T`, `psql`) must never eat its successors' records (T165; field-reported silent fail-open skip). Every result line carries its duration (`(Ns)`), a TTY shows a transient `⏳` "running now" line (cleared before the result — captured output never carries it), and `--all` announces its scope up front and reports the elapsed total in its verdict (T159). Within one `--all` sweep, byte-identical criteria — same `cmd` **and** same effective timeout — run once and reuse the verdict, each reuse reported as `(deduped, Ns)` and counted in the verdict (T160); sound because criteria are deterministic by contract, and scoped to the sweep so there is no cross-run cache to rot. A sweep FAILURE is re-run once (the flake probe, T161): pass on re-run → labeled `FLAKY` (counted in the verdict, surfaced by the pre-push hook), fail again → labeled "reproduced" — and the verdict NEVER changes, because observed nondeterminism is itself a gate-contract violation (the behavioral complement of the auditor's static `nondeterministic` rule) and fails closed. A failing criterion surfaces its `cmd` plus a bounded tail of its captured stdout+stderr (`GATE_OUT_LINES`, default 20, loud truncation marker) — captured to a temp file, not a command substitution, so a timed-out criterion's surviving children can't hold a pipe open past the kill (T157); a passing criterion's output is discarded. Criteria are transported from the node extractor to the bash consumer as `\x1f`-joined fields **terminated by `\x1e`** (record sep), read with `read -d $'\x1e'` — newline-safe, so a `cmd` may contain an embedded newline (e.g. a heredoc) without splitting into bogus records (T153). Git snapshot (only when the git policy is on: no `HB_NO_GIT`, `HB_GIT_AUTOCOMMIT` ≠ 0, inside a git worktree): `git add -A` → commit `--no-verify` (`heartbeat(<phase-id>): <title> [GATE]`; skipped when nothing is staged — not a failure) → force-tag the gate id. A failed step is reported on stderr and recorded as `restore_point_failed {gate, step, error}` — never swallowed — and a failed add/commit SKIPS the tag (a tag on the pre-phase HEAD would make `git reset --hard <GATE>` silently discard the phase's work); `hb review pass` does the same for a review gate. Every `gate_passed` / `review_passed` carries `git:{autocommit}` (the policy in force), so `hb doctor` judges a missing tag by the policy of the time: once `_start` exists it flags an accepted gate (judged by its LAST acceptance) with no acceptance anchor, whose restore point failed after that acceptance, or with autocommit recorded on and no tag (legacy history and pending gates are never flagged; with git absent from PATH the tag check is skipped — tag state unknown, never a false alarm). Restore a phase: `git reset --hard <GATE_ID>`.

## State CLI — `hb.js`

Mutation is `withWlock` (`.wlock` mkdir) → append event → reproject → atomic write. The lock's scope is
exactly that state.json read-modify-write; the append-only informational events `tick.sh` writes (`wake`,
`lease_expired`, …) are lock-free by design (atomic O_APPEND + reproject is a full re-fold). See
[parity-notes.md](../planning/parity-notes.md) "Write-lock scope".

| Command | Effect |
|---|---|
| `start <id>` | lease + `task_started` |
| `done <id>` | `task_done` + release lease |
| `fail <id> [reason]` | `task_failed` + release lease |
| `heartbeat`/`beat <id>` | refresh lease `beat` mtime |
| `review <gate> pass\|fail\|free [--artifact f] [--model m] [note]` | `review_passed`/`review_failed`/`free_review_recorded`. On an UNCONSTRAINED gate, and for `free`, the artifact must carry a visible `HOLES: none` line and no HOLES line may list anything (`checkHoles`, same normalised visible text as the answers; a pass records `holes:"none"` + `artifact_sha256`, re-checked by `doctor`). On a CONSTRAINED gate a pass also needs this cycle's recorded gate-time set and an answer per id (`checkAnswers` — explicit rules shared with python: the word "violated" is reserved for a VIOLATED answer and checked on the whole normalised artifact (NFKC, entities, `<br>`, tags/comment markers, confusables), evidence included; answers parsed from the visible text on an ASCII-only lowercased copy, answer-shaped lines with a malformed status refused: `<ID>: VIOLATED \| NOT-REPRODUCED \| N/A — <evidence or reason>`, markdown-/case-insensitive; no VIOLATED, evidence/reason required, no duplicate/unknown id), plus — when the profile sets `free_review` — a `review free` recorded this cycle by another actor; the event records `answers` + `constraint_ids` + `artifact_sha256`, which `doctor` re-checks against the stored artifact (bytes and answers); identity comparisons are trimmed + case-insensitive and a blank `HB_ACTOR` cannot record a free review. `free` (constrained gates only; review_pending; not a doer) stores `reviews/<G>.free.md` |
| `ready [N]` | JSON of `readyTasks` (concurrently-runnable set) |
| `doctor` | integrity: rot problems + notes; exit 1 on problems |
| `diagnose [reason]` | computed root-cause + recovery (read-only) |
| `protocol [reason] [--md] [--oneline]` | reason→action map / one action / `PROTOCOL.md` |
| `rebuild` | reproject from log |
| `state` | print projection |
| `park <PHASE\|GATE> [reason…]` / `unpark <PHASE\|GATE>` | retire a phase without deleting it (sets `parked` in dag.json; resolver/audit/report/sweep all skip it, loudly; reversible) |
| `import` | seed log from a legacy `state.json` |
| `changed <gate> [--json]` | (paths with control characters are shown JSON-quoted in text output and agent prompts — a newline in a file name cannot forge a prompt section) what the phase exiting `<gate>` changed: added/modified/deleted between its entry anchor and the gate's own anchor once accepted, else the live tree (anchors below) |
| `refute-prompt <gate> [--json] [--free]` | the ONE refute compose (`refuter_profiles.composePrompt`). An UNCONSTRAINED gate: the pre-constraint compose + the HOLES block (`HOLES_BLOCK`; golden fixtures). A CONSTRAINED gate (with or without a profile): that compose + the `hb changed` list + every constraint id once, P then G (the gate-time set recorded in THIS review cycle — a set whose bytes drifted from its event is refused), the per-id answer format and the triage rule. `--free`: the compose + change list + free-review instructions + the HOLES block, no constraint block (refused on an unconstrained gate). `--json` adds `author_model`, `free_review`, `free_model` to `{prompt, model, provider, panel, refute_if}` |
| `constraints <gate> --prompt [--json]` | the gate-time constraint AUTHOR's instructions for a constrained gate (tasks, gate desc, plan-time constraints, `hb changed` list, the no-bug-hunting rule); `--json` → `{gate, prompt, model}` with `model` = the gate profile's `author_model` verbatim (null when unset) |
| `constraints <gate> --record <file.json> [--model <m>]` | record the author's G-id set: needs the gate review_pending, `HB_ACTOR` set and not a doer of the phase, a valid non-empty list (`constraintErrors(list, 'G')`, the lint's validator), each constraint GROUNDED (`groundingErrors`: at least one subject is a file in `hb changed` — added, modified or deleted — or a directory holding one; with no change list (no entry anchor) or an empty one, a project-relative path that exists; `:line`/`::symbol`/`#anchor` suffixes stripped by `subjectPath`, absolute paths, `..` and `.` never ground; areas and unchanged files allowed alongside; the refusal lists up to five changed paths); write-once per REVIEW CYCLE — a cycle starts after the gate's last review VERDICT, so re-running the gate while the review is owed never re-opens it; the check-then-write runs under the write lock (concurrent records: one wins); identity compared trimmed + case-insensitively; strict JSON (valid UTF-8, no NaN/Infinity); the gate id must be a safe file name and the file is written tmp+rename (a planted symlink is replaced, not written through); stores `.hb/constraints/<gate>.json` + `constraints_recorded {gate, ids, sha256, actor, model}`; `doctor` flags a stored set whose sha256 drifted or that vanished |
| `anchor <gate>` | internal — `gate.sh` records a review-less gate's acceptance anchor through it |

**Anchors** — HeartBeat's own record of the tree, independent of git tags: `.hb/anchors/<name>.json` = `{gate, ts, commit, files:{path:sha256}}`. `_start` is written on the first LIVE `task_started` (`hb start`; `hb-exec` shells out to it — never on `rebuild`/`import`); `<GATE>` on acceptance (a review-less pass in `gate.sh`, or `review pass`), after the restore-point commit, so `commit` is the accepted HEAD (`null` outside git). Listing: inside a git worktree `git ls-files -co --exclude-standard` (read-only — `HB_NO_GIT` only disables writes), so uncommitted and untracked work is seen and ignored files are not; outside git a walk skipping `.hb .git node_modules __pycache__ .venv` at any depth. `.hb/` and `.git/` are never listed; only regular READABLE files are hashed (an unreadable one is skipped by both runtimes, never aborting the anchor). A phase's entry anchor is its `gate_entry`'s, or `_start`. Acceptance anchors are **write-once** — re-running an accepted gate never moves its anchor (later phases' work would leak into its report). Which start is the first is decided inside the write lock (so concurrent first starts cannot both miss it); the tree is hashed after the lock is released (a large project never holds other writers past the lock timeout), streamed in chunks. A gate re-accepted later (re-run after a failure) keeps its FIRST acceptance anchor. A write failure is reported on stderr, never swallowed. Known limits: the start anchor is hashed after the lock is released, so an edit made by a SECOND concurrent `hb start` during that hash can land in `_start` (the shipped parallel runners edit in separate worktrees); a project whose log predates anchors has no `_start` (its first phase's `hb changed` refuses: no entry anchor); files inside an untracked nested git repo and symlinks are not hashed; non-UTF-8 file names are skipped. Parity: `anchors:manifest` / `anchors:changed` (git + no-git); T166.

`hb.js` is `require`-safe (CLI dispatch guarded by `require.main === module`); `tick.sh` requires it for `PROTOCOL`.

**`doctor`** — rot = a completed phase whose gate `cmd` references a now-missing path (via `extractPaths`); also DAG lint errors, state/log drift, stale leases. **`diagnose`** — infers the blocker (`gate_blocked` / `gate_rot` / `review_stuck` / `build_stuck` / `deadlock`) and prints failing criteria — or, when the gate was blocked by a failed review (the criteria pass), `Cause: review_failed` with the recorded findings — git backward-trace of a deleted gate file (`git log --diff-filter=D`), or the deadlock cause.

**`PROTOCOL`** (single source of truth; drives `data.action`, `hb protocol`, `.hb/PROTOCOL.md`) reasons: `next_task, gate_pending, review_pending, gate_blocked, at_capacity, state_corrupted, dag_corrupted, deadlock, unsanctioned_drift, gate_rot, build_stuck, review_stuck, all_done`.

## Resolver — `hb-next-task.js`

`resolve(state, dag, hbDir)` returns a task view `{id, phase, title, description, requires}` or `{type}` where type ∈ `gate_pending` (`+gate`), `review_pending` (`+gate`), `all_done`, `busy` (`+in_flight`), `deadlock` (`+cause: active_orphan|dag_invalid|unsatisfiable`). Eligibility: task pending + all `requires` done; phase reachable only if `gate_entry` passed. Leased tasks (`leases/<id>`) are excluded. `readyTasks(state, dag, hbDir, limit)` → all currently-runnable, unleased tasks.

## Lint — `hb-lint.js`

Errors (exit 1): duplicate task ID; `requires` non-existent; dependency cycle; undefined gate; `gate_entry` that is no phase's `gate_exit`; malformed plan-time constraints (`checkConstraints`: `gates.<G>.review.constraints` must be a list of `{id P<n>, claim, subjects[], violation}` — non-empty strings, ids unique within the gate, `G<n>` reserved for review-time constraints; `constraints` placed on the gate itself is an error; "non-blank" uses ONE explicit ASCII whitespace set in both runtimes, since JS `trim()` and python `strip()` disagree on `\ufeff`/`\x1c`/`\x85`). A `review` that is not a non-empty object (`true`, `false`, a string, a list, `{}`) is an error: node truthiness and python `bool()` disagree on `{}`/`[]`, so any other shape would split the runtimes on whether the gate owes a review. Every message names the gate and the id (or `#n`). Warnings (exit 0): phase > 8 tasks; gate defined-but-unreferenced; skeleton/placeholder text; gate cmd referencing a path no task produces (`extractPaths` heuristic). `extractPaths(cmd)` strips `$PROJECT_DIR`/`$HB_DIR` and state files.

## Audit

`hb-audit.js`. `classify(cmd)` → `vacuous` (trivially true) | `existence` (`test -f/-e/-d/-s`, `[`, `ls`) | `behavioral`. `isNondet(cmd)` → network/time (`curl|wget|nc|ping|sleep|$RANDOM|date|http(s) non-localhost`).

| Rule | Severity | Condition |
|---|---|---|
| `hollow_gate` | error | phase gate has criteria but none behavioral |
| `ungated` | error | gate has zero criteria |
| `unguarded_phase` | warn | phase has tasks, no `gate_exit` |
| `nondeterministic` | warn | a criterion touches network/time/randomness (`curl`, `date`, `$RANDOM`, `shuf`, `$$`, …) — not `mktemp`: a random name is not a random verdict |
| `gate_offphase` | warn | gate references files no task in the phase mentions |
| `unconstrained_review` | warn | a live phase's exit gate has a `review` block but no plan-time `review.constraints` — the refuter's target is implicit |
| `control_char` | error | a criterion cmd/desc contains a `\x1e`/`\x1f` byte (would corrupt the gate runner's record transport) |
| `vacuous` / `existence` | info | per-criterion, when not the sole behavioral one |

Exit 1 on any error. Ruleset is byte-identical to the port ([dev-python.md](dev-python.md#audit)); parity-locked.

## Executor — `hb-exec.js`

Pluggable Stage B. `run` drives the same loop as a manual session but dispatches each task to a backend and mediates every state transition. `config` (env > `.hb/executor.json` > default):

| Key | Env | Default |
|---|---|---|
| `backend` | `HB_EXEC_BACKEND` | `claude-code` |
| `cmd` | `HB_EXEC_CMD` | `defaultCmd(backend)` |
| `strict` | `HB_EXEC_STRICT` | false |
| `attemptCap` | `HB_EXEC_ATTEMPT_CAP` | 3 |
| `concurrency` | `HB_MAX_CONCURRENCY` | 1 |
| `heartbeatMs` | `HB_EXEC_HEARTBEAT_MS` | `HEARTBEAT_STALE_S*1000/2` |
| `refuteBackend` / `refuteCmd` / `refuteModel` / `refuteProvider` | `HB_REFUTE_BACKEND` / `HB_REFUTE_CMD` / `HB_REFUTE_MODEL` / `HB_REFUTE_PROVIDER` | fall back to the doer's |

Cross-model refuter: the `review_pending` refute is dispatched on `refuteCmd` with `HB_REFUTE_MODEL`/`PROVIDER` merged into the spawn env, so a distinct model refutes; each setting falls back to the doer's (backward compatible). See [cross-model-verification.md](../docs/howto/cross-model-verification.md).

**Refuter profiles** (`refuter_profiles.js`, python twin `refuter_profiles.py`, T145): `resolve(hbdir, name)` turns a profile NAME into a normalized `{persona, questions[], model, provider, verdict}` bundle from `.hb/refuters/<name>.json` (or an `executor.json` `refuters` inline entry). A built-in `default` (generic-skeptic `DEFAULT_PERSONA`) is always resolvable and **opt-in** — the no-profile path is byte-unchanged. Precedence: explicit `name` (a gate's `review.profile`) > `HB_REFUTER` env > `default`; and project files shadow shipped, shadow the built-in. An unknown **explicit** name throws (never a silent no-review). Composition of the refute prompt from a resolved profile is the ONE compose `composePrompt` / `hb refute-prompt <gate>` used by every refute surface (the executor `review_pending` and the interactive skill): no profile ⇒ today's prompt (backward-compat); else persona + BASE `review_questions` + the profile's extra questions (**appended**) + `review.prompt`; `profile.model`/`provider` route through the cross-model `refute_*` path; unknown profile fails **closed**. `hb refuters` lists profiles. `hb refute-prompt <gate> --json` emits the machine-readable binding for an interactive host — `{prompt, model, provider, panel, refute_if}`, prompt byte-identical to the text compose, all null with no profile (T163); the skill/PROTOCOL instruct the host to spawn the refuter on the profile's model and record the verdict with `--model`. Review events carry that model (`hb.js review --model`, exec auto-stamp from the resolved profile — config-derived; interactive values are the recorder's self-report; null when unknown), and `hb-report.js` breaks refuter impact down per model (`(none)` buckets the null) — T164. node ≡ python (T146/T147/T163/T164).

Loop: run `tick.sh` → route `data.reason` (a `gate_blocked` stop names its cause: `<gate>: review_failed — <finding>` when the review failed, else `gate errors`). `next_task` → `hb start` → dispatch execute (lease heartbeat pumped) → `hb done`/`hb fail` (+attempt cap → escalate). `gate_pending` → strict check (`strictBlock`: non-behavioral or lint-warning → escalate) → `gate.sh`. `review_pending` → dispatch refute → `hb review pass|fail` (a refused pass escalates `review_error` with the validator's reason; with `verdict.panel` the pass artifact is the CLEAR panelists' findings and the outvoted panelists' findings ride as the pass note, so `refute_if` keeps its meaning); on a CONSTRAINED gate `constrainedReview` runs the constraint-first pipeline: `author` dispatch (once per review cycle; model = profile `author_model`, else `refuteModel`) → `hb constraints --record` as `<worker>:author` → constrained refute (composed after recording; a panel checks EACH panelist's answers with `checkAnswers`) → free refute (`review: "free"`, model `free_model`) → `hb review free` as `<worker>:free` when the profile sets `free_review` → the same enforced `hb review pass` as `<worker>:refuter`. A refused answer set or pass is recorded as `review_failed` with the reason (the next tick is gate_blocked → escalation) — never a crash; a malformed author reply or a verdict-less refuter escalates `review_error` (T172). `all_done` → report + stop. Any human-needed reason → escalate (`HB-EXEC STOP: <reason>`); escalate-only, never auto-fixes a blocked gate.

Parallel (`concurrency > 1`): free the tick's lease, fan out `hb ready N` concurrently; each task in its own git worktree (`.hb/wt/<id>`), merge-back serialized, worktree discarded on failure; in-place fallback without git.

## Backends — `executors/`

Wire protocol — driver spawns `bash -c "<cmd> <mode>"`, mode ∈ `execute|refute|author`, payload JSON on stdin, ONE JSON line on stdout:

| Mode | stdout |
|---|---|
| `execute` | `{"ok": bool, "summary": str}` |
| `refute` | `{"refuted": bool, "findings": str}` only when the reply's last non-empty line is only the verdict (optional markup, an optional `Verdict:` label, the upper-case token, optional `.`/`!`) and the line before it neither begins with a verdict token nor ends with one after a separator — the contract is `py/tests/verdict_cases.json`; anything else (a same-line `… CLEAR`, `NOT yet CLEAR`, `REFUTED | CLEAR`, a list of both) is no verdict; a last line that is only a verdict is read at face value, whatever the reply argued before it (a hard-wrapped "…is not⏎CLEAR" included) — the answer-format check of a constraint-first review is the backstop there (for opencode: in the model's text parts, never a tool's output); a review that could not run, or a reply without a final verdict token, is `{"error": str}` (fail-closed — the driver escalates) (payload `review: "free"` = the free review; findings up to 20 000 chars) |
| `author` | `{"ok": bool, "constraints": [...]}` — the gate-time constraint author (every adapter passes the role's model, `HB_EXEC_MODEL`, to its CLI: `claude --model`, `codex -m`, `opencode -m`; none when unset — T57.2) (read-only model call; the python adapters extract the first JSON array via `_fileblocks.author_reply`, the shell adapters via an inline node extractor) |
| anything else | `{"error": "unsupported mode …"}` — never falls through to execute (T57.2 conformance) |

`defaultCmd`: `claude-code`→`claude-exec.sh`, `codex`→`codex-exec.sh`, `opencode`→`opencode-exec.sh`; each framework/local backend → its `<name>_exec.py` under `executors/` (`agno` `crewai` `ollama` `langgraph` `openai_agents` `autogen` `smolagents` `pydanticai`); else the string is the command. Backends never touch `state.json`/`gate.sh`.

| Backend | Worker mechanism | Notes |
|---|---|---|
| `claude-code` | headless `claude -p` | default |
| `codex` | headless `codex exec` (stdin closed) | `HB_EXEC_PROVIDER=oss` → keyless Ollama; `HB_CODEX_NETWORK=1` → `-c sandbox_workspace_write.network_access=true` on execute/refute (the author stays read-only) |
| `opencode` | headless `opencode run --format json` | `HB_EXEC_MODEL=provider/model` |
| `agno` | Agno agent + `FileTools` | `HB_EXEC_PROVIDER=anthropic\|ollama` |
| `crewai` | CrewAI Agent+Task+Crew | `HB_EXEC_PROVIDER`; FILE-block writer |
| `langgraph` | LangGraph ReAct agent + `save_file` | `HB_EXEC_PROVIDER=anthropic\|ollama\|openai` |
| `openai-agents` | OpenAI Agents SDK + function tool | `HB_EXEC_PROVIDER=openai\|ollama` |
| `autogen` | AutoGen AssistantAgent | `HB_EXEC_PROVIDER=openai\|ollama`; FILE-block writer |
| `smolagents` | smolagents ToolCallingAgent + `save_file` | `HB_EXEC_PROVIDER=openai\|ollama` |
| `pydantic-ai` | pydantic-ai Agent + `save_file` | `HB_EXEC_PROVIDER=openai\|ollama` |
| `ollama` | stdlib `urllib` → local model | FILE-block mini-agent |
| `script` | arbitrary `HB_EXEC_CMD` | subprocess, any language |

Python backends redirect fd 1 → stderr so only the protocol JSON reaches stdout. `_fileblocks.py` parses `===FILE: path=== … ===END===` blocks (normalizes absolute/`$PROJECT_DIR` paths, concatenates split files, refuses `.hb/` and tree escapes).

## Bootstrap — `bootstrap.sh <dir> [--force] [--no-git]`

Copies templates into `.hb/` (incl. `executors/`), lints the seeded DAG, seeds `state.json`/`events.jsonl`, writes `PROTOCOL.md`, `chmod +x`. Unless `--no-git`/`HB_NO_GIT`: `git init`, `.gitignore` for ephemeral `.hb/` runtime, a pre-commit rot hook (blocks a commit deleting a file a completed gate needs; bypass `--no-verify`/`HB_NO_HOOK`), initial commit.

## Skill + hooks

`SKILL.md` commands: `init, plan, status, lint, audit, doctor, viz, tick, run, exec, schedule, help`. `/heartbeat plan` acceptance gate: lint clean + audit clean (0 hollow) + a refutation returning SOUND before proposing. A second skill, `gated-docs`, captures the docs-as-verified-claims method (gate a guide with a runnable proof or prose-check, wire it, refute it). `hooks.json` registers a SessionStart command (`heartbeat-detect.sh`) that prints a pointer when `$CLAUDE_PROJECT_DIR/.hb/hb.js` exists, silent otherwise. The pointer is the always-on channel (independent of which skill version loads, and shared with Codex via the plugin marketplace), so it teaches the agent to **drive** the loop — after each action re-run `.hb/tick.sh` and act on the new reason, stopping only at `all_done` or a human-needed reason — not merely react to a single tick (gated by T143).

## Environment variables

| Var | Default | Consumer |
|---|---|---|
| `LOCK_STALE_S` | 1800 | tick, hb.js |
| `HEARTBEAT_STALE_S` | 180 | tick, hb-exec |
| `STUCK_TICKS` | 3 | tick |
| `HB_MAX_CONCURRENCY` | 1 | tick, hb-exec |
| `GATE_TIMEOUT_S` | 60 | gate.sh (per-criterion `timeout_s` in dag.json wins) |
| `GATE_OUT_LINES` | 20 | gate.sh (failing-criterion output tail) |
| `HB_ROT_CHECK` | 1 | tick |
| `WATCH_PATHS` | (unset) | tick drift |
| `HB_NOTIFY_CMD` | (unset) | tick |
| `HB_NO_GIT` / `HB_GIT_AUTOCOMMIT` / `HB_NO_HOOK` | unset / 1 / unset | gate.sh, bootstrap |
| `HB_EXEC_BACKEND` / `HB_EXEC_CMD` / `HB_EXEC_STRICT` / `HB_EXEC_ATTEMPT_CAP` / `HB_EXEC_MAX_ITERS` / `HB_EXEC_MODEL` / `HB_EXEC_PROVIDER` | see config | hb-exec, backends |
| `OLLAMA_HOST` | `http://localhost:11434` | ollama backend |
| `HB_OLLAMA_NUM_CTX` | 16384 | ollama backend: the context size requested (`options.num_ctx`); a prompt that fills it is refused, never answered truncated |
| `HB_DIR` | script dir | all |
| `CLAUDE_PLUGIN_ROOT` / `CLAUDE_PROJECT_DIR` | Claude Code | skill, hooks |

## Invariants

- `events.jsonl` is authoritative; `state.json` is a pure projection — mutate only via `hb.js`. Reproduce with `hb rebuild`.
- Phase-completion and projection semantics must stay identical to the port (T43 parity).
- `hb.js` must remain `require`-safe (tick depends on it).
- `PROTOCOL` is the sole reason→action source; keep reason keys in sync with the port (action text may differ per runtime).
- Gate criteria must be behavioral, deterministic, < `GATE_TIMEOUT_S`; keep the seeded template audit-clean.
