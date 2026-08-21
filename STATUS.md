# STATUS — HeartBeat

**Version:** v1.27 (the research adapter completes its loop — an internet-sourced writeup earns acceptance the same way code does: source → stamp → ground → refute → write, over v1.26)
**Regression suite:** `bash tests/run-tests.sh` · **Parity:** `bash tests/parity.sh`

## v1.27 — the research adapter's full loop (source → stamp → ground → refute → write)

The research adapter graduates from a single grounding check to the **whole evidence lifecycle for
facts**: an internet-sourced writeup is accepted only when every claim is backed by a real, stored
source and survives an adversarial refuter — the same bar HeartBeat holds code to. The web **fetch stays
on-demand and non-gated** (it's non-deterministic by design); everything downstream of the stored
snapshot is deterministic and gates.

- **A grounding verifier (the gate).** `ground-check` verifies OFFLINE that every claim's verbatim
  excerpt is present in its stored source and the source still matches its recorded sha (**STALE**
  detection), catching hallucinated citations and fabricated quotes. Advisory; `--strict` blocks. Both
  runtimes (**T110/T111**).
- **Honest hashes — `stamp-evidence`.** Records each source's sha256 from the **stored bytes** into the
  evidence map (a one-time, at-store-time step), so an agent-supplied hash can't lie and a later edit
  surfaces as STALE. node ≡ python same map (**T113**).
- **Grounded context for the writer — `research-context`.** Renders **only** a given section's grounded
  claims (id + text + source url + verbatim excerpt) as the Seam-2 block fed to Stage B — no
  cross-section leak. node ≡ python byte-identical (**T112**).
- **The skill documents the full loop.** `research-grounding` now walks source → stamp → ground →
  refute (a distinct-actor review seeded by `hb-audit --questions`) → write, handing off to
  `docs-authoring` (ordering) and `gated-docs` (prose). Two gated how-tos ship
  (`source-and-ground-research.md`, `run-a-grounded-research-project.md`). Honest throughout: **it
  verifies grounding, not truth** — HeartBeat does not fetch or fact-check for you.

## v1.26 — the evidence lifecycle, made first-class

HeartBeat's differentiator, stated plainly (now the README lead): **a proof-driven development method —
work is accepted only when its claims are backed by executable evidence and survive an adversarial
attempt to refute them.** This release makes the *lifecycle* first-class rather than implicit.

- **A checkpoint only certifies a REVIEWED state.** A review-gated phase's commit+tag `GATE_x` is now
  created only at **review acceptance** (`hb review pass`), not at the deterministic pass — so the tag
  never marks an un-reviewed / later-refuted state, and a refute→fix cycle no longer churns the tag or
  doubles the checkpoint. `git reset --hard GATE_x` always restores a state that passed BOTH the gate
  and the review. Both runtimes (**T103**).
- **Falsification questions, generated from the gate's own claims.** `hb-audit --questions <gate>`
  (node) / `hb audit --questions` (python) derives, from each criterion's class, a targeted "how could
  this FALSELY pass?" question + a general phase question — seeding the adversarial review
  deterministically instead of relying on prompt craft. Node ≡ python (**T104**); referenced from the
  `review_pending` guidance.
- **Evidence provenance on every gate pass.** The `gate_passed` event records per-criterion
  `{id, cmd, exit}`, the git **commit** tested, and the **runtime** — and `hb evidence <gate>` reads it
  back (with the review artifact when present). The evidence is now auditable/reproducible, not implicit
  (**T105**).
- **Graph blind-spots surfaced.** `codegraph-coverage` reports each task's resolved-symbol count and
  lists the **GRAPH-BLIND** tasks (zero symbols — dynamic/framework bindings or not-yet-existing files
  the static graph can't model → read manually), so code context isn't trusted equally (**T106**). Both
  runtimes; in the code-aware-planning skill.

## v1.25 — domain adapters (the method, made domain-aware without leaving the method)

The method stays domain-agnostic; a **domain adapter** plugs in at two seams — plan authoring
(dep-lint a DAG's `requires` against a real dependency graph) and context assembly (feed Stage B
the slice a task needs) — over one small `codemap` contract (`docs/adapters.md`). Two adapters ship,
in **both runtimes**, so the capability is native to the Python/framework path, not just the node plugin.

- **Two shipped adapters, both seams.** **code** (a CodeGraph symbol graph) and **docs/research**
  (a markdown citation graph) each provide Seam 1 (`deplint`) + Seam 2 (a `context_cmd` provider).
  Proofs: `code-deplint.sh` / `code-map.sh` / `code-context.sh` (T87/T88) and `docs-deplint.sh` /
  `docs-map.sh` / `docs-context.sh` (T90/T91). Boundary is enforced: adapters live under
  `plugin/adapters/` (+ `py/src/heartbeat/adapters/`), are **not** scaffolded into any `.hb/`, and
  import nothing from core — the suites stay green without them.
- **Adapters are a PARITY SURFACE — node ≡ python.** Both adapters are ported to Python and
  cross-checked: **byte-equal** for the deterministic outputs (dep-lint findings incl. the em-dash;
  context renderers — Python matches JS `.trim()` exactly via `js_trim`) and **set-equal** for the
  maps (**T94**/**T95**). The capability runs with **zero Node** (**T96**, `adapters-nodefree.sh`
  drives a `python3 -m heartbeat.adapters…` `context_cmd` with node off `PATH`). One deliberate impl
  divergence (node shells to the `sqlite3` CLI, Python uses the stdlib module) — same output — is
  recorded in `planning/parity-notes.md`.
- **Frictionless + enforced.** Each adapter ships a skill (`code-aware-planning`, `docs-authoring`)
  so a user never touches the raw `node plugin/adapters/…` commands; **skill-integrity** (**T92**)
  fails the suite unless every adapter is declared by a skill that names real, **wired** proofs.
  Guide: `docs/howto/build-a-domain-adapter.md`.
- **Code adapter, beyond the two seams** (all node ≡ python): **discovery** — `codegraph-discover`
  gives the transitively-affected set from entry symbols (`dependents` = change impact) to scope a
  change before authoring the DAG (**T98**); **deplint-accept** auto-surfaces dep-lint at plan
  acceptance, resolving the codemap (explicit → `codemap.json` → `.codegraph` db-build → skip),
  advisory / `--strict` (**T100**); **exclude-hb** keeps CodeGraph off HeartBeat's own `.hb/` scaffold
  (**T102**); dep-lint no longer false-flags REDUNDANT for a task with no resolved symbols (**T101**);
  and `resolve_task_symbols` is ported to Python (parity gap closed).
- **MCP adapter tools.** The Python MCP server exposes the now-native adapters as tools — `deplint`,
  `code_context`, and `code_discover` — so a framework/MCP client gets the code-aware capability
  in-session, node-free (**T97**/**T99**, `mcp-adapters.sh` / `code-discover-mcp.sh` drive real
  `mcp-serve` and compare each tool result to the adapter).
- **Live viz dashboard.** `hb-viz.js --serve` runs a loopback-only HTTP server that re-reads
  `dag.json`+`state.json` fresh per request (no regenerate), refusing a non-loopback bind and
  validating `Origin` (DNS-rebinding) — alongside the point-in-time snapshot (**T86**,
  `viz-serve.sh`). Guide: `docs/howto/watch-a-run-live.md`.
- **Docs held to the code's bar.** Whole-`docs/` prose gating (**T93**) extends prose-integrity to
  every guide, and the `T55.2` executor test was de-flaked (deterministic, no timing race). Built the
  gated way throughout: plan/phase refutations caught real defects each phase (a cross-adapter context
  leak, a BOM/NEL `trim` divergence, a nonzero-exit `context_cmd` divergence, stale "node-only" adapter
  docs) before they shipped.

## v1.24 — cross-runtime parity hardening (and the bug it surfaced)

Auditing parity coverage across every feature — prompted by asking "where is the parity
cross-check?" — turned up a real liveness bug and four uncovered surfaces.

- **Python `review_stuck` fix (HIGH).** `tick.py` lacked node `tick.sh`'s `review_stuck`
  escalation, so a never-resolving adversarial review stalled **forever** in the Python runtime
  (a liveness violation) instead of escalating past `STUCK_TICKS`. Now mirrored (count `review_wake`
  since the last verdict; single-alert flag; `review_stalled` event). It hid because the tick's
  *decision* was never cross-checked — only the projector/resolver and the protocol reason *keys*.
- **Four new cross-runtime parity proofs**: the tick's `data.reason` (**T82** — next_task /
  gate_pending / all_done / review_stuck / build_stuck), the gate-runner verdict (**T83** —
  pass/fail/hollow-floor/timeout), doctor/rot detection (**T84**), and the backends registry
  (**T85**, python-only `claude` alias normalized). Each drives both runtimes.
- **Intentional divergences documented** so they're not future false-positives: node-only
  `unsanctioned_drift` (opt-in drift detection, off by default) + `no_next_task_script`, the `claude`
  alias, the scaffold default `.hb`, node-only `import`, and `diagnose` recovery-command text.
- Built + double-checked the gated way: plan/phase refutations caught a vacuous-pass hole, a
  grep-a-filename wiring check, an unbuildable registry assertion (the `claude` alias), and an
  incomplete tick mirror; a pre-commit sweep confirmed 0 consequence-bugs and 0 further missed gaps
  (all other tick reasons verified identical across runtimes).

## v1.23 — scheduled self-audit (corpus coherence + runtime parity)

The drift/overclaim audit we'd been running by hand, made a standing, schedulable capability —
the compounding step from v1.22's gated docs.

- **Deterministic self-audit** (`docs/howto/gate-examples/self-audit.sh`, **T81**) — one command
  checking three project-wide invariants: **prose-integrity** (every guide), **referenced-proof
  integrity** (every `gate-examples/*.sh` a guide names in its body exists AND is wired in the
  suite — the gap `prose-check` misses because those are code-fence paths, not markdown links, and
  exactly how a proof can vanish/go dormant), and **runtime parity** (`node ≡ python` via
  `tests/parity.sh`, failing on divergence). Count-pinned (no vacuous `0/0`); `--selftest` has teeth
  (catches a missing AND an unwired proof). Guide `docs/howto/run-a-scheduled-self-audit.md` with a
  cron/`/loop` schedule recipe that escalates on non-zero.
- **Adversarial tier (on-demand, non-gating)** — the distinct-actor refutation sweep for
  overclaims, documented as a capability probe (needs a model). Fittingly, the phase refutation
  caught an overclaim in the self-audit's *own* guide — an invalid cron the deterministic tier
  structurally can't parse — the exact defect class the adversarial tier exists to find.
- Built the gated way (plan-refuted: a vacuous-pass hole + a grep-a-filename wiring check, both
  tightened; phase-refuted: the cron). The parity cross-check was added after review flagged that a
  "self-audit" omitting node ≡ python isn't auditing the project's core contract.

## v1.22 — gated-docs skill + a fully-gated how-to library + a bug the method caught

Applying HeartBeat's "refute, don't confirm" to the documentation itself — a doc is a claim, so
gate it, wire it to re-verify, refute it, and bend the doc to the code.

- **`gated-docs` skill** (`plugin/skills/gated-docs/`) — the method as a plugin skill: pick
  mechanism-proof vs prose-check, write the proof spec-first (must be able to go red), wire it so
  the suite runs it, refute it; for a batch, orchestrate with `/heartbeat plan`. Enforced by **T78**.
- **Six Tier-1/Tier-2 operational how-tos** — run tasks in parallel (+worktree isolation), add
  HeartBeat to an existing repo, write dependencies that don't over-constrain, review an unsafe gate
  (each a runnable proof, **T77**), plus run fully locally and schedule unattended (prose, **T62**).
- **Whole-library prose gate (T79)** — `prose-check` now runs over *every* `docs/howto/*.md`
  (count-matched), closing the coverage gap where ~half the guides were ungated. Its placeholder
  rule was tightened to marker-based (a false positive on the word "TODO" in prose), with a
  regression-guard selftest.
- **Level-3 refutation sweep** of the existing library — 3 of 5 batches came back clean; it caught
  a **flagship-quickstart bug** (`heartbeat-in-5-minutes.md` didn't run as written — a relative
  `--dir` the proof never exercised) and two `review_stuck` misattributions, all fixed.
- **Relative-`--dir` fix (T80)** — the bug the sweep surfaced: the Python runtime resolved a
  relative `--dir` to a relative `PROJECT_DIR`/`HB_DIR`, so gate criteria and the git worktree
  double-nested (`<proj>/<proj>/…`) and blocked. `gate.py`/`executor.py` now absolutize (matching
  the node runtime, already correct). Behavioral parity in `parity-notes.md`; regression tests in
  `test_gate.py` + `test_exec.py`. Refutation caught two incomplete-fix holes (the `HB_DIR` twin and
  the worktree path) before it landed.

## v1.21 — parity differential-testing oracle + verifiable-reward / model-regression

Two more capabilities that cascade from HeartBeat's own primitives — two implementations of one
spec are each other's oracle, and the event log's gate verdicts are a deterministic label.
Python port + shared test harness; **plugin templates are unchanged** this release.

- **Parity as a differential-testing oracle** — `tests/parity-fuzz.sh` feeds *seeded, generated*
  cases (`tests/gen-parity-case.py`, deterministic xorshift32) through *both* runtimes on every
  shared surface and asserts node ≡ python — so any disagreement on any generated input is a real
  bug, not just the fixtures you thought of. `--selftest` binds the teeth: it must pass clean on the
  real runtime *and* catch an injected divergence on a mutant in one run. It immediately caught a
  **real latent parity bug the fixed fixtures missed** — `report` percent rounding (node
  `Math.round(100*done/total)` vs Python `int(done/total*100)`: `5/8` → 63 vs 62), fixed in
  `report.py` (match node's operand order + round half up). Enforced by **T75**; method in
  `docs/howto/keep-the-runtimes-in-parity.md`.
- **Verifiable-reward + model-regression** — `hb reward` extracts one labeled record per gate
  evaluation from the event log (`{gate, phase, passed, actor, ts}`); `passed` is the deterministic
  log verdict (never a self-report) and `phase` is derived from the dag. `hb bench --baseline <L>`
  adds a per-candidate regression verdict (fewer gates / fewer phases / more failures than the
  baseline). Both are pure functions over the log/scorecards — Python-delivered analytical tooling
  (like `hb bench`; python-only divergence recorded in `parity-notes.md`). Enforced by **T76**;
  guide `docs/howto/benchmark-agents.md`. Honest scope: the extraction/comparison is deterministic;
  a real model's run isn't → a signal, not a leaderboard.
- **Discipline note.** Built through the full plan→refute→build→refute loop; the distinct-actor
  refuters caught five real defects before commit (the latent rounding bug, a float op-order in the
  first fix, an LCG low-bit generator that barely varied, missing review-owed/gate-pending fuzz
  coverage, and a `bench --json` back-compat regression) — the method finding bugs in its own work.

## v1.20 — cross-model refuter + agent benchmark harness

Two capabilities that cascade from HeartBeat's own primitives — refute being a separate backend
method, and the DAG/gates being backend-agnostic and deterministic.

- **Cross-model refuter** — the adversarial `refute` can run on a *different* backend/model than
  the `execute` doer (`HB_REFUTE_BACKEND` / `HB_REFUTE_MODEL` / `HB_REFUTE_PROVIDER` /
  `HB_REFUTE_CMD`, or `executor.json refute_*`; each falls back to the doer's, so it's opt-in and
  backward-compatible). A model doesn't refute its own blind spots. The distinct-actor review
  guarantee is preserved and the refuter's identity is recorded in the review artifact
  (provenance). Both runtimes; `hb exec config` prints the settings. Enforced by **T73**; guide
  `docs/howto/cross-model-verification.md`.
- **Agent benchmark harness** — `hb bench --dir <p> --backend <spec>…` runs the *same* DAG under N
  backends on isolated copies and scores each behaviorally from the event log (gates are the
  rubric; completed phases / attempts / escalations are the metric). The scorer is a pure function
  over the log — never the backend's self-report. Python-delivered analytical tooling. Enforced by
  **T74**; guide `docs/howto/benchmark-agents.md`. Honest scope: the scorer is deterministic
  (suite-proven); real-model runs are non-deterministic → a capability probe, not a leaderboard.

## v1.19 — MCP server (drives, or is driven) + Codex/OpenCode backends

HeartBeat now works in both directions: it drives agents (new `codex`/`opencode` backends), and it
*is* an MCP server that agents drive. Three MCP-client hosts (Codex, Claude Code, OpenCode) on one
server.

- **MCP server (`hb mcp-serve`, Python port)** — a minimal, **stdlib-only** JSON-RPC server (no SDK)
  exposing the read (`tick`/`next`/`state`/`report`/`diagnose`/`doctor`/`lint`/`audit`) and act
  (`gate`/`start`/`done`/`fail`/`review`) tools. Act tools route through the log, so the
  mutate-only-through-the-log invariant holds. Enforced by **T67**.
- **Dual-stacks the 2026-07-28 spec** — the classic `initialize` handshake for today's hosts and
  the 2026 revision (via `server/discover` + per-request `_meta`; `resultType`/cacheable-list) for
  new ones; old responses stay byte-identical. Verified against the official MCP Python SDK v2
  client (`tests/mcp-interop.sh`, `[mcp-test]` extra). Enforced by **T70**.
- **Streamable-HTTP transport** (`--http`) — unauthenticated by design, hardened: loopback-only
  default, refuses a non-loopback bind without `--allow-remote`, exact-IP Origin validation
  (DNS-rebinding). Enforced by **T68**; security note in `docs/howto/secure-the-mcp-server.md`
  (**T71**).
- **Plugin registers the server** (`plugin/.mcp.json`) — installing the HeartBeat plugin wires
  `hb mcp-serve` for Codex *and* Claude Code (one manifest, both hosts). Enforced by **T69**.
- **`codex` backend** — headless `codex exec` (stdin closed; `HB_EXEC_PROVIDER=oss` → keyless
  Ollama). Enforced by **T66**.
- **`opencode` backend** — headless `opencode run --format json` (SST's provider-agnostic agent;
  `HB_EXEC_MODEL=provider/model`) + the opencode.json MCP wiring. Enforced by **T72**.
- Both backends: both runtimes + registry (a new shared surface → parity), stub-on-PATH suite
  proofs + honest on-demand live tiers. Guides under `docs/howto/`.

## v1.18 — agent-framework how-tos + reproducible Docker proof harness

Guides for driving HeartBeat with each of the seven agent frameworks, on a pinned, reproducible
Docker harness — plus one real packaging fix the harness surfaced.

- **Framework proof harness (`tests/frameworks/`)** — one parametrized Dockerfile
  (`ARG FRAMEWORK`/`ARG VERSION`) + a pinned matrix + `run.sh`. `run.sh --check` validates the
  harness **Docker-free** (valid set derived from the backend registry ∩ pyproject extras);
  `run.sh <fw>` builds the pinned image and drives the real adapter against local Ollama.
  RESULTS.md captures live outcomes. Docker is the on-demand LIVE tier — it never gates the suite.
- **Seven framework guides (`docs/howto/use-heartbeat-with-*.md`)** — CrewAI, LangGraph, Agno,
  OpenAI Agents SDK, AutoGen, smolagents, pydantic-ai. Each written for that framework's typical
  user (division of labor: the framework is Stage B / the reasoner, HeartBeat is the harness that
  verifies — not a replacement), with real `HB_EXEC_*` config, the bring-your-own-agent seam, and
  a containerized live proof. Six reached a strict behavioral-gate pass live against Ollama
  qwen2.5:7b; autogen is honestly recorded as wiring-ok (real run; strict miss was model-luck).
- **agno packaging fix** — agno's Ollama path needs the `ollama` client; added to the `[agno]`
  extra (a user hit the same gap).
- Enforced by suite groups **T64–T65** (Docker-free: harness `--check` + conformance + prose).

## v1.17 — runnable how-to library + exec-config parity

A documentation release: a `docs/howto/` library where every guide is CI-enforced, plus one
runtime fix the doc work surfaced.

- **How-to library (`docs/howto/`)** — guides organized by job (roadmap in
  `docs/howto/howto-list.md`). Mechanism guides are each backed by a runnable, self-verifying
  proof under `docs/howto/gate-examples/` (weakness catalogue, refutation, parity self-test,
  recovery, untrusted-Stage-B, liveness, auditor, portability, conformance, diagnose,
  re-verify, restore points, tick economics, CI, event log, embed, quickstart, DAG authoring,
  stop/resume, backends). Launch-prose guides (sizing, runtime/backend choice, when-not) are
  integrity-checked (links resolve, only real commands) + adversarially clarity-reviewed.
  Enforced by suite groups **T53–T62**.
- **`hb exec config` parity fix** — the Python `hb exec` CLI ignored its `action` arg, so
  `hb exec config` ran the executor instead of printing config (the plugin already printed it).
  The handler now honors `config` / `run` / unknown. Behavioral parity locked by **T63**;
  intentional key-format divergence recorded in `planning/parity-notes.md`.
- **Coherence** — `__version__` now single-sourced from package metadata; docs, the test-group
  map, and the architecture diagrams (version stamp removed) brought current.

## v1.16 — gate-quality strengthening

Three fixes so a gate can't pass on unverified work — from an audit of our own gates.

- **Outcome-asserting coverage.** `tests/run-tests.sh` now tracks per-group pass/fail
  (`grp` helper) and prints a machine-checkable `GROUPS-PASSED:` line listing only groups
  with zero failing checks. A coverage gate keyed on `GROUPS-PASSED:.* Tnn ` asserts the
  group actually PASSED, closing the old `run-tests.sh | grep Tnn` hole (a bare-header grep
  passes on a red suite because the header prints before the run fails and the pipe hides
  the exit code). +T52.
- **Behavioral over source-grep.** Rewrote our `planning/*.dag.json` gates: source-string
  greps (`grep 'def X' file`) → import + assert callable/shape or exercise the entrypoint
  and check protocol output; every coverage gate → the outcome marker. All lint- and
  audit-clean.
- **Clean exemplar.** The default template (`plugin/templates/dag.json`) now audits with
  0 warnings (the `GATE_P1` gate_offphase is resolved — a P1 task produces the artifact the
  gate checks). `/heartbeat plan` guidance documents both rules.

## v1.15 — AutoGen + smolagents + pydantic-ai backends

- Three more Stage-B backends in both runtimes (in-process `backends/` + subprocess
  `executors/`): **`autogen`** (AutoGen AssistantAgent, FILE-block writer),
  **`smolagents`** (ToolCallingAgent + `save_file` tool), **`pydantic-ai`** (Agent +
  `save_file` tool). Same two-method contract, graceful degrade, keyless via Ollama.
- Hardened path handling: `_fileblocks.norm_rel` (strip `$PROJECT_DIR`, map absolute →
  relative-under-cwd/basename) now backs both the FILE-block writer and every `save_file`
  tool, so a model that emits an absolute or prefixed path can't nest files.
- All three proven to drive their framework end-to-end against local Ollama (agent writes
  a file, a behavioral gate runs it). Backends now: claude-code · agno · crewai ·
  langgraph · openai-agents · autogen · smolagents · pydantic-ai · ollama · script.
- Not a parity surface — parity unaffected. +T49/T50/T51 (node), +3 python degrade tests,
  pyproject extras `[autogen]` / `[smolagents]` / `[pydantic-ai]`.

## v1.14 — LangGraph + OpenAI Agents SDK backends

- Two more Stage-B backends in both runtimes (in-process `backends/` + subprocess
  `executors/`): **`langgraph`** (LangGraph ReAct agent + `save_file` tool) and
  **`openai-agents`** (OpenAI Agents SDK Agent + function tool). Same two-method contract,
  graceful degrade when the lib is absent, FILE-block fallback.
- Keyless-testable via Ollama (`HB_EXEC_PROVIDER=ollama`; the OpenAI SDK uses Ollama's
  OpenAI-compatible `/v1`). Both **proven live end-to-end** (model writes code, a
  behavioral gate runs it). Backends: claude-code · agno · crewai · langgraph ·
  openai-agents · ollama · script.
- Backends aren't a parity surface — parity unaffected. +T47/T48 (node degrade/validity),
  +test_backends_frameworks.py (python), pyproject extras `[langgraph]` / `[openai-agents]`.

## v1.13 — review-evidence hardening (both runtimes)

Closes the "grade your own homework" hole: a review **pass** is now reducible to evidence
the deterministic layer can re-inspect.

- **Artifact-backed pass.** `hb review <gate> pass` requires `--artifact <file>` — the
  refuter's written attempt. It must be substantive, **cite a real phase anchor** (gate id
  / task id / a path the gate's criteria reference), and be recorded by a **different actor**
  than the doer (`HB_ACTOR`) — self-reviews are rejected. The artifact is stored under
  `.hb/reviews/` and re-checked by `doctor` (a vanished/thin artifact is Sev-1 rot).
- **Runtime hollow-gate floor.** A zero-criteria gate now fails at `gate.sh`/`gate.run_gate`,
  not just in audit — an un-audited or post-audit-mutated DAG can't buy a free advance.
- **Auditor reach.** New **side_effecting** rule (a gate that writes/creates files can
  fabricate its own pass) + broader nondeterminism (`RANDOM`, `shuf`, `/dev/urandom`,
  `SECONDS`, `$$`, `mktemp`).
- **Driver enforcement.** `hb-exec` persists the refuter's findings, passes `--artifact`
  (escalates on an empty pass), and stamps **distinct worker/refuter actors** so the
  self-review guard is enforced in the automated path.
- **Symmetric + parity-locked.** Mirrored in the Python port; `tests/parity.sh` gains a
  `side-effect` fixture that exercises the new audit rules, so a node/python divergence now
  fails T43 (no false-green).

## v1.11 — audited plan step + full-coverage parity

- **`/heartbeat plan` now audits and refutes before proposing.** Its acceptance step runs
  `hb-lint` (structure) **and `hb-audit` (gate quality)**, then refutes the DAG (skeptic
  agent, or `hb audit --agent` in the port) — so no plan is proposed until it's lint-clean,
  audit-clean, AND a skeptic comes back SOUND.
- **Full-coverage parity.** `tests/parity.sh` now checks node ≡ python across every shared
  surface: lint, audit, **protocol (reason keys)**, **resolve (`hb next`)**, **ready**,
  **report** (progress), **diagnose** (inferred blocker), and the state projection. It
  encodes the one intentional divergence — protocol *action text* is runtime-specific (node
  cites `.hb/hb.js`/`gate.sh`, python cites the `hb` console) — by comparing reason keys.
- Added `hb next` (resolve) to the Python CLI; `--json` to `hb lint`.

## v1.10 — agent DAG review + node↔python parity

- **`hb audit --agent` (Python).** The deterministic auditor catches structural
  weakness; the agent layer catches semantics — a gate that asserts the *wrong*
  behaviour, a phase whose gate doesn't exercise the task's real requirement. It
  dispatches a refutation of the DAG to a configured backend and exits non-zero if the
  reviewer refutes the plan. The node/Claude side has a concrete refuter prompt in the
  skill.
- **Exemplary default template.** The scaffold's gates are now behavioral (the DAG
  lints clean; output reports success) instead of `test -f` — `hb audit` on the template
  is clean, and it still bootstraps green.
- **Parity test (`tests/parity.sh`, ratcheted as T43).** The node plugin and the Python
  port are checked to AGREE on lint (errors), audit (findings), and the state projection
  for shared fixtures. node ≡ python.

## v1.9 — adversarial DAG review (gate quality)

- **`hb-audit.js` + `/heartbeat audit`.** Where `lint` checks structure, `audit` checks
  **gate quality** — the thing that actually bounds HeartBeat's value. It applies
  refute-don't-confirm to the *plan* before you run it, flagging **hollow_gate** (a phase
  whose gate has no behavioral criterion), **ungated**, **unguarded_phase**,
  existence-only / vacuous criteria, **nondeterministic** gates, and **gate_offphase**.
  Exit 1 on any hollow gate. The agent-refutation layer (a skeptical second read of the
  whole DAG) sits on top, documented in the skill.
