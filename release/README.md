<!-- Release candidate. Promote to the repo-root README when you publish. -->

# HeartBeat

**Verify what your agents actually did.** A deterministic harness that drives long, autonomous agent runs, gates every phase on *behavioral* checks, and refutes the plan before it runs.

Most agent tooling helps you *run* agents. HeartBeat is about the harder half: knowing the work is actually done, not just claimed. Agents are confident and often wrong; HeartBeat assumes nothing and verifies everything at defined checkpoints.

*New in **v1.27** — the **research adapter completes its loop**: an internet-sourced writeup earns acceptance the same way code does — **source** (on-demand, non-gated) → **stamp** honest source hashes (`stamp-evidence`) → **ground** every claim's verbatim quote against its stored source (`ground-check --strict`, the gate) → **refute** with a distinct actor (seeded by `hb-audit --questions`) → **write** each section against only its grounded evidence (`research-context`). It verifies **grounding, not truth** — HeartBeat does not fetch or fact-check for you. (v1.26 made the **evidence lifecycle first-class** — reviewed-only checkpoints, generated falsification questions, gate provenance via `hb evidence`, graph blind-spots; v1.25 the **domain-adapter architecture** — code + docs, both runtimes, over MCP; v1.24 **cross-runtime parity hardening**; v1.23 the **scheduled self-audit**; v1.22 the `gated-docs` skill; v1.21 the **parity oracle**; v1.20 the **cross-model refuter**; v1.19 the **MCP server**.) Details below.*

---

## The idea, in three moves

- **Ticks — spend the model only when there's work.** Between tasks, reality is settled and deterministic. A cheap tick reads that settled state and wakes the agent only when there is real work to do — no model in the idle loop.
- **Behavioral gates — prove it works, not that a file exists.** A phase advances only when a fast, deterministic check passes: the endpoint returns 200, the row persisted, the invariant holds. Not `test -f`.
- **Refute, don't confirm.** An agent that writes both the code and its test will confirm itself. So sensitive gates aren't confirmed — a second agent is asked to *prove the phase isn't done*. And the *plan itself* is refuted before it runs: hollow gates and phases with no real coverage are caught before you spend a token.

## What you get

| | |
|---|---|
| **Informed state** | Event-sourced; state is a projection of an append-only log. A session dies, the next tick rebuilds and continues. |
| **Behavioral gates** | One-line checks that assert behavior; a phase can't advance until they pass. |
| **Adversarial verification** | A second agent must fail to refute completion — at execution time *and* plan time; the refuter can run on a *different model* than the doer. |
| **Restore points** | Every gate pass commits and tags, so each phase is a `git reset` away. |
| **Liveness** | The tick detects stuck loops, unanswered reviews, and gates that silently rot, and escalates instead of waiting forever. |
| **Pluggable workers** | Stage B is a two-method contract; drive it with a local model, a headless CLI agent (Claude Code, Codex, OpenCode), seven agent frameworks (Agno, CrewAI, LangGraph, the OpenAI Agents SDK, AutoGen, smolagents, pydantic-ai), or any command. |
| **Drives, or is driven** | Besides driving agents, HeartBeat *is* an MCP server: any MCP client (Codex, Claude Code, OpenCode) can call its tick / gate / state tools mid-session. |

## Two ways to run it

- **Claude Code plugin** (node + bash) — the `/heartbeat` skill: plan, lint, audit, run, drive.
- **`pip install`** (pure Python, stdlib core) — one `hb` console, runs anywhere Python does, no Claude Code required.

Same DAG format and protocol; the two implementations are kept in lockstep by a parity test.

## Quickstart

**Plugin (Claude Code):**
```
/plugin marketplace add <path-or-owner/repo>
/plugin install heartbeat
/heartbeat init <project-dir>
```

**Python:**
```bash
pip install -e py                 # from a clone (heartbeat-hb is not published)
hb init myproject
hb audit --dir myproject          # refuse hollow gates before running
hb exec run --dir myproject       # drive the loop with a backend
```

Describe the work as a DAG (`phases → tasks → behavioral gates`), audit and refute the plan, then let the tick decide — cheaply and deterministically — when to spend the model.

## Backends

Stage B is swappable. A backend implements two functions — `execute → {ok}` and `refute → {refuted}` — so the *same DAG* runs under any of them; the framework is an implementation detail, the gates are the durable asset.

