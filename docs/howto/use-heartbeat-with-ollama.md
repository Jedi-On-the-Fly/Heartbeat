# Use HeartBeat with Ollama

**Outcome:** run a HeartBeat project with a **local model** — fully offline, no API key. The
DAG and gates don't change; only the worker does.

## Do it

Start [Ollama](https://ollama.com) and pull a model, then select the `ollama` backend:

```bash
ollama pull qwen2.5:7b-instruct
HB_EXEC_BACKEND=ollama HB_EXEC_MODEL=qwen2.5:7b-instruct hb exec run --dir myproject
```

The backend is stdlib-only (no extra dependencies) and talks to Ollama's OpenAI-free
`/api/generate`. A text model can't call tools, so `execute` runs a small **FILE-block
protocol**: the model returns file contents in `===FILE: path===` … `===END===` blocks and the
backend writes them. Config: `OLLAMA_HOST` (default `http://localhost:11434`),
`HB_EXEC_MODEL` / `OLLAMA_MODEL`.

## What HeartBeat does

The worker changed; **Stage A and the gates did not**. The tick still decides what runs, the
gate still verifies the result, and the driver still escalates on a blocked gate — so a weaker
local model is safe: the worst it can do is fail a gate, never fake a pass. Realistic
expectations matter — a 7B model clears simple, well-scoped tasks; hard tasks want a bigger
model or tighter task sizing.

## Prove it worked

Model output is non-deterministic, so the enforced proof mocks *only the model*: a local HTTP
server stands in for `/api/generate` while the real adapter (request, FILE-block parse, file
write), driver, and gate run unchanged — and a dead host is shown to degrade.
[`gate-examples/ollama-backend.sh`](gate-examples/ollama-backend.sh) → `OLLAMA-BACKEND-OK`.

For a genuinely live check, run the command above against a real local model and inspect the
result with `hb state` — the same DAG that runs under any other backend
([swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md)).

## Next

- Drive an agent framework instead of a raw model, or write your own adapter:
  [build-and-test-a-backend.md](build-and-test-a-backend.md).
- Prove your DAG isn't secretly coupled to one worker:
  [swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md).
