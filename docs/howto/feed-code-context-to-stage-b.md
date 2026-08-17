# Feed code context to Stage B

When HeartBeat drives a backend worker (Stage B) through the executor, each task carries a **context**
the worker reads before doing the work. Seam 2 lets a domain adapter add to that context — for code,
the slice of the call/dependency graph the task touches — so the worker starts informed instead of
rediscovering it. The concept is in [adapters.md](../adapters.md).

## The generic hook

The executor exposes one domain-neutral extension point: `context_cmd`. When set, the executor runs
that command once per task and appends its stdout to the task context, wrapped in a stable
`<<HB-CONTEXT>>` delimiter. The executor never inspects what the command emits — it just runs it.
Configure it via the environment or `executor.json`:

```bash
export HB_EXEC_CONTEXT_CMD='bash my-context.sh'
```

The command receives the task via `HB_TASK_ID`, `HB_TASK_TITLE`, and `HB_TASK_DESC` in its
environment, so it can return context specific to that task. If it errors or is slow, the task still
proceeds (the hook degrades and there is a timeout).

## The code provider

For code, `codegraph-context.js` renders a task's subgraph — the symbols it touches plus their
direct neighbors (what each depends on, and what uses it):

```bash
node plugin/adapters/code/codegraph-context.js codemap.json TASK_ID
```

Wrap it in a small `context_cmd` that passes `HB_TASK_ID` through, and point the executor at it. The
codemap comes from your provider (for CodeGraph, via `codegraph-map.js`).

## What's proven, and what's on-demand

The provider and the injection mechanism are gated deterministically (node-suite T88/T89): the
subgraph rendering by [`gate-examples/code-context.sh`](gate-examples/code-context.sh), and the fact
that **both runtimes inject a configured `context_cmd`'s output identically** by
[`gate-examples/context-inject-parity.sh`](gate-examples/context-inject-parity.sh).

```bash
bash docs/howto/gate-examples/code-context.sh          # -> CODE-CONTEXT-OK
bash docs/howto/gate-examples/context-inject-parity.sh  # -> CONTEXT-INJECT-PARITY-OK
```

Driving a **real local model** with the injected context is a separate, on-demand demo
(`tests/real-context.sh`, run against a local ollama model). It needs external tools and is
non-deterministic, so it is *not* part of the gated suite — run it yourself to see the end-to-end
path with a live model.