- **Ported to both runtimes** — `hb-audit.js` (node) and `heartbeat.audit` (`hb audit`,
  Python) share one ruleset and are checked for **parity** on shared fixtures
  (`planning/audit-fixtures/`, see `planning/parity-notes.md`).

## v1.8 — pluggable Stage B

- **`hb-exec.js` executor driver + `/heartbeat exec`.** Stage B is now pluggable. The
  driver runs the same serial loop as `/heartbeat run` but dispatches each task to a
  **backend agent** (`claude-code`, `agno`, `crewai`, or a raw `script`) over a tiny
  JSON wire protocol — so an unattended process can do the work. HeartBeat stays the
  deterministic brain: the tick decides what/when, the gates verify, and the driver
  mediates **every** state transition (the backend never touches `state.json`/`gate.sh`).
- **Wire protocol.** `driver → backend`: `argv[last]=execute|refute`, stdin = payload
  JSON. `backend → driver`: `execute → {ok,summary}`, `refute → {refuted,findings}`.
  A backend is ~two methods; shipped adapters live in `.hb/executors/`.
- **Driver owns the hard parts** (framework-blind): the lease **heartbeat pump** during
  a task, **context assembly** from settled reality (dag + state + git log + gate
  criteria), **escalate-only** on a blocked gate (never auto-fixes), a per-task
  **attempt cap** (`HB_EXEC_ATTEMPT_CAP`, default 3), and **strict mode**
  (`HB_EXEC_STRICT=1`) that refuses non-behavioral gates / lint-warning DAGs.
