# Use HeartBeat with Codex

**Outcome:** run a HeartBeat project with **Codex** (OpenAI's terminal coding agent) as the
worker — Codex does the coding, HeartBeat schedules the tasks, gates each on a behavioral check,
refutes sensitive ones, and recovers.

## Codex is Stage B; HeartBeat is the harness

Codex CLI and Claude Code are the same *kind* of thing — an interactive terminal coding agent.
HeartBeat doesn't replace it; it wraps it. `codex exec` (Codex's non-interactive mode) is the
worker for one HeartBeat task, exactly as `claude -p` is for the `claude-code` backend. HeartBeat
owns the DAG, the gates, the event-sourced state, and escalation; Codex owns the reasoning and
edits for a single task — and its result is never trusted, only gate-verified
([keep-stage-b-untrusted.md](keep-stage-b-untrusted.md)).

## Do it

```bash
codex login                                    # authenticate once (ChatGPT or an OpenAI key)
HB_EXEC_BACKEND=codex hb exec run --dir myproject

# keyless local instead (drives a local model through Ollama):
HB_EXEC_BACKEND=codex HB_EXEC_PROVIDER=oss HB_EXEC_MODEL=qwen2.5:7b-instruct \
  hb exec run --dir myproject
```

The adapter runs `codex exec` non-interactively with the right autonomous flags for you —
`-s workspace-write` (sandboxed, may edit the project), `-C <task dir>`, `--skip-git-repo-check`,
and, in the Python runtime, `-o <last-message>` for the summary. In the plugin runtime it's
`codex-exec.sh` (which captures stdout instead of using `-o`); in the Python runtime it's
`backends/codex.py`. Both are thin wrappers over `codex exec`.

## Gotcha (the one that matters)

`codex exec` **blocks reading stdin** when you pass the prompt as an argument and leave stdin
open — it will hang forever. The adapter always closes stdin (`</dev/null`); if you script Codex
yourself, do the same. Also: `-s workspace-write` keeps Codex sandboxed to the project; don't
reach for `--dangerously-bypass-approvals-and-sandbox` just to make it non-interactive — closing
stdin is what makes it non-interactive.

## Network (opt-in)

`-s workspace-write` gives Codex **no network — not even loopback** (`curl http://127.0.0.1:…` fails).
That is the right default for a worker, but it means a Codex refuter cannot exercise a server the
phase starts locally. Opt in explicitly:

```bash
HB_CODEX_NETWORK=1 HB_EXEC_BACKEND=codex hb exec run --dir myproject
```

With `HB_CODEX_NETWORK=1` (exactly `1`), the execute and refute calls add
`-c sandbox_workspace_write.network_access=true`; the constraint author stays read-only without
network. This opens the sandbox's network generally — outbound too, not only loopback — so turn it on
for projects whose review needs it, not by default. The suite proof checks the flag reaches Codex in
both runtimes with a stub `codex` ([`tests/codex-network.sh`](../../tests/codex-network.sh)); the
override itself was checked live (without it `curl` to a local server exits 7, with it the page is
read) on codex-cli 0.157.1 — re-check on your version.

## Point it at your own setup

The adapter is a small file — edit `backends/codex.py` (or `codex-exec.sh`) to add Codex config
(`-c key=value`, a `--model`, MCP servers via `~/.codex/config.toml`) for your project. A custom
adapter is validated like any backend ([build-and-test-a-backend.md](build-and-test-a-backend.md)),
and the gate-is-contract means you can swap Codex → Claude → a local model without touching the
DAG ([swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md)).

## Proof (honest)

The deterministic, suite-enforced proof mocks only the CLI — a **stub `codex` on PATH** drives
the real adapter through the real gate (and a failing stub does *not* complete the phase):

```bash
bash docs/howto/gate-examples/codex-backend.sh   # -> CODEX-BACKEND-OK
```

Live behavior is on-demand, not gated: the authed path needs a valid `codex login`; the keyless
`HB_EXEC_PROVIDER=oss` path runs end to end against Ollama, but a small local model can miss a
strict task through Codex's agent loop (wiring-ok, not a wiring failure — the same honesty as the
framework guides). Codex, like `claude-code`, is a hosted/agentic CLI, so its proof is the stub
pattern rather than the pinned-Docker live tier used for the pip-installed frameworks.
