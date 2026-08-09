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

Two gotchas it encodes:
1. Python's `json.dumps` escapes non-ASCII (the `—` in a lint message) → compare with
   `ensure_ascii=False`.
2. **Protocol action text is runtime-specific by design** — node cites `node .hb/hb.js` /
   `bash .hb/gate.sh`; python cites the `hb` console. So parity compares the reason *keys*,
   not the action strings. (If you ever want the reasons themselves to diverge, that's a
   real bug; the wording differing is not.)

## Intentional divergences (not on the byte-equal surface)

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