| Backend | Worker |
|---|---|
| `claude-code` · `codex` · `opencode` | headless CLI agents (`claude -p` · `codex exec` · `opencode run`) |
| `agno` · `crewai` · `langgraph` · `openai-agents` · `autogen` · `smolagents` · `pydantic-ai` | agent frameworks; local models (no API key) or a provider |
| `ollama` | local models, stdlib only, offline |
| `script` | any command, any language |

Adding another is one small adapter (two methods + graceful degrade) — it doesn't touch the core, and it can't break the runtime parity.

Because the same DAG runs under any backend, `hb bench --dir <project> --backend a --backend b` runs it under each and scores them behaviorally from the event log (the gates are the rubric) — a capability probe, not a leaderboard. Add `--baseline` for a model-regression signal (did a newer model clear fewer gates?), and `hb reward` extracts the log's gate verdicts as a verifiable-reward stream. And the refuter can run on a *different* model than the doer (`HB_REFUTE_BACKEND`/`HB_REFUTE_MODEL`) so a model doesn't grade its own blind spots.

## Drive HeartBeat from your agent (MCP)

HeartBeat also runs the other way. `hb mcp-serve` exposes its `tick` / `gate` / `state` tools over the [Model Context Protocol](https://modelcontextprotocol.io), so an MCP-capable agent — **Codex, Claude Code, or OpenCode** — can drive HeartBeat mid-session: ask what's next, do the work, call the gate to verify, and act on the deterministic answer. One server, every client — and installing the HeartBeat plugin registers it for you on either host, no manual `mcp add` ([install guide](../docs/howto/install-the-heartbeat-plugin.md)).

It's **stdlib-only** (no SDK) and **dual-stacks** the spec — the classic handshake for today's hosts and the 2026-07-28 revision (via `server/discover`) for new ones — verified against the official MCP SDK reference client. The trust model is unchanged: a caller can't fabricate a pass (behavioral gate + distinct-actor review), and the HTTP transport is hardened (loopback default, Origin validation). See [drive HeartBeat over MCP](../docs/howto/drive-heartbeat-over-mcp.md) and the [security note](../docs/howto/secure-the-mcp-server.md).

## How it works

The concept, in plain terms: [The gaps are deterministic](../docs/heartbeat.md). Architecture: [plugin](../docs/heartbeat-arch-full.png) · [Python port](../docs/heartbeat-py-arch.png).

## The docs are proofs

HeartBeat is about verifying what actually happened — so its own guides are held to that
standard. Every how-to in [docs/howto/](../docs/howto/) is backed by a runnable, self-verifying
proof: the mechanism guides ship a script that demonstrates the behavior (and fails if it
regresses), and the decision guides are integrity-checked (links resolve, only real commands)
and adversarially reviewed for clarity. The whole library is enforced by the test suite, so a
guide can't quietly drift from the code. Start at [writing behavioral gates](../docs/howto/writing-behavioral-gates.md)
or the [roadmap](../docs/howto/howto-list.md).

The agent-framework guides go a step further. Each is proven by a **live run in a pinned Docker
image** — the real framework (CrewAI, LangGraph, Agno, the OpenAI Agents SDK, AutoGen, smolagents,
pydantic-ai) driving the real adapter against a local model, captured in
[tests/frameworks/](../tests/frameworks/). Pinning keeps the proof reproducible as frameworks
drift, isolates each dependency tree, and — because the recipe is one parametrized Dockerfile plus
a version matrix — adding a framework is a matrix line. (The Docker runs are an on-demand tier;
they never gate the suite, which stays green with no Docker.)

## Honest limits

HeartBeat is only as good as your gates. A weak gate produces *false* confidence, which is worse than none — so it ships an auditor that flags hollow gates before you run, and an adversarial reviewer that refutes the plan. Neither guarantees a gate tests the *right* behavior; that last mile is still on you. Its value concentrates in long, multi-phase, verifiable work; for a throwaway script the ceremony is overhead.

## Docs

Concept: [heartbeat.md](../docs/heartbeat.md). How-to library (runnable): [docs/howto/](../docs/howto/) · [roadmap](../docs/howto/howto-list.md). Backend reference: [dev-plugin.md](../docs/dev-plugin.md) · [dev-python.md](../docs/dev-python.md) · [dev-tests.md](../docs/dev-tests.md). Contributor rules: [AGENTS.md](../AGENTS.md).

## License

MIT.
