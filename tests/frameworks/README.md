# Framework proof harness

Reproducible, **pinned** per-framework proof images for the agent-framework backends. A live
run (real framework → real HeartBeat adapter → real gate, against local Ollama) is captured as
re-runnable evidence — so it can't rot, and each framework's dependency tree stays isolated.

## Contract

- **`Dockerfile`** — one parametrized recipe (`ARG FRAMEWORK`, `ARG VERSION`) on `python:3.11-slim`:
  installs HeartBeat from the mounted repo, then the pinned framework, then runs `incontainer.sh`.
- **`matrix.txt`** — `<framework>  <pip install spec>`, one line per framework. The pin is the
  version the guide's live proof is reproducible against; bump it deliberately, then re-run.
- **`incontainer.sh`** — drives the real backend for one task and reports a `LIVE:` /
  `VERDICT:` line (produced / structural / behavioral).
- **`run.sh`**:
  - `run.sh --check <fw>` / `--check-all` — validate the harness **without Docker**; the valid
    framework set is derived from the backend registry ∩ `pyproject` extras (a bogus framework
    or an un-pinned one is rejected). Prints `FRAMEWORK-HARNESS-OK:<fw>` / `HARNESS-ALL-OK`.
  - `run.sh <fw>` — build the pinned image and drive it against local Ollama (`--network host`;
    use `host.docker.internal` on mac/win).
- **`RESULTS.md`** — captured live outcomes (framework, version, model, date, verdict).

## Boundaries (deliberate)

- **Docker is the on-demand LIVE tier — it never gates the test suite.** `run-tests.sh` /
  `pytest` / `parity.sh` stay Docker-free and green on any machine; the suite enforces only the
  Docker-free `--check` + the backend conformance/degrade contract.
- **Reproducible environment ≠ reproducible output.** The model inside is non-deterministic, so
  a small local model may miss a strict gate by luck. The proof verifies the *wiring*; the
  verdict records whether the strict gate also passed.

## Add a framework

Append a pinned line to `matrix.txt` (it must be a real backend extra), then
`run.sh --check <fw>` and `run.sh <fw>`. No Dockerfile change — the recipe is parametrized.
