<!-- Draft launch post (Show HN / blog). Plain, first-person. Not published. -->

# HeartBeat: verify what your agents actually did

I've been running long, autonomous coding agents for a while, and the thing that kept breaking wasn't capability — it was trust. Over hours and many steps an agent drifts, repeats itself, and reports success on work that doesn't hold. Most of the tooling I found was about *running* agents. I wanted the harder half: knowing the work was actually done.

HeartBeat is what I built. It's a small, deterministic harness around a non-deterministic worker. I'm sharing it in case the approach is useful.

The starting observation was simple. The non-determinism lives *inside* the tasks — the reasoning, the writing. But the time *between* tasks is deterministic. When one unit of work settles and before the next begins, nothing is being generated: the files are what they are, reality is observable with no model in the loop. That gap is a deterministic component sitting inside a non-deterministic flow, and you can use it.

Three moves follow from that:

**Ticks.** Cheap, deterministic code runs on a schedule, reads the settled state, and wakes the agent only when there's real work — nothing generated, almost no cost, the expensive resource spent only when needed.

**Behavioral gates.** The project is a DAG: phases, tasks, and gates. A gate is a fast, deterministic check that must pass before a phase counts as done — not "does the file exist" but "does the thing work": the endpoint returns 200, the row persisted, the invariant holds. A phase doesn't advance until its gate passes.

**Refute, don't confirm.** This is the part I care about most. An agent that writes both the code and the test that grades it will confirm itself — a model is good at producing reasons to say yes. So sensitive gates aren't confirmed; a second agent is asked to *prove the phase isn't done*. And the plan itself gets refuted before it runs — hollow gates, phases with no real coverage, get caught before a token is spent. Looking for the one reason to say no catches what looking for reasons to say yes waves through.

Underneath: state is event-sourced, so a dead session rebuilds and continues; every gate pass commits and tags, so each phase is a restore point; the tick notices stuck loops and gates that silently rot and escalates instead of waiting forever.

It runs two ways — a Claude Code plugin, or `pip install` as a pure-Python package with one `hb` console that runs anywhere Python does. Stage B (the worker) is a two-method contract, so you can drive it with a local model, a headless CLI agent (Claude Code, Codex, OpenCode), any of seven agent frameworks (Agno, CrewAI, LangGraph, the OpenAI Agents SDK, AutoGen, smolagents, pydantic-ai), or any command — the same DAG runs under all of them. The two implementations are kept identical by a parity test.

It also works the other way around. HeartBeat is now an MCP server: `hb mcp-serve` exposes its tick/gate/state tools over the Model Context Protocol, so instead of HeartBeat driving an agent, an agent can drive HeartBeat — Codex, Claude Code, or OpenCode asks *what's next*, does the work, and calls the *gate* to verify, acting on the deterministic answer. One server, every client — and installing the HeartBeat plugin wires it for either host, so there's nothing to configure. It's stdlib-only (no SDK) and speaks both the classic MCP handshake and the new 2026-07-28 revision, which I checked against the official SDK's own client. The trust boundary is the same either way: a caller can't fabricate a pass, because the gate is behavioral and a review needs a different actor.

Something I didn't plan: the documentation ended up dogfooded. Every how-to guide is backed by a small runnable proof — the one on behavioral gates ships a script that shows a weak gate passing on a stub and the behavioral one rejecting it; the operational guides drive the real CLI and assert what happened. The whole library is checked by the test suite, so a guide can't quietly drift from the code. Writing them that way actually turned up a real bug — a command that printed config in one runtime but silently ran in the other — which felt like the method working on itself.

The framework guides pushed that further. HeartBeat's worker can be any of seven agent frameworks (CrewAI, LangGraph, Agno, the OpenAI Agents SDK, AutoGen, smolagents, pydantic-ai), and "does it actually work with mine?" only means something if you can rerun it. So each guide is proven by a live run in a pinned Docker image — the real framework driving the real adapter against a local model — one parametrized recipe plus a version matrix, so the proof reproduces later and adding a framework is a line. Pinning them like that immediately caught a real packaging gap in one adapter, and was honest about the rest: six drove a local 7B model to pass the strict behavioral gate; one only reached the framework-ran-and-wrote-a-file bar on that run, which I recorded as-is rather than dressing up. The Docker runs are on-demand — they never gate the suite, which stays green on a plain machine.

The honest part: it's only as good as your gates. A weak gate gives you *false* confidence, which is worse than none — so it ships an auditor that refuses hollow gates before you run. It won't guarantee a gate tests the *right* thing; that's still on you. And it earns its keep on long, verifiable work, not throwaway scripts.

I have nothing to prove here — I've used it for my own work and it helped, and the approach felt worth putting out. If it's useful to you, good.

MIT. [Repo](#) · [The gaps are deterministic (the longer writeup)](#).
