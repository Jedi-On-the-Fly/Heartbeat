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
| **Refuter profile resolution** | `refuter_profiles.js resolve()` | `heartbeat.refuter_profiles.resolve()` | same name + `.hb/refuters/` → same normalized `{persona, questions[], model, provider, verdict}`; same precedence (explicit > env > project-file > built-in); unknown explicit name errors on both (T145) |
| **Refuter discovery** | `hb.js refuters` | `heartbeat.cli refuters` | same `.hb/refuters/` → identical sorted profile-name listing (T146 proof + `parity.sh refuters:list`) |
| **Refuter skill-format parsing** | `refuter_profiles.js parseSkill` / resolve | `heartbeat.refuter_profiles.parse_skill` / resolve | same `<name>/SKILL.md` (folder) or `<name>.md` (lite) → same normalized dict as the `.json` form; a SHARED minimal no-YAML line-parser (first-`:` split, trim+dequote, case-insensitive keys/`## Checklist`, `-`/`*` bullets, BOM/CRLF-tolerant) so the enumerated frontmatter divergence traps agree node ≡ python and a `panel:` value is validated identically (strict digits, and rejected above MAX_SAFE_INTEGER so the accepted range is where node `parseInt` == python `int`); a same-name cross-format collision errors on both; `hb refuters` lists folder+lite+json identically (T150 + `parity.sh skill-format`) |
| **Refute-prompt compose** | `refuter_profiles.js composePrompt` / `hb.js refute-prompt` | `heartbeat.refuter_profiles.compose_prompt` / `heartbeat.cli refute-prompt` | same gate + profile → byte-identical composed prompt (no-profile ⇒ today's prompt; else persona + BASE review_questions + appended profile questions + review.prompt); unknown profile errors on both (T147 + `parity.sh refute-prompt:composed`) |
| **Refute-prompt --json** (the interactive model binding) | `hb.js refute-prompt <gate> --json` | `heartbeat.cli refute-prompt <gate> --json` | same project → same `{prompt, model, provider, panel, refute_if}` with `prompt` byte-identical to the text compose (one compose) and all fields null when no profile — never fabricated (T163 + `parity.sh refute-prompt:json`) |
| **Review-event model field** (provenance) | `hb.js review --model` / `hb-exec.js` auto-stamp | `review_policy.accept_review(model=…)` / `executor.py` auto-stamp / MCP `review.model` | the review-event model field: review_passed/review_failed carry `model` (null when unknown, never fabricated); refuter-impact breaks down caught/cleared per model with null bucketed under `(none)` — one mirrored convention, pinned on a mixed fixture (T164 + `parity.sh refuter-impact`) |
| **Refuter impact** | `hb-report.js refuterImpact` | `heartbeat.report.refuter_impact` | same events + dag → same canonical summary (per-gate catches/clears + `review.profile` lens + findings) so `hb report` reads identically both runtimes (T152 + `parity.sh refuter-impact`) |
| **Panel aggregation** | `refuter_profiles.js aggregateVerdict` | `heartbeat.refuter_profiles.aggregate_verdict` | same verdict list + rule → same boolean (majority >N/2, any ≥1, all unanimous); the executor panel loop + fail-closed mirror across `hb-exec.js` ≡ `executor.py` (T148 + `parity.sh panel-aggregate`). A panel pass carries only real per-panelist findings (empty ones contribute no `[panelist …]` label), so an evidence-free panel can't clear the substance floor — same guard both runtimes |

**Refuter library is a SEED model (deliberate, for parity + portability).** The shipped library lives
at `plugin/templates/refuters/`; `bootstrap.sh` seeds it into a project's `.hb/refuters/` (no-clobber,
like `templates/executors/`), and BOTH runtimes resolve/discover from `.hb/refuters/` ONLY — a
one-tier search path. We deliberately did NOT add a runtime "shipped" tier located relative to each
runtime's module: that path differs node (plugin tree) vs python (installed package), so it would
diverge resolution and break the T145 parity oracle (an unknown name could resolve on node but error
on python). Seeding keeps the shipped set identical for both (they read the same project dir) and
means a project needs no access to the plugin/package at runtime. "Project shadows shipped" is
realized by no-clobber seeding (a project's own refuter of the same name is never overwritten).
Seeding is `bootstrap.sh`'s job; python `hb init` (`scaffold.py`) does NOT seed the library — exactly
as it does not seed `templates/executors/` — so `hb refuters` on a python-only-init'd project lists
nothing until bootstrapped. The parity contract is scoped to "same `.hb/refuters/` → same listing",
which holds; and the built-in `default` still resolves, so refutation never fails open.

Fixtures for the auditor live in `tests/fixtures/audit/` and are consumed by BOTH
suites (node T42, py test_audit.py).

**The parity test `tests/parity.sh`** (ratcheted as node-suite T43) now has **full
coverage** of the shared surfaces — node ≡ python on:
- **audit** findings (7 fixtures), **lint** errors (`tests/fixtures/parity/broken.json` + fixtures),
- **protocol** — the reason KEYS (not the action text, see below),
- **resolve** (`hb next`), **ready** (the runnable set), **report** (progress numbers),
- **diagnose** (the inferred blocker's first line),
- **state projection** (fresh / p0-gated / review-owed / two-fails),
- **anchors** — the manifest (path set + sha256) and `hb changed`, git and no-git (`anchors:*`),
- **plan-time constraints** — lint errors and the `unconstrained_review` warning (`constraints:lint/audit`),
- **the constraint author** — prompt bytes, `--json`, and the `--record` verdict sequence (`constraints:author:*`),
- **the constrained refute prompt** — constrained / free / `--json`, and `free_review` coercion from JSON and
  SKILL-format profiles on unicode-whitespace edges (`refute-prompt:constrained*`, `:free`, `:free_review:*`,
  `:skill-free_review:*`),
- **the answer parser** — `checkAnswers` ≡ `check_answers` messages and counts (`review:answers`).

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
- **git-snapshot on review acceptance is a cross-runtime pair.** node's inline snapshot in `hb.js review`
  ≡ python's `gate._git_snapshot` (via `review_policy.accept_review`): accepting a review-gated phase must
  `git add -A` + commit + force-tag the gate id, in both runtimes, so the tag only ever certifies a
  reviewed-good state. This logic cannot be code-shared across bash and Python, so it is held by a behavioral
  parity proof: **T141** (`git-snapshot-parity.sh` drives `hb review GATE_P0 pass` in each runtime and asserts
  both produced the commit+tag; a missing tag is RED).

## Review acceptance is a shared behavioral surface (must match)

Both runtimes decide a review-gated phase the same way, and a **degraded refuter never fails open**:
a refute result with **no boolean `refuted`** (a sentinel — `{"error": …}` from a py backend, or
`{"error": …}` from a bash backend when its CLI is absent) routes to **review_error**, never a pass
(`executor.py` ~329, `hb-exec.js` ~352). A genuine "could not refute" requires `refuted:false` **plus
substantive findings ≥40 chars** (the reviewer's actual text) → review pass; `refuted:true` →
review_failed. The model-text verdict is the reply's **final REFUTED/CLEAR token**, not a grep-anywhere
(the prompt itself contains "REFUTED"). Proof: `gate-examples/refute-integrity.sh` (T119), both runtimes.

## Constraint-first review is a shared surface (1.32.0)

Both runtimes implement the same pipeline and the same refusals, byte-for-byte where text is involved:
anchors (`hb.js` anchor section ≡ `anchors.py`), plan-time constraint validation (`constraintErrors` ≡
`lint.constraint_errors`), the author (`composeAuthorPrompt` ≡ `constraints.compose_author_prompt`, record
≡ `constraints.record` — grounded subjects (`groundingErrors` ≡ `grounding_errors`, `subjectPath` ≡
`_subject_path`, parity case `constraints:subject-path`, T177), write-once per review cycle, the cycle starting after the last review verdict,
check-then-write under the write lock), the constrained refute prompt (`composePrompt` ≡ `compose_prompt`),
the answer enforcement (`hb.js review` ≡ `review_policy.accept_review`) and the unattended pipeline
(`constrainedReview` ≡ `executor._constrained_review`). Proofs: T166–T172.

Where the two languages' primitives disagree, ONE explicit rule is used on both sides (each was a
refuter catch): **whitespace** — "blank", the `free_review` coercion and the SKILL-format parser use
ASCII whitespace only (`" \t\n\r\f\v"`; JS `trim()` and python `strip()` disagree on `\ufeff`,
`\x1c-\x1f`, `\x85`); **a review value** must be a non-empty object (JS truthiness and python `bool()`
disagree on `{}`/`[]`); **strict JSON** for `--record` (valid UTF-8 only, a BOM refused, no
NaN/Infinity); **paths and constraint text with control characters** are shown JSON-quoted
(`safePath` ≡ `safe_path`); **Unicode normalisation** is never delegated to the platform (node ICU and python unicodedata ship different Unicode versions — the answer parser folds explicitly and refuses styled-letter blocks by fixed ranges); **sort order** of paths is UTF-16 code units (python sorts with a
`utf-16-be` key). Known, accepted differences on INVALID input only: a lone surrogate in a gate-time
claim prints in node and raises in python; a lint-invalid `null` claim prints `null` vs `None`;
U+2028/U+2029/U+0085 are not quoted by `safePath` (identically in both).

## Write-lock scope (both runtimes)

The write-lock (`withWlock` / `with_wlock`, a `.wlock` mkdir) guards exactly one thing in both
runtimes: the **state.json read-modify-write** — `mutate` = `append_event` → `reproject` → atomic
write. Two concurrent `mutate`s must serialize there or one clobbers the other's projection; T139
(`wlock-tested.sh`) proves the lock actually does this (gut it → a lost update → RED), both runtimes.

What is deliberately **outside** the lock: the append-only informational events `tick.sh` writes via a
raw `echo "{…}" >> events.jsonl` (`wake`, `lease_expired`, `review_wake`, `log_event` — tick.sh
lines 72/181/338/388). These are **lock-free by design and it is safe**: a POSIX **O_APPEND** write of
a short line (< `PIPE_BUF`, 4096) is atomic, so concurrent appends never tear or lose a line; and
because `state.json` is a **full re-fold of events.jsonl** (`reproject`), it stays eventually-consistent
without the lock — a `tick.sh` append is picked up by the next `mutate`/`rebuild`. So the docs do **not**
claim "all writes are locked"; the lock scope is precisely the state.json RMW. Proven by
`docs/howto/gate-examples/tick-append-safe.sh` (60 concurrent appends stay valid + all present; real
concurrent `tick.sh` don't corrupt the log; a `--selftest` non-atomic read-concat-write *does* lose
updates, so the check has teeth), wired as node-suite T140.

## Intentional divergences (not on the byte-equal surface)

- **The tick notifier is node-only.** `tick.sh` runs `HB_NOTIFY_CMD` once per blockage on `build_stuck`, `gate_blocked`, `deadlock`, `unsanctioned_drift`, `gate_rot`, `review_stuck`, `replan_pending` and `all_done`; the python `tick.py` has no notifier. The wake reasons and the once-flags (`.replan-alerted` included) are shared; only the side-channel ping differs.

- **Pre-push gate guard: behavioral parity, runtime-specific body; rot pre-commit is node-only.** Both
  bootstraps now install a **blocking `pre-push` hook** (re-verify every gate, block the push on any
  regression) — behavioral parity (T118): the body differs by runtime (node calls `bash .hb/gate.sh
  --all`, python calls `hb gate --all`), and the seed outcome differs (node's template `GATE_P1` fails a
  fresh `--all`, python's `true` placeholder passes), so the proof asserts *the hook blocks iff gate
  re-verify fails*, not byte-equality. The **rot `pre-commit`** hook (`bootstrap.sh`) remains **node-only**
  — a pre-existing divergence, out of scope for the pre-push work.
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

- **The domain adapters ARE a parity surface — node ≡ python.** Both the code adapter
  (`plugin/adapters/code/` — `deplint` + `codegraph-map` + `codegraph-context`; node `*.js` and
  `py/src/heartbeat/adapters/code/*.py`) and the docs adapter (`plugin/adapters/docs/` — `docs-map` +
  `docs-context`; `py/src/heartbeat/adapters/docs/*.py`) ship in **both runtimes** and are cross-checked:
  **byte-identical** for the deterministic outputs (deplint findings+messages incl. the em-dash;
  context renderers — the Python side matches JS `.trim()` exactly via `js_trim`) and **set-equal** for
  the maps (edge/row order can differ). This makes the capability native to the Python/framework path —
  a `context_cmd='python3 -m heartbeat.adapters.docs.docs_context …'` works with **zero Node**
  (proof `docs/howto/gate-examples/adapters-nodefree.sh`). Enforced by **T94** (`deplint-parity.sh`,
  `codegraph-map-parity.sh`, `codegraph-context-parity.sh`) and **T95** (`docs-map-parity.sh`,
  `docs-context-parity.sh`), plus `py/tests/test_adapters_{code,docs}.py`. Boundary unchanged: not
  scaffolded into any `.hb/`, imports nothing from core; the live CodeGraph DB read stays harness-first
  (node uses the sqlite3 CLI, Python the stdlib `sqlite3` module — an intentional impl divergence, not
  an output divergence). The original node-suite proofs (T87/T88, T90/T91) still hold.

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
  mentioning codegraph/deplint); the code-context provider that plugs into it is the parity-surface
  adapter above (node ≡ python). The pre-existing node-only divergence in the *rest* of the assembled context (node appends a
  `git log` block python does not) is why parity compares the injected block, not the whole context.

Extend it when a new shared surface lands.

## Auditor ruleset (identical regexes in both)

Classify each gate criterion `cmd`:
- **vacuous** — trivially true. An EMPTY or non-string cmd first (the runner evals `''` →
  exit 0, so it must never count as the behavioral criterion that saves a gate from
  `hollow_gate`; a non-string cmd's shape is a lint ERROR — the criteria-shape rule: every
  entry an object with a string cmd, identical bytes both runtimes, parity case
  `hostile-criteria:lint` — and classifies as nothing here), then the regex
  `^\s*(true|:|exit 0|echo\b|test 1 = 1|\[ 1 = 1 \])\s*;?\s*$`
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
- `side_effecting` (**warn**) — a criterion writes/creates files (it could fabricate its own evidence).
- `unconstrained_review` (**warn**) — a review gate without plan-time `review.constraints`.
- `control_char` (**error**) — a criterion cmd/desc carries a `\x1e`/`\x1f` byte.
- `speculative_tail` (**warn**) — ≥ 2 trailing live phases unverified behind a verified head (see the horizon contract below).

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

Node ≡ Python on all five fixtures — same `errors`, `warns`, and sorted rule set.
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

## Intentional divergence: dag-writer number fidelity (regate wave, G3 refuter catch)

Every node CLI path that rewrites `dag.json` (`regate`, `park`/`unpark`, any future dag
editor) serializes through `JSON.stringify`, so JS number semantics apply to the WHOLE
dag: an integer beyond 2^53 loses precision (`12345678901234567890` →
`12345678901234567000`), `-0.0` becomes `0`, and `1.0` becomes `1`. The python writer
(`json.dumps`) preserves ints exactly and keeps the float distinction. This is a
pre-existing, dag-wide property of the node runtime — the regate `prev_criteria`
snapshot adds no loss of its own (snapshot and live criteria stay deep-equal relative to
each other, both passing through the same writer). Contract: dag values that must
round-trip bit-faithfully across BOTH runtimes stay within ASCII strings, booleans,
and integers |n| < 2^53 (every shipped field — ids, descs, cmds, timeout_s — does).
A dag that needs exotic numbers is outside the parity contract; lint does not police
this (numbers beyond timeout_s are not part of any shipped schema).

## Regate (the gate-revision surface)

Shared behavior, runtime-specific grammar (the park precedent): node declares with trailing
words (`hb regate <id> <reason…>`), python with `--reason`; the rearm grammar is identical
(`--rearm --artifact <f> [--model m]`). The refusal SIGNAL is equivalent, not byte-identical:
`gate.sh` exits **3** (reserved — 1 blocked, 2 usage) where python's `run_gate` returns the
`regate_pending` status, which its CLI maps to exit 3. Everything behavioral is pinned in
`tests/parity.sh` (`regate:lint-malformed` with a non-empty-error guard, `regate:declare-cross`
— a declare by one runtime honored by the other: marker, exit 3, no events, the identical
`regate_pending_waiting` tick sleep — and `regate:rearm-cross` — acceptance, same-actor and
stale refusals, the restarted review cycle, doctor's altered-evidence line). Shared helpers are
twins by name: `regateBlocks`/`regate_blocks` (strict fail-closed predicate — only a well-formed
`pending:false` clears; the runtimes' truthiness rules disagree on `[]`/`{}`, a refuter catch),
`staleRearm`/`stale_rearm` (fresh-pass rule over PROVENANCED passes), `unansweredRegate`/
`unanswered_regate` (the log outranks a hand-edited marker), `substantiveLen`/`substantive_len`
(artifact thin checks: ONE explicit ASCII whitespace set and CODE-POINT counting — JS `trim()`
vs `str.strip()` and UTF-16 units vs code points both diverged at the boundary, refuter
catches), and the single cycle-start (`reviewCycle.start` ≡ `constraints._cycle_start`, the
later of the last review verdict and the last `gate_rearmed`).

## Detach (the dependency-claim surface)

Shared behavior, runtime-specific grammar (the park/regate precedent): node declares with trailing
words, python with `--reason`; `reattach` is identical. Parity cases: `detach:cross` (a detach by
one runtime honored by the other — fields, the resolver unlock, the detach-anchor change base, a
cross-runtime reattach round-trip), `detach:lint-malformed` (non-empty identical errors on the
partial-fields shape), `detach:lint-reserved` (the reserved `_start`/`_detach_*` gate names on a
regex-hostile fixture: a gate named `"_start\n"` once split the runtimes because `re.match`'s `$`
matches before a trailing newline and JS's `$` does not — both checks are now exact-equality +
prefix, no regex), and the changed-base assertions inside `detach:cross`. The changed-base rule:
a detached phase's `hb changed` base is `gate_entry || the stamped _detach_<PHASE> anchor ||
_start` — the anchor is rewritten per declare and a stamp mismatch reads as missing (fail-closed
against a late-landing stale hash). The warning twins (`detachWarn` ≡ `_detach_warn`) are
per-channel over the event log; fuzzed cross-runtime during review (400 seeded cases, no
divergence).

## The replan contract (the editability boundary + the drift tripwire)

Append-continuation is the sanctioned way a plan grows: new phases with fresh ids (both lints now
error on a duplicate phase id, same bar as tasks), the first new phase's `gate_entry` = the last
completed phase's `gate_exit`; the append leaves every completed phase's projection untouched, and
`rebuild` is deterministic MODULO the top-level `last_updated` stamp (hb.js / state.py write it at
projection time — the one intentional nondeterminism in the projection bytes).

The editability boundary: the UNSTARTED surface is freely editable — the plan below the knowledge
horizon is a hypothesis, so reshaping or dropping a never-started phase (its gate included) is
quiet by design. The ACCEPTED surface changes only through its own rigor — regate (criteria) and
detach (dependency claims). The drift tripwire makes the unsanctioned path LOUD on both runtimes:
every real gate pass pins its criteria on the `gate_passed` event (`criteria: [{id, cmd, exit}]`);
`driftedGates` (hb.js) ≡ `state.drifted_gates` walks each gate's criteria-pinned pass history plus
the current dag criteria as the final element, comparing the ORDERED `(id, cmd)` pairs byte-exact.
An adjacent difference is drift unless a `gate_regated` for that gate lies between the two points
(a declared window — the regate machinery already fails that gate closed), or a COMPLETED regate
cycle (`gate_regated` → `gate_rearmed` → fresh criteria-pinned pass, the whole cycle after the
pair's later point) absolves it — the cure; the unsanctioned window stays in the log. Drift is a
doctor PROBLEM (exit 1) with twin-identical bytes, the sweeps (`gate.sh --all` ≡ `hb gate --all`)
EXCLUDE the drifted gate from re-evaluation and count it FAILING annotated (parked silences
neither drift nor a pending regate — the T179.4 flip), a removed ever-pinned gate surfaces via the
log walk, and the tick wakes the human-needed `criteria_drift` reason (identical key, runtime-
specific action text) every tick until cured.

HONEST LIMITS, recorded: `desc` and `timeout_s` are not pinned and never compared (reword a
description or adjust a budget freely — only `(id, cmd)` is evidence); bare/import passes (no
criteria field) never pin and never seed the walk; and the trust model is PROCEDURAL — `HB_ACTOR`
strings are self-declared identity, one human can play declarer and rearmer, and a forged or
truncated event log is outside the tripwire's reach (the log is trusted input, the same trust the
whole event-sourcing design already assumes). Parity case: `drift:cross` (a runtime-neutral
hand-edit of a completed gate's criteria is detected identically by both doctors — exit 1,
byte-identical problem line) with a non-vacuity floor (the clean twin fixture must be quiet on
both). Proof: `tests/replan.sh` (T184) + its `--selftest` teeth.

## The horizon contract (the knowledge horizon made machine-visible)

The marker is `"horizon": true` on a phase — a strict boolean (`hb-lint` ≡ `lint.py` error
`[<pid>] horizon must be true or false (the knowledge-horizon marker)`, byte-identical). It has a
runtime effect ONLY on the LAST LIVE (non-parked) phase; anywhere else it is inert, and its position
is never linted (a flag left behind by an append is historical). When every live phase is complete
and the last one is flagged and not in the projected `horizon_closed`, both resolvers return
`{"type":"replan_pending","phase":<id>}` (identical keys) instead of `all_done`; an EMPTY live list
(every phase parked) keeps today's `all_done`, never a throw. Both ticks wake `replan_pending` ONCE
per horizon phase — the `.replan-alerted` flag stores the phase id, so a stale flag never silences a
newer horizon — then sleep `replan_waiting`; the flag clears on the task and `all_done` branches and
no event is appended on the wake. Both exec drivers stop with `HB-EXEC STOP: replan_pending` (exit
nonzero) on every run whose tick reaches the open horizon — the wake run and every later
`replan_waiting` run alike. A higher-priority tick reason (criteria drift, gate rot, a blocked gate)
keeps its own handling ahead of the horizon, exactly as it does ahead of task dispatch.

The projection (`project` ≡ `state.project`) folds `horizon_closed` events into an insertion-ordered
set that `initialized` resets, and projects it SPARSELY — the `horizon_closed` key is ABSENT on any
log without a close, so every existing projection stays byte-identical.

`hb horizon close --reason <why>` (both CLIs, under the write lock) is a VERDICT: it appends
`{"event":"horizon_closed","phase","reason"}` (actor via the usual attribution) and reprojects, or
refuses with a nonzero exit and NO event when the reason is missing/empty, the live list is empty,
the last live phase is unflagged, any live phase is incomplete, the phase is already in the
PROJECTED `horizon_closed` (the resolver's own source), or any live gate's regate cycle is open —
pending (`regateBlocks`), unanswered in the log (`unansweredRegate`), or rearmed without a fresh
criteria-pinned pass (`staleRearm`). The close is phase-scoped: an appended, flagged, completed
horizon wakes again despite the older close. Refusal message text is runtime-flavored (like every
CLI verb's); exit status and the no-event guarantee are the shared contract. Argument style is
runtime-flavored too (the park/regate/detach precedent): node takes the reason as the trailing
words after `--reason`, python takes one `--reason <string>` argument. The once-only wake is
consumed by the first tick at a reached horizon even while a revision is open on a live gate (the
close is refused until the cycle completes; the drivers keep stopping on every run).

`speculative_tail` (`hb-audit.js` ≡ `audit.py`, identical message bytes): over live phases in plan
order, a phase is UNVERIFIED when it has no `gate_exit` (with or without tasks — a zero-task
placeholder is the purest speculative shape), its gate has no criteria, or none of its criteria is
behavioral. Hostile shapes outside the dag schema — a non-object `gates` map or gate value, a
non-array `criteria`, a non-string (or empty) `gate_exit` — read as EMPTY in every audit rule on
both runtimes: no gate, no criteria (never an audit crash, never an audit divergence; full finding
objects agree). This is an audit guarantee only — the lints do not yet reject every such shape. When the maximal trailing run of unverified phases is ≥ 2 AND at least one earlier live
phase is verified, ONE warn finding names the tail ids, the cut phase and the cure (end the plan
there with the horizon flag; `docs/howto/plan-to-the-horizon.md`). Parked phases are excluded. It
stays a WARN: its job is the diagnosis (where to cut), not a second verdict — a tail member carries
its own finding when its shape has one (unguarded warns, ungated/hollow error), and an empty
placeholder carries none, which this rule names.

HONEST LIMITS, recorded: the marker is plan surface, desc-class — the drift tripwire pins only a
completed gate's `(id, cmd)` criteria, so deleting the flag or parking the flagged phase silences the
wake with doctor quiet (pinned as behavior, `l1`/`l2`). The recorded way to end a horizon is the
close verb. A hand-appended `horizon_closed` event is accepted by the projection — the same
procedural trust the whole event log carries (`HB_ACTOR` is self-declared identity); the verb's
refusals bind the verb, not the pen. Parity cases: `horizon:resolve`, `horizon:project`
(multi-close insertion order + the absent key), `horizon:lint`, `horizon:audit`, each with a
non-vacuity floor, implemented inline. Proof: `tests/horizon.sh` (T185) + its `--selftest` teeth.