- **Parallel fan-out** (`HB_MAX_CONCURRENCY > 1` / `run --parallel N`): the runnable
  set (`hb ready N`) runs concurrently, **each task in its own git worktree** so writes
  can't collide; the **merge-back is serialized** and a failed task's worktree is
  discarded. Falls back to concurrent in-place without git.
- **Backends**: `claude-code` (default), `agno`, `crewai`, `ollama` (local models,
  stdlib-only), or a raw `script`. Each degrades to protocol-valid JSON when its
  runtime is absent. `tests/real-backend.sh` drives a live end-to-end run against a
  local model (verified with `qwen2.5:7b-instruct`: the model writes code, a
  behavioral gate compiles and runs it).

## v1.7 — never left guessing

- **Self-describing ticks.** Every wake embeds the exact next action in
  `data.action`, so any driver (cron, headless, another harness) knows what to do
  from the JSON alone.
- **One-source protocol.** A single `reason → action` map in `hb.js` drives
  `data.action`, `hb protocol`, and `.hb/PROTOCOL.md` (written at bootstrap, versioned
  with the project) — no more drift across skill / README / snippet.
- **`hb diagnose`.** For a blocked state, computes the root cause where the substrate
  can — which criteria fail, the commit that deleted a gate's file (git backward-trace),
  the deadlock cause — plus ordered recovery steps. Read-only.
