<!-- Release candidate. Promote to the repo-root README when you publish. -->

# HeartBeat

**Verify what your agents actually did.** A deterministic harness that drives long, autonomous agent runs, gates every phase on *behavioral* checks, and refutes the plan before it runs.

Most agent tooling helps you *run* agents. HeartBeat is about the harder half: knowing the work is actually done, not just claimed. Agents are confident and often wrong; HeartBeat assumes nothing and verifies everything at defined checkpoints.

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
| **Adversarial verification** | A second agent must fail to refute completion — at execution time *and* plan time. |
| **Restore points** | Every gate pass commits and tags, so each phase is a `git reset` away. |
| **Liveness** | The tick detects stuck loops, unanswered reviews, and gates that silently rot, and escalates instead of waiting forever. |
| **Pluggable workers** | Stage B is a two-method contract; drive it with a local model, headless Claude, seven agent frameworks (Agno, CrewAI, LangGraph, the OpenAI Agents SDK, AutoGen, smolagents, pydantic-ai), or any command. |

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
pip install heartbeat-hb          # or: pip install ./py from a clone
hb init myproject
hb audit --dir myproject          # refuse hollow gates before running
hb exec run --dir myproject       # drive the loop with a backend
```

Describe the work as a DAG (`phases → tasks → behavioral gates`), audit and refute the plan, then let the tick decide — cheaply and deterministically — when to spend the model.

## Backends

Stage B is swappable. A backend implements two functions — `execute → {ok}` and `refute → {refuted}` — so the *same DAG* runs under any of them; the framework is an implementation detail, the gates are the durable asset.

| Backend | Worker |
|---|---|
| `claude-code` | headless `claude -p` |
| `agno` · `crewai` · `langgraph` · `openai-agents` · `autogen` · `smolagents` · `pydantic-ai` | agent frameworks; local models (no API key) or a provider |
| `ollama` | local models, stdlib only, offline |
| `script` | any command, any language |

Adding another framework is one small adapter (two methods + graceful degrade) — it doesn't touch the core, and it can't break the runtime parity.

## How it works

The concept, in plain terms: [The gaps are deterministic](../docs/heartbeat.md). Architecture: [plugin](../docs/heartbeat-arch-full.png) · [Python port](../docs/heartbeat-py-arch.png).

## Honest limits

HeartBeat is only as good as your gates. A weak gate produces *false* confidence, which is worse than none — so it ships an auditor that flags hollow gates before you run, and an adversarial reviewer that refutes the plan. Neither guarantees a gate tests the *right* behavior; that last mile is still on you. Its value concentrates in long, multi-phase, verifiable work; for a throwaway script the ceremony is overhead.

## Docs

Concept: [heartbeat.md](../docs/heartbeat.md). Backend reference: [dev-plugin.md](../docs/dev-plugin.md) · [dev-python.md](../docs/dev-python.md) · [dev-tests.md](../docs/dev-tests.md). Contributor rules: [AGENTS.md](../AGENTS.md).

## License

MIT.
