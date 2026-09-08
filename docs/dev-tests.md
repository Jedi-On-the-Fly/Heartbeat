# Dev — Test suites

Test reference. Backends: [dev-plugin.md](dev-plugin.md) · [dev-python.md](dev-python.md).

Four surfaces. The two unit suites and the parity test are ratcheted (must stay green); the live tests are non-deterministic and run on demand.

| Surface | Entry | Scope |
|---|---|---|
| Node suite | `bash tests/run-tests.sh` | plugin (bash + node) |
| Python suite | `cd py && PYTHONPATH=src python3 -m pytest -q` | `heartbeat` package |
| Parity | `bash tests/parity.sh` | node ≡ python on shared surfaces |
| Live | `bash tests/real-backend.sh [backend] [model]` · `python3 py/real-backend.py [backend] [model]` | real local-model end-to-end |

## Node suite — `tests/run-tests.sh`

Harness: `set -uo pipefail`; per-run `TMP=$(mktemp -d)`. Globals set for determinism: `STUCK_TICKS=999` (no-progress off), `HB_NO_GIT=1` (no commits), `HB_ROT_CHECK=0` (rot off). Tests opt back in locally (e.g. T26 sets `HB_NO_GIT=""`, T30 sets `HB_ROT_CHECK`).

Helpers: `ok`/`ko` (counters), `check "<label>" '<cond>'` (`eval` the condition), `set_state '<js>'` (mutate the shared `state.json`), `tick` (clear `.lock`, run `tick.sh`). Convention: when an asserted producer exits non-zero, capture its stdout into a var before `grep` (pipefail propagates the producer's status through a pipe).

| Group | Covers |
|---|---|
| T1 | bootstrap (non-interactive) |
| T2 | `gate.sh` out-of-the-box + exit codes |
| T3 | resolver is gate-aware |
| T4 | corrupt `state.json` → auto-repair |
| T5 | leases + handout lock |
| T6 | circuit breaker (single alert) |
| T7 | `gate_blocked` wake |
| T8 | drift detection + `--freeze` |
| T9 | `all_done` (single alert) |
| T10 | doc/skill consistency |
| T11 | `hb-lint` errors |
| T12 | deadlock + corrupt dag |
| T13 | `hb-report` |
| T14 | `hb-viz` |
| T15 | packaging (plugin + install script) |
| T16 | `hb` CLI + event-sourced projection |
| T17 | objective no-progress detection |
| T18 | gate criterion timeout |
| T19 | leases + bounded concurrency |
| T20 | mid-session heartbeat (fast reclaim) |
| T21 | `hb-lint` advisory warnings |
| T22 | notify hook |
| T23 | `hb ready` + parallelism |
| T24 | adversarial gate / second agent |
| T25 | DAG schema + per-task timing |
| T26 | git init at bootstrap + commit-on-gate-pass |
| T27 | `hb doctor` rot detection |
| T28 | `gate.sh --check`/`--all` read-only |
| T29 | review no-progress → `review_stuck` |
| T30 | rot detection wakes at tick |
| T31 | pre-commit rot guard |
| T32 | `PROTOCOL` source of truth |
| T33 | self-describing ticks + `PROTOCOL.md` |
| T34 | `hb diagnose` computed root-cause |
| T35 | SessionStart hook |
| T36 | `hb-exec` driver (pluggable Stage B) |
| T37 | Agno adapter (validity + degrade) |
| T38 | CrewAI adapter (validity + degrade) |
| T39 | bootstrap ships the executor |
| T40 | parallel fan-out + worktree isolation |
| T41 | Ollama adapter (validity + degrade) |
| T42 | DAG auditor (gate quality) |
| T43 | node ↔ python parity |
| T44 | `/heartbeat plan` folds in the auditor |
| T45 | review-evidence hardening (holes stay closed) |
| T46 | review substance & identity (self-review) |
| T47 | LangGraph adapter (validity + degrade) |
| T48 | OpenAI Agents SDK adapter (validity + degrade) |
| T49–T51 | AutoGen / smolagents / pydantic-ai adapters (validity + degrade) |
| T52 | outcome-asserting coverage marker (`GROUPS-PASSED`) |
| T53 | behavioral-gate how-to proofs (weakness catalogue) |
| T54 | behavioral-gate how-to mechanism demos (refutation, fast/deterministic) |
| T55 | parity self-test + recovery proofs |
| T56 | untrusted-Stage-B / liveness / auditor proofs |
| T57 | portability / backend conformance / diagnose proofs |
| T58 | re-verify / restore-points / tick-economics proofs |
| T59 | adoption on-ramp proofs (quickstart, DAG authoring, stop/resume, backends) |
| T60 | best-practice proofs (state discipline, escalate, refute, context) |
| T61 | CI / event-log / embed / refutation-loop proofs |
| T62 | launch-prose integrity (links + real commands) + selftest |
| T63 | `hb exec config` cross-runtime behavioral parity (prints, does not run) |
| T64 | framework proof harness (Docker-free `--check`) + CrewAI/LangGraph guides |
| T65 | framework fan-out (agno/openai-agents/autogen/smolagents/pydantic-ai) harness + guides |
| T66 | codex backend (stub-on-PATH proof, Docker-free) + guide |
| T67 | MCP server (`hb mcp-serve`, stdio) — handshake, read + act tools, mutate-through-log invariant |
| T68 | MCP HTTP transport (`hb mcp-serve --http`) — real urllib round-trip + Origin/`--allow-remote` hardening |
| T69 | plugin registers the MCP server (`plugin/.mcp.json`) — static + isolated codex-live tier |
| T70 | MCP 2026-07-28 dual-stack (`server/discover`, negotiation, modern result semantics) + handshake no-regression |
| T71 | MCP security note (prose-integrity, proof-referenced) |
| T72 | opencode backend (stub proof) + opencode.json MCP wiring |
| T73 | cross-model refuter (refute on a distinct backend/model; distinct actor + provenance; both runtimes) |
| T74 | agent benchmark harness (`hb bench` — same DAG under N backends, scored from the event log) |
| T75 | parity differential-testing oracle (`tests/parity-fuzz.sh` — seeded generator, node ≡ python across generated cases; mutation self-test has teeth) |
| T76 | verifiable-reward + model-regression (`hb reward`; `hb bench --baseline`) — labeled log verdicts + regression comparator, Docker-free |
| T77 | operational how-to proofs (parallel/worktree fan-out, existing-repo non-destructive init, sparse-deps ready set, unsafe-gate auditor) |
| T78 | `gated-docs` skill (docs-as-verified-claims methodology) — prose-integrity + frontmatter/machinery consistency |
| T79 | whole how-to library prose integrity (every `docs/howto/*.md` guide gated; count-matched) + prose-check selftest |
| T80 | relative `--dir` resolves to an absolute `PROJECT_DIR`/`HB_DIR` (both runtimes) — gate + worktree paths |
| T81 | scheduled self-audit (`self-audit.sh`) — corpus prose + referenced-proof integrity + runtime parity; count-pinned, `--selftest` teeth |
| T82 | tick decision parity (`tick-parity.sh`) — node ≡ python `data.reason` (next_task/gate_pending/all_done/review_stuck/build_stuck) + the Python `review_stuck` escalation |
| T83 | gate-runner parity (`gate-parity.sh`) — pass/fail/hollow-floor/timeout agree across runtimes (exit codes) |
| T84 | doctor/rot parity (`doctor-parity.sh`) — both runtimes agree on rot detection |
| T85 | backends-registry parity (`registry-parity.sh`) — same canonical set (python-only `claude` alias normalized) |
| T86 | live viz `--serve` (`viz-serve.sh`) — fresh re-read + `Origin` 403 + non-loopback refusal + snapshot regression |
| T87 | heartbeat-code dep-lint (`code-deplint.sh`) — missing/redundant/collision, transitive-closure, advisory/strict |
| T88 | code adapter Seam 2 (`code-context.sh`) — context provider emits a subgraph (touched symbols + neighbors), not an echo |
| T89 | Seam-2 context-injection parity (`context-inject-parity.sh`) — both executors inject a `context_cmd` identically |
| T90 | docs adapter (`docs-deplint.sh` / `docs-map.sh`) — citation graph → codemap, the **unchanged** deplint generalizes |
| T91 | docs adapter Seam 2 (`docs-context.sh`) — renders a task's direct-cited section text (not 2-hop/self) |
| T92 | adapter skill-integrity (`skill-integrity.sh`) — every adapter ships a skill naming real, wired proofs |
| T93 | whole-`docs/` prose gate — every markdown under `docs/` prose-integrity-checked (not just how-tos) |
| T94 | code adapter parity (`deplint-parity.sh` / `codegraph-map-parity.sh` / `codegraph-context-parity.sh`) — node ≡ python |
| T95 | docs adapter parity (`docs-map-parity.sh` / `docs-context-parity.sh`) — node ≡ python |
| T96 | adapters node-free (`adapters-nodefree.sh`) — Python adapters + a python `context_cmd` with no Node on `PATH` |
| T97 | MCP adapter tools (`mcp-adapters.sh`) — `deplint` + `code_context` on real `mcp-serve` == the Python adapter |
| T98 | code adapter discovery (`code-discover.sh`) — transitive reachability (dependents/dependencies/both), node ≡ python |
| T99 | MCP `code_discover` (`code-discover-mcp.sh`) — on real `mcp-serve` == the discovery function |
| T100 | deplint-accept (`deplint-accept.sh`) — plan-acceptance wrapper: codemap resolution + clean skip, node ≡ python |
| T101 | deplint precision (`deplint-redundant-empty.sh`) — no REDUNDANT for a task with no resolved symbols (spec-first / new files) |
| T102 | codegraph-exclude-hb (`codegraph-exclude-hb.sh`) — keep CodeGraph off `.hb/`, idempotent, node ≡ python |
| T103 | checkpoint lifecycle — a review-gated `GATE_x` is tagged only at **review acceptance**, not the deterministic pass (node ≡ python) |
| T104 | `hb-audit --questions` — falsification questions derived per criterion class to seed the review (node ≡ python) |
| T105 | gate evidence provenance — `gate_passed` records `{criteria,commit,runtime}`; `hb evidence` reads it back (node ≡ python) |
| T106 | code adapter coverage (`code-coverage.sh`) — per-task symbol coverage + **GRAPH-BLIND** list (node ≡ python) |
| T107 | docs adapter — `docs-map` recognizes reference-style links, not just inline (node ≡ python) |
| T108 | docs adapter real-corpus — `docs-map` over the repo's own `docs/` is a non-empty graph (regression guard, node ≡ python) |
| T109 | docs change-impact reuses the neutral discover engine (reverse-citation reachability) |
| T110 | research adapter (`ground-check.sh`) — claims grounded in stored sources; fabricated / ungrounded / missing / stale |
| T111 | research adapter parity (`ground-check-parity.sh`) — ground-check node ≡ python (byte-identical report) |
| T112 | research adapter Seam 2 (`research-context.sh`) — renders a section's grounded claims for the writer (node ≡ python) |
| T113 | research adapter (`stamp-evidence.sh`) — honest source shas so ground-check can verify + catch a later edit (node ≡ python) |
| T114 | research boundary (`ground-check-redteam.sh`) — gate catches mechanical fabrication, stays **silent on truth** (grounded-but-wrong) |
| T115 | research scale/parity (`research-scale-parity.sh`) — node ≡ python on 60 sources / 200 claims (unicode, line-wraps) |
| T116 | adapter doc-coverage (`adapters-doc-coverage.sh`) — every shipped `plugin/adapters/<domain>` tool is named in `adapters.md` |
| T117 | pre-push gate guard installed by bootstrap — blocks on a failing gate, non-clobber, HB_NO_HOOK / --no-verify bypass, existing repos (`pre-push-hook.sh`) |
| T118 | pre-push guard is behavioral node ≡ python — both bootstraps install a blocking hook (`pre-push-hook-parity.sh`) |
| T119 | review integrity — a degraded refuter → review_error (never a pass), a genuine review isn't discarded, robust verdict; both runtimes (`refute-integrity.sh`) |
| T120 | `hb init` preserves the append-only event log unless --force (parity with node) (`init-preserves-log.sh`) |
| T121 | gate criteria run under bash in both runtimes (not dash) + failing output surfaced (`gate-shell-parity.sh`) |
| T122 | the pre-push hook is self-contained/honest — tested as it runs; hb-absent = skip, not import-error block (`pre-push-selfcontained.sh`) |
| T123 | CI workflow wires the three suites (run-tests.sh + pytest + parity.sh) (`ci-workflow.sh`) |
| T124 | how-to index + dev-tests T-table stay derived-consistent with source (`index-coverage.sh`) |
| T125 | honest claims — LICENSE (MIT) + no unpublished pip-install as an install line (`claim-honesty.sh`) |
| T126 | kernel: rot-lint precision (`rot-lint-precision.sh`) — extractPaths excludes sed/awk constructs + absolute paths, keeps real relative artifacts |
| T127 | kernel: deterministic state projection (`state-determinism.sh`) — two rebuilds → byte-identical state.json |
| T128 | kernel: git-optional gate pass (`gate-gitless.sh`) — a gate passes with no git binary, no crash |
| T129 | kernel: gate_blocked circuit breaker (`gate-blocked-breaker.sh`) — a persistently blocked gate stops re-waking after a bound |
| T130 | safety: python verdict by final REFUTED/CLEAR token (`verdict-robust.sh`) — shared helper, not grep-anywhere |
| T131 | safety: argv-not-source-splice (`injection-safe.sh`) — doctor no shell-injection via a \$(...) path; bootstrap node -e argv-safe |
| T132 | portability: macOS-safe drift hashing (`drift-portable.sh`) — shasum fallback, not a silent no-op |
| T133 | portability: adapter-skill commands use ${CLAUDE_PLUGIN_ROOT} (`skill-paths.sh`) — resolve from an installed plugin |
| T134 | portability: MCP entry runtime-honest + command-surface decided (`mcp-json-runtime.sh`) |
| T135 | honesty: coverage floor (`coverage-floor.sh`) — the runner emits a `GROUPS-SKIPPED:` count and `_coverage_check` marks a mostly-skipped run INCOMPLETE (exit 3), not a silent ALL-GREEN |
| T136 | honesty: every example DAG gated (`example-dags-gated.sh`) — all planning/*.dag.json lint clean + 0 hollow |
| T137 | honesty: audit-fixture count in docs matches parity.sh (`doc-fixture-count.sh`) |
| T138 | anti-drift: must-not-drift logic is single-sourced (`single-source.sh`) — SKILL.md reason table == protocol.py keys; hb-exec imports hb-audit's `nonBehavioral` (no fork) |
| T139 | safety: write-lock gives real mutual exclusion (`wlock-tested.sh`) — two concurrent workers through withWlock/with_wlock serialize an RMW (counter==2); gutting the lock makes it RED, node + python |
| T140 | safety: tick.sh's lock-free appends are corruption-safe (`tick-append-safe.sh`) — 60 concurrent O_APPEND appends + real concurrent ticks keep events.jsonl valid & complete; `--selftest` shows a non-atomic writer loses updates (teeth) |
| T141 | parity: git-snapshot on review acceptance (`git-snapshot-parity.sh`) — `hb review GATE_P0 pass` commits + force-tags in both node and python; a missing tag is RED (cross-runtime pair `hb.js review` ≡ `gate._git_snapshot`) |
| T142 | honesty: docs reflect current code (`docs-currency.sh`) — dev docs describe review_policy/accept_review + GROUPS-SKIPPED, no doc references the moved audit-fixtures/parity-fixtures paths, plugin==marketplace version; `--selftest` proves teeth |
| T143 | reliability: the SessionStart hook teaches DRIVING the loop (`hook-drives-loop.sh`) — on a `.hb/` project the pointer instructs re-running `.hb/tick.sh` in a loop and names the stop conditions (all_done + a human-needed reason), silent off-project; `--selftest` proves teeth (reactive-only text is rejected). Closes the interactive-agent gap where a single completed task read as "done" |
| T144 | reliability: the MCP `tick` tool teaches DRIVING the loop (`mcp-drives-loop.sh`) — driving the real `hb mcp-serve`, the tick tool's description instructs calling `tick` again in a loop until all_done/human-needed, a pending tick carries a `data.next` nudge, and an all_done tick does not; `--selftest` proves each check individually load-bearing. The MCP twin of T143 (Python-only surface, no parity obligation) |
| T145 | refuter profiles: the resolver (`refuter-profile-resolve.sh`) turns a NAME into a normalized `{persona, questions[], model, provider, verdict}` profile — a named profile resolves from `.hb/refuters/<name>.json`, a built-in `default` is always resolvable (refutation can't fail-open for a missing profile), an unknown EXPLICIT name errors (never a silent no-review), and precedence (explicit > HB_REFUTER env > project-file > built-in) holds; node ≡ python (parity oracle). `--selftest` mutates a fake resolver so each field, each precedence tier, and the unknown-errors path is individually load-bearing |
| T146 | refuter profiles: the shareable library (`refuter-library.sh`) — a shipped `plugin/templates/refuters/` profile is seeded into `.hb/refuters/` by bootstrap (no-clobber, so a project file shadows a shipped one of the same name and survives re-bootstrap), every shipped refuter is valid + resolves (behavioral integrity, not `test -f`), and `hb refuters` lists the project's profiles identically node ≡ python. `--selftest` proves seeding / override / discovery-parity / integrity each individually load-bearing |
| T147 | refuter profiles: ONE `hb refute-prompt <gate>` compose (`refuter-compose.sh`) serves the refute path — no profile ⇒ byte-identical to today's prompt (backward-compat), a named profile injects persona + the gate's BASE `review_questions` (APPENDED, never replacing) + the profile's extra questions + `review.prompt`, `profile.model` reaches the refute dispatch (observed via a stub backend), an unknown profile fails closed at the dispatch (review not skipped), distinct-actor + fail-closed intact; node ≡ python (byte-identical compose + `parity.sh refute-prompt:composed`). `--selftest` proves backward-compat / append-not-replace / unknown-errors each load-bearing |
| T148 | refuter profiles: perspective-diverse panel (`refuter-panel.sh`) — a profile `verdict {panel:N, refute_if:'majority'|'any'|'all'}` runs N refute dispatches and aggregates the boolean verdicts (majority ⇒ >N/2, any ⇒ ≥1, all ⇒ unanimous); the no-panel single-verdict path is unchanged; fail-closed holds (a panelist with no boolean verdict cannot certify a pass); a panel that aggregates to CLEAR but whose panelists cite NO evidence cannot certify a pass either (the `[panelist i/N]` label attaches only to real findings, so boilerplate can't clear the substance floor — Rule 6); identical aggregation node ≡ python (`parity.sh panel-aggregate`). `--selftest` proves majority/any/all each produce a distinct outcome and a non-bool is an error |
| T156 | gate integrity: portable per-criterion timeout (`gate-timeout-portable.sh`) — `gate.sh` bounds every criterion even when neither `timeout` nor `gtimeout` is installed (stock macOS has no coreutils); under a curated PATH with both absent, a criterion that sleeps past `GATE_TIMEOUT_S` is KILLED via a shell-level bound (background + poll + kill) → gate blocks (✗), returning fast, while a quick criterion still passes — parity with the python runner (always bounded via `subprocess` timeout). Closes the gap where the bash runner ran criteria UNBOUNDED without a timeout binary. `--selftest` proves `run_bounded` flags a hang / clears a quick cmd and the curated PATH excludes `timeout`/`gtimeout` while keeping `bash`/`node`/`sleep` |
| T154 | gate integrity: auditor `control_char` rule (`audit-ctrl-byte.sh`) — a criterion whose cmd/desc carries a `\x1e`/`\x1f` byte (the transport delimiters) is a LOUD audit error (exit 1), turning the one residual transport fragility into a caught-before-run failure instead of a silent miscount; node ≡ python; also proven triggerable by the rule-completeness self-audit (`audit-rules-check.sh`). `--selftest` proves the detector discriminates and both bytes trigger it |
| T155 | bootstrap non-interactive safety (`bootstrap-noninteractive.sh`) — re-bootstrapping a project that already has `.hb/` prompts `Overwrite?` only with a real terminal (`[ -t 0 ]`); a non-interactive caller whose stdin is a live-but-silent pipe (never a byte, never EOF) blocks forever under the old `read ... \|\| REPLY="n"` guard (which covers EOF, not never-returns) — now it refuses safely; a `/dev/null` stdin refuses; `--force` still overwrites. Portable — carries its own `run_bounded` (background + poll + kill), never `timeout(1)` (absent on stock macOS, the platform the bug hangs on). `--selftest` proves the silent-pipe detector flags the unguarded read AND clears the `[-t 0]`-guarded one |
| T153 | gate integrity: newline-in-cmd transport (`gate-newline-cmd.sh`) — `gate.sh` feeds criteria from its node extractor to the bash consumer as `\x1f`-joined fields TERMINATED by `\x1e` (record sep), read with `read -d $'\x1e'`, so a `cmd` containing an embedded newline (a heredoc) is one record — not split into bogus empty-CMD lines that trivially "pass" (a false gate). A 3-fail gate with a heredoc middle criterion reports 0/3, no bogus entries, node/bash ≡ python (python `gate.py` reads the dag directly, the oracle). Regression guard for a silent-miscount bug; `--selftest` proves the count/bogus-entry checks load-bearing |
| T152 | refuter profiles: `hb report` refuter-impact (`refuter-impact.sh`) — from the event log (truth), a `review_failed` is a CATCH and a `review_passed` a clear, counted per gate with the gate's `review.profile` lens + the findings text, so a run answers "did the refuter earn its keep?"; it records what was caught, never what was missed (unknowable); a review-less project reports zero and renders no section; node ≡ python on the canonical summary (`report.refuter_impact` ≡ `refuterImpact`, `parity.sh refuter-impact`). `--selftest` proves the count/lens/findings/parity checks each load-bearing |
| T151 | refuter profiles: quick scaffolder (`refuter-scaffold.sh`) — `hb refuters new <name> [--from <starter>] [--lite]` writes a refuter that immediately RESOLVES (a canonical `<name>/SKILL.md` folder by default, or a lite `<name>.md`), `--from` carries a shipped starter's lens, an unknown starter and a path-separator name error, no-clobber across all formats, and the scaffolded bytes are identical node ≡ python (shared `render_skill`/`renderSkill`); the bare `hb refuters` list still works after the `new` sub-action is added. `--selftest` proves resolvable-output / unknown-errors / no-clobber / byte-parity / bare-list each load-bearing |
| T150 | refuter profiles: skill-format authoring (`refuter-skill-format.sh`) — a refuter may be authored as a canonical agent-skill folder `<name>/SKILL.md` or a lite `<name>.md` (flat frontmatter + persona body + `## Checklist` bullets); both resolve to the same normalized dict as the `.json` form via a SHARED no-YAML line-parser, node ≡ python across every divergence trap (first-colon, quotes, whitespace, CRLF/BOM, key-case, dup-keys, checklist casing, bullet style, persona trim); `hb refuters` lists folder + lite + json (a `references/` subdir is not a refuter); a same-name cross-format collision errors; bootstrap seeds `.md` + folders collision-safe. `--selftest` mutates the parser per-trap to prove each parity check load-bearing; `--seeding` proves the shipped library defines no name in >1 format and a bootstrapped project resolves every seeded refuter incl. a folder one |
| T149 | refuter profiles: panel `verdict` placement (`refuter-verdict-placement.sh`) — a panel is configured by the refuter **profile**'s `verdict` field only; a `verdict` placed on the gate's `review` block is silently inert. By counting refute dispatches through a stub: `verdict{panel:3}` on the profile drives 3, the same on the gate drives 1 (the single-verdict path), both runtimes. Goes RED if the executor ever honours a gate-level verdict. `--selftest` proves the 1-vs-N assertion load-bearing. Backs the placement caution in `write-a-refuter-profile.md` / `tune-refuter-sensitivity.md` |

The `docs/howto/` proof scripts (`docs/howto/gate-examples/`) are runnable, self-verifying, and enforced by T53–T139; see [../docs/howto/howto-list.md](../docs/howto/howto-list.md). The agent-backend/framework guides (T64–T66, T72) are enforced Docker-free (harness `--check` + backend conformance + prose-integrity); their live proof is the reproducible **pinned Docker** harness in [`../tests/frameworks/`](../tests/frameworks/) — an on-demand tier that never gates the suite. The MCP server is enforced Docker-free by T67–T71 (JSON-RPC over stdio/HTTP with our own client, deterministic); its real-third-party-client proof — the official MCP Python SDK v2 driving `hb mcp-serve` — is `tests/mcp-interop.sh`, an on-demand tier behind the `[mcp-test]` extra (`mcp>=2`) that never gates the suite.

## Python suite — `py/tests/`

`conftest.py`: sets `STUCK_TICKS=999`, `HB_ROT_CHECK=0`, `HB_NO_GIT=1` before import; adds `src` to `sys.path`. Fixtures: `make_hb(tmp_path, dag, events=None)` (writes `.hb/` with `initialized` + events), `two_phase_dag()`.

| File | Module under test |
|---|---|
| `test_state.py` | projection, leases, review-gated completion |
| `test_resolver.py` | `resolve`/`ready_tasks` |
| `test_lint.py` | lint rules + `extract_paths` |
| `test_gate.py` | gate pass/fail/check, behavioral criteria |
| `test_tick.py` | Stage A reasons, lease, circuit breaker |
| `test_cli.py` | `hb` end-to-end (init→tick→gate→report→diagnose) |
| `test_exec.py` | driver: drive-to-done, attempt cap, strict, parallel worktree |
| `test_audit.py` | auditor rules vs fixtures |
| `test_review.py` | `hb audit --agent` via stub backend, prompt build |
| `test_hardening.py` | review-evidence: artifact required, substance, distinct actor, rot |
| `test_backends_frameworks.py` | framework adapters resolve + degrade (no network) |
| `test_smoke.py` | version, `--help`, protocol render |

Backend tests drive a stub via `HB_EXEC_CMD` (subprocess wire); framework/ollama adapters are validity + graceful-degrade only (no network).

## Parity

`tests/parity.sh`. Runs the same inputs through both implementations; exits non-zero on any divergence; skips cleanly without `python3`. Ratcheted as node-suite T43.

| Surface | Compared |
|---|---|
| audit | `[errors, warns, sorted rules]` on 5 fixtures |
| lint | sorted `errors` on `broken.json` + fixtures |
| protocol | sorted reason KEYS (action text is runtime-specific) |
| next (resolve) | `[type, id, gate, phase]` |
| ready | sorted task ids |
| report | `[done, total, pct]` (progress only) |
| diagnose | inferred blocker (first line) |
| state | `[completed_tasks, completed_phases, pending_reviews, build_stuck_count, current_phase]` × 4 scenarios |

Normalization: Python comparisons use `ensure_ascii=False` (node emits non-ASCII literally). State/next/ready/report/diagnose build a temp `.hb/`, copying the node tools and reprojecting, then compare against `hb <cmd> --dir`. Details and intentional divergences: [parity-notes.md](../planning/parity-notes.md).

**Generative oracle — `tests/parity-fuzz.sh` (ratcheted as T75).** Where `parity.sh` compares hand-picked fixtures, the fuzzer feeds *seeded, generated* cases (`tests/gen-parity-case.py`) through the same shared surfaces and asserts node ≡ python across many inputs — two implementations of one spec are each other's oracle, so any disagreement is a real bug. The generator is seed-only (deterministic, reproducible); `--selftest` proves teeth by requiring a clean pass *and* a caught injected divergence in one run. It caught a real `report` rounding divergence (`5/8`: node `Math.round`=63 vs Python `int()`=62) the fixtures missed — since fixed via round-half-up in `report.py`.

## Live — real local model

Non-ratcheted; skip when the Ollama server is unreachable. `tests/real-backend.sh <backend> [model]` drives a project where a model writes `greeting.js` and a node gate runs it. `py/real-backend.py <backend> [model]` uses a Python gate (fully node/bash-free). `agno`/`crewai` default to `HB_EXEC_PROVIDER=ollama` (no API key); point `HB_EXEC_CMD` at a venv python when the framework lives in a virtualenv.

## Fixtures

| Path | Purpose |
|---|---|
| `tests/fixtures/audit/{hollow,existence,nondeterministic,good,side-effect}.json` | auditor + parity |
| `tests/fixtures/parity/broken.json` | lint-error parity |

## Invariants

- Node suite, Python suite, and parity stay green on every change; a new shared surface adds a parity case.
- New behavior is gated by a spec-first test in the owning suite; cross-runtime behavior adds a parity comparison.
- Determinism globals (`STUCK_TICKS`, `HB_NO_GIT`, `HB_ROT_CHECK`) are opt-out per test, never removed wholesale.