- **SessionStart hook.** Detects a `.hb/` project and injects a tiny pointer, so a
  Claude Code session is always current regardless of installed skill version.
- Fixed a latent bug: `hb.js` is now safely `require`-able (CLI guarded).

## v1.6 — gate liveness

- **`review_stuck`** — an adversarial review that never resolves (agent doesn't run
  it / session died) is now caught by the objective no-progress breaker and escalated
  instead of silently stalling.
- **Automatic rot detection** — the tick runs `doctor` each tick and wakes `gate_rot`
  on rot; a **pre-commit hook** blocks a commit that deletes a file a completed gate
  depends on (bypass: `git commit --no-verify` / `HB_NO_HOOK=1`).

## v1.5 — gate integrity

- **`hb doctor`** — static integrity check. Headline: *rot detection* — a completed
  phase whose gate references a now-deleted file (that gate can no longer be
  reproduced). Also flags DAG errors, state/log drift, stale leases. Read-only.
- **Re-verifiable gates** — `gate.sh --check <GATE>` re-evaluates a gate read-only
  (no state change); `gate.sh --all` re-evaluates every gate (regression check). A
  passed gate keeps acting as a gate instead of a one-shot checkpoint.

## v1.4 — quality & throughput

- **Adversarial gates (second agent).** A gate may carry a `review` block; after the
  deterministic gate passes, the tick emits `review_pending` — a skeptical second
  agent must fail to *refute* completion (`hb review <gate> pass|fail`) before the
  phase advances. Closes the "grade-your-own-homework" hole. Review-less gates behave
  as before.
