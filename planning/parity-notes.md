# Parity notes — node vs. Python (running log)

Purpose: capture anything that must stay identical between the node+bash plugin and the
`py/` port, so a future **parity test** (run the same input through both, compare output)
is easy to build. Update as we add cross-implementation surface.

## Shared surfaces (must agree)

| Surface | node | python | Compare by |
|---|---|---|---|
| Projector | `hb.js project()` | `heartbeat.state.project()` | same events+dag → same `completed_tasks/phases`, `pending_reviews`, `build_stuck_count`, `current_phase` |
| Resolver | `hb-next-task.js resolve/readyTasks` | `heartbeat.resolver` | same state → same next action / ready set |
| Lint | `hb-lint.js lint()` | `heartbeat.lint.lint()` | same dag → same errors (warnings may differ in wording) |
| Protocol | `hb.js PROTOCOL` | `heartbeat.protocol.PROTOCOL` | same reason KEYS (action text is runtime-specific by design — see below) |
| **Auditor** | `hb-audit.js audit()` | `heartbeat.audit.audit()` | same dag → same findings (rule + severity per gate) |

Fixtures for the auditor live in `planning/audit-fixtures/` and are consumed by BOTH
suites (node T42, py test_audit.py).

**The parity test `tests/parity.sh`** (ratcheted as node-suite T43) now has **full
coverage** of the shared surfaces — node ≡ python on:
- **audit** findings (4 fixtures), **lint** errors (`parity-fixtures/broken.json` + fixtures),
- **protocol** — the reason KEYS (not the action text, see below),
- **resolve** (`hb next`), **ready** (the runnable set), **report** (progress numbers),
- **diagnose** (the inferred blocker's first line),
- **state projection** (fresh / p0-gated / review-owed / two-fails).

**Generative oracle — `tests/parity-fuzz.sh` (T75).** Beyond the fixed fixtures, a seeded
deterministic generator (`tests/gen-parity-case.py`) produces varied well-formed cases and
asserts node ≡ python on every shared surface — two implementations of one spec are each
other's oracle. It caught a real divergence the fixtures missed: **progress percent rounding**
— node used `Math.round(100*done/total)` (half up), Python used `int(...)` (truncate), so
`5/8` gave 63 vs 62. Fixed by making `report.py` round half up (`int(x + 0.5)`, x ≥ 0). Keep
the two `pct`/`percent` computations identical.

Two gotchas it encodes:
1. Python's `json.dumps` escapes non-ASCII (the `—` in a lint message) → compare with
   `ensure_ascii=False`.
2. **Protocol action text is runtime-specific by design** — node cites `node .hb/hb.js` /
   `bash .hb/gate.sh`; python cites the `hb` console. So parity compares the reason *keys*,
   not the action strings. (If you ever want the reasons themselves to diverge, that's a
   real bug; the wording differing is not.)

## Behavioral parity (not byte-equal, but must match)

- **A relative `--dir` resolves to an ABSOLUTE `PROJECT_DIR`/`HB_DIR`.** The gate runs with
  `cwd = PROJECT_DIR`, so if those vars were relative a criterion like `grep "$PROJECT_DIR/out.txt"`
  would double-nest to `<proj>/<proj>/out.txt` and block. Node's `gate.sh` has always absolutized
  (`HB_DIR="$(cd "$(dirname "$0")" && pwd)"`); the Python runtime now matches (`gate._project_dir`
  and `_env` use `os.path.abspath`, and the executor's worker `cwd` is absolute). Enforced by
  node-suite **T80** (`docs/howto/gate-examples/relative-dir.sh` drives both runtimes with a
  relative dir) + `py/tests/test_gate.py::test_relative_dir_gate`.
- **Tick decision (`data.reason`).** Both ticks must emit the same wake reason for the same state —
  the projector/resolver are byte-equal but the *tick* wraps them, so it's a separate surface.
  This caught a real bug: `tick.py` lacked the `review_stuck` escalation that `tick.sh` has (a
  never-resolving review stalled forever in Python instead of escalating). Now mirrored. Enforced
  by **T82** (`tick-parity.sh` compares node vs python `data.reason` across next_task / gate_pending
  / all_done / the review-stall frontier) + `py/tests/test_tick.py::test_review_stuck_escalation`.
- **Gate-runner verdict.** `gate.sh` and `hb gate` must reach the same pass/block on the same
  criteria (pass, fail, the zero-criteria hollow floor, timeout). Enforced by **T83**
  (`gate-parity.sh`, compared by exit code).
- **Doctor / rot detection.** Both must agree on whether a completed phase's gate is still
  reproducible (the tick keys off this). Enforced by **T84** (`doctor-parity.sh`).
- **Backends registry.** Both runtimes must offer the same canonical backend set. Enforced by
  **T85** (`registry-parity.sh`), modulo the python-only `claude` alias (below).

## Intentional divergences (not on the byte-equal surface)

- **Backend name aliases.** The Python `_KNOWN` registry accepts `claude` as an alias for
  `claude-code` (both resolve to the same adapter); the node `defaultCmd` has only `claude-code`
  (bare `claude` falls through to a custom command). T85 normalizes this alias before comparing.
- **Scaffold default `.hb`.** `bootstrap.sh` copies `templates/dag.json`; `scaffold.py` writes its
  own inline `DEFAULT_DAG` — the first-run starter DAGs differ by design (both audit-appropriately).
- **`import` is node-only.** `hb.js import` (legacy `state.json` → event-log migration) has no
  Python equivalent; the Python port was event-sourced from the start.
- **Drift detection (`unsanctioned_drift`) is node-only.** `tick.sh` supports optional
  architecture-drift detection (SHA of `WATCH_PATHS`, `--freeze` to re-baseline); it is **off by
  default** (`WATCH_PATHS=""`), so it never fires in default operation. `tick.py` does not implement
  it. Likewise `no_next_task_script` is a node-internal fallback. Both reasons stay in the shared
  `PROTOCOL` map (so protocol-key parity holds), but only node emits them — the tick-parity proof
  (T82) compares the reasons both runtimes DO emit (next_task / gate_pending / all_done /
  review_stuck / build_stuck).
- **`diagnose` recovery text.** Its *blocker* line is parity-checked, but the *recovery-command*
  text is runtime-specific (node cites `node .hb/hb.js` / `gate.sh`, python the `hb` console) —
  same reason `protocol` compares reason keys, not action text.

- **`hb exec config`** is a shared command (both runtimes print the resolved executor config and
  neither runs), but the JSON **key format differs by design**: the plugin emits camelCase
  (`attemptCap`, `heartbeatMs`) and the Python port snake_case (`attempt_cap`, `heartbeat_s`), and
  the resolved `cmd` differs (the plugin fills a backend default). So `exec config` is **not** on
  the byte-equal `parity.sh` surface; its *behavioral* parity ("config prints, does not run" in
  both) is enforced by the node suite's `T63` group instead. The executor generally is not a
  parity surface — backends and their config are runtime-local. The **cross-model refuter**
  config (`refute_backend`/`refute_cmd`/`refute_model`/`refute_provider` ↔ `HB_REFUTE_*`) is part
  of that shared config surface (both runtimes resolve it and print it via `exec config`, T73);
  the refute *dispatch* that uses it is runtime-local like the rest of the executor.

- **`hb mcp-serve`** (the MCP server) is **Python-delivered only** and is *not* mirrored in the
  node+bash plugin. Like `pip install`, it's a single host-neutral binary that **both** hosts
  consume (`codex mcp add … -- hb mcp-serve`; Claude Code's MCP config points at the same command),
  so there is no second implementation to keep byte-equal. Parity with the CLI is instead
  *automatic*: its tools call the same `heartbeat` library functions `hb <cmd>` calls, and its proof
  (`docs/howto/gate-examples/mcp-server.sh`) asserts each tool's answer equals the corresponding
  `hb` command. AGENTS rule 2 governs shared *logic*; the MCP server is a thin adapter over that
  shared logic, not a new shared surface that needs a mirror.

- **`hb bench`** (the agent benchmark harness) is likewise **Python-delivered only** analytical
  tooling — not mirrored in the plugin. It drives the existing (runtime-local) executor over the
  shared, backend-agnostic DAG; there's no new shared *logic* to keep byte-equal (its scorer reads
  the same event log the projection does). Proof: `docs/howto/gate-examples/agent-bench.sh`.

- **`hb reward`** and **`hb bench --baseline`** (verifiable-reward stream + model-regression) are
  the same case: **Python-delivered only** analytical tooling. `reward_records`/`regressions` are
  pure over the event log + scorecards (no new shared *logic* to mirror byte-for-byte). Proof:
  `docs/howto/gate-examples/reward-regression.sh` (node-suite T76).

- **The code adapter** (`plugin/adapters/code/` — `deplint` + `codegraph-map` + `codegraph-context`)
  is **node-only** and intentionally **not a parity surface**, like viz/bench/mcp-serve. It's a
  *domain adapter* over the general method (Seam 1: plan authoring; Seam 2: context assembly),
  delivered by the plugin but **not scaffolded into any `.hb/`** and importing nothing from core; the
  suites stay green without it (and without CodeGraph). There is no second implementation to keep
  byte-equal — the live CodeGraph DB read is harness-first; the pure dep-lint engine, row→codemap
  mapping, and context provider are gated hermetically (node-suite T87/T88). Proofs:
  `docs/howto/gate-examples/code-deplint.sh`, `code-map.sh`, `code-context.sh`.

- **The docs adapter** (`plugin/adapters/docs/` — `docs-map` + `docs-context`) is the SECOND domain
  provider and is likewise **node-only** and **not a parity surface**. It reuses the *unchanged*
  `deplint.js` and the generic context hook — only the provider is new — so it adds no shared logic to
  keep byte-equal. Gated hermetically (node-suite T90/T91: `docs-deplint.sh`, `docs-context.sh`); the
  live ollama demo (`tests/real-docs-context.sh`) is harness-first. Same boundary as code.

- **The executor context-injection hook IS a shared behavioral surface** (Seam 2). When a
  `context_cmd` is configured, both executors (`py/src/heartbeat/executor.py::assemble_context` and
  `plugin/templates/hb-exec.js::assembleContext`) run it per task and append its stdout to the task
  context, wrapped in the same `<<HB-CONTEXT>>` delimiter — so the **injected block is byte-identical
  node ≡ python**, including exit-code handling: both inject the captured stdout even when the
  command exits NONZERO (Python `subprocess.run` without `check`; node captures `e.stdout` from the
  `execSync` throw), degrading to nothing only when there is no output. Enforced by **T89**
  (`context-inject-parity.sh` drives both executors with a stub context_cmd + a stub backend and
  compares the injected block for BOTH an exit-0 and an emit-then-nonzero-exit command) +
  `py/tests/test_exec.py`. The hook is
  **domain-neutral** (the executor never inspects what the command emits — a boundary gate forbids it
  mentioning codegraph/deplint); the code-context provider that plugs into it is the node-only adapter
  above. The pre-existing node-only divergence in the *rest* of the assembled context (node appends a
  `git log` block python does not) is why parity compares the injected block, not the whole context.

Extend it when a new shared surface lands.

## Auditor ruleset (identical regexes in both)

Classify each gate criterion `cmd`:
- **vacuous** — trivially true. `^\s*(true|:|exit 0|echo\b|test 1 = 1|\[ 1 = 1 \])\s*;?\s*$`
- **existence** — existence-only check. `^\s*(test\s+-[efds]\b|\[\s+-[efds]\b|ls(\s|$))`
- **behavioral** — anything else (the good case).
Orthogonal flag:
- **nondeterministic** — network/time. `\bcurl\b|\bwget\b|\bnc\b|\bping\b|\bsleep\b|\$RANDOM\b|\bdate\b|https?://(?!localhost|127\.0\.0\.1)`

Findings (severity):
- `hollow_gate` (**error**) — a phase's gate has criteria but NONE are behavioral (all vacuous/existence). The phase passes without proving its work.
- `ungated` (**error**) — gate has zero criteria.
- `unguarded_phase` (**warn**) — a phase has tasks but no `gate_exit`.
- `vacuous` / `existence` (**info**) — per-criterion note (does not fail the DAG on its own if a sibling criterion is behavioral).
- `nondeterministic` (**warn**) — per-criterion flake risk.
- `gate_offphase` (**warn**) — the gate references files no task in that phase mentions (may not test this phase's work).

`audit` exits 1 if any **error**, else 0. A phase with one behavioral + one `test -f`
criterion is NOT hollow (one behavioral criterion is enough) — only its `test -f` gets an
info note.

## Expected findings on the fixtures

| fixture | error | notable findings |
|---|---|---|
| `hollow.json` | yes | `hollow_gate` (G0), `vacuous` (G0/c) |
| `existence.json` | yes | `hollow_gate` (G0), `existence` (G0/c) |
| `nondeterministic.json` | no | `nondeterministic` (G0/c) — behavioral but flaky |
| `good.json` | no | none (clean) |

## Parity result (DA3)

Node ≡ Python on all four fixtures — same `errors`, `warns`, and sorted rule set.
(Only cosmetic difference: `json.dumps` spacing; compare via normalized serialization.)
This is the working parity test; a future dedicated one should also diff `project()`,
`resolve()`, and `lint()` on shared fixtures.

## Dogfood findings on our own DAGs (DA3)

Ran `hb-audit` on our real DAGs — the auditor behaved correctly and found nothing
false-confident in the plans we actually run:

| DAG | result |
|---|---|
| `planning/hb-exec.dag.json` | clean ✓ |
| `planning/heartbeat-py.dag.json` | `GATE_PP5[pp5c2]` is `test -f pyproject.toml` (info) — but has a `pytest` sibling, so **not hollow**. Fine. |
| `planning/dag-auditor.dag.json` (this plan) | clean ✓ |
| `plugin/templates/dag.json` (default template) | two `test -f` info notes with behavioral siblings → not hollow. **Could be more exemplary** (it's the thing users copy) — left as-is to avoid churning the node suite; noted as a follow-up. |
| python scaffold default (`hb init`) | `hollow_gate` **error** on the `true` placeholder — **intended**: a fresh project has no real gate yet, and audit correctly says so. |

Takeaway: the auditor caught the one genuinely hollow gate we ship (the scaffold
placeholder, by design) and cleared every plan we actually executed. No changes required.
