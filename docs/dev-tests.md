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

The `docs/howto/` proof scripts (`docs/howto/gate-examples/`) are runnable, self-verifying, and enforced by T53–T76; see [../docs/howto/howto-list.md](../docs/howto/howto-list.md). The agent-backend/framework guides (T64–T66, T72) are enforced Docker-free (harness `--check` + backend conformance + prose-integrity); their live proof is the reproducible **pinned Docker** harness in [`../tests/frameworks/`](../tests/frameworks/) — an on-demand tier that never gates the suite. The MCP server is enforced Docker-free by T67–T71 (JSON-RPC over stdio/HTTP with our own client, deterministic); its real-third-party-client proof — the official MCP Python SDK v2 driving `hb mcp-serve` — is `tests/mcp-interop.sh`, an on-demand tier behind the `[mcp-test]` extra (`mcp>=2`) that never gates the suite.

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
| audit | `[errors, warns, sorted rules]` on 4 fixtures |
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
| `planning/audit-fixtures/{hollow,existence,nondeterministic,good}.json` | auditor + parity |
| `planning/parity-fixtures/broken.json` | lint-error parity |

## Invariants

- Node suite, Python suite, and parity stay green on every change; a new shared surface adds a parity case.
- New behavior is gated by a spec-first test in the owning suite; cross-runtime behavior adds a parity comparison.
- Determinism globals (`STUCK_TICKS`, `HB_NO_GIT`, `HB_ROT_CHECK`) are opt-out per test, never removed wholesale.