- **Parallel-when-no-conflict.** `hb ready [N]` surfaces the concurrently-runnable
  (eligible, unleased, requires-independent) set; fan it out as worktree-isolated
  sub-agents. `/heartbeat run` drives serial or parallel.
- **hb-lint advisory warnings.** Flags leftover template/placeholder text and gate
  criteria that reference files no task produces.
- **Notify hook.** `HB_NOTIFY_CMD` fires once on human-needed wakes (build_stuck,
  gate_blocked, deadlock, unsanctioned_drift, all_done). Timeout-bounded, fail-safe.
- **dag.schema.json** for editor validation; **per-task durations** in the report.
- **Git-aware.** Bootstrap runs `git init`; every gate pass commits and force-tags
  the gate id, so each phase is a restore point (`git reset --hard GATE_PN`). Opt out
  with `--no-git` / `HB_NO_GIT` / `HB_GIT_AUTOCOMMIT=0`.

## v1.3 — reliability hardening

- **Event-sourced state (`hb.js`).** `events.jsonl` is authoritative; `state.json`
  is a deterministic projection. Agents mutate state only via the `hb` CLI
  (`start`/`done`/`fail`/`rebuild`/`state`/`import`) — never by hand-editing JSON.
- **Objective no-progress detection.** The tick flags an agent that is woken
  repeatedly without progressing (`build_stuck`, `signal: no_progress`), independent
  of the agent's self-report.
- **Gate criterion timeout.** Each gate criterion runs under `GATE_TIMEOUT_S` (5s
  default) — a hanging criterion blocks the gate instead of hanging the tick.
- **Per-task leases + bounded concurrency.** `HB_MAX_CONCURRENCY` (default 1 =
  serial) lets independent DAG branches run in parallel; stale leases from crashed
  sessions are reclaimed automatically.
- **Mid-session heartbeat.** `hb heartbeat <id>` refreshes a lease during long
  work; a heartbeated lease that goes silent is reclaimed after `HEARTBEAT_STALE_S`
  (default 180s) instead of the slow `LOCK_STALE_S` — hung agents are caught in
  minutes. Leases that never heartbeat keep the slow fallback (no false reclaims).

## Stage A — tick.sh priority checks (order matches tick.sh)

1. **Lock** — atomic `mkdir` lock; guards concurrent ticks and the agent
   session. Stale locks (> `LOCK_STALE_S`, default 1800s) are auto-broken.
2. **Integrity** — corrupt `state.json` → wake `state_corrupted`; corrupt
   `dag.json` → wake `dag_corrupted`.
3. **Circuit breaker** — `build_stuck_count >= 5` → single wake `build_stuck`,
   then silence until human reset.
4. **Drift detection** — SHA256 of `WATCH_PATHS`; baseline auto-frozen on first
   run; unsanctioned change → wake `unsanctioned_drift`.
5. **Gate errors** — a previously failed gate (`gate.errors > 0`) → wake
   `gate_blocked`.
6. **Next task** — eligible pending task → wake; all tasks done but gate unpassed
   → `gate_pending`; project finished → single `all_done`; nothing actionable on
   an unfinished project → single `deadlock` with diagnostic.

Output is always `{ "wakeAgent": true|false, "data": { "reason": "...", ... } }`.

## Tooling (v1.2)

- `hb-next-task.js` — gate-aware resolver with deadlock diagnostics.
- `hb-lint.js` — static DAG validation (dup IDs, cycles, broken `requires`,
  undefined/unreachable gates, oversized phases).
- `hb-report.js` — progress report (text / `--json`).
- `hb-viz.js` — standalone `dag-view.html`.
- `gate.sh` — behavioural gate runner.

## Packaging

Distributed as a Claude Code plugin (local marketplace) and a fallback
`scripts/install.sh`. See `INSTALL.md`.
