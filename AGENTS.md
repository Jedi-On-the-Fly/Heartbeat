# AGENTS.md — HeartBeat

Non-negotiable rules for any coding agent (or human) working on this repo. Detail lives in the dev docs; this is the minimum you must hold. General engineering practice (think before coding, minimal/surgical diffs) is assumed.

## Rules

1. **Event log is truth.** `events.jsonl` is authoritative; `state.json` is a derived projection — never hand-edit it. Mutate state only through the CLI (`start`/`done`/`fail`/`review`/`rebuild`; node `hb.js`, python `hb`). Recover with `rebuild`.
2. **Two runtimes, one behavior — parity is a contract.** The plugin (`plugin/`, node+bash) and the port (`py/`, Python) share the `dag.json` format and tick protocol. `project` / `resolve` / `lint` / `audit` must return identical results on both, and `PROTOCOL` reason keys must match (action *text* is runtime-specific by design). Change one side's shared logic → mirror it on the other and keep `tests/parity.sh` green. A new shared surface adds a parity case. Beyond the fixed fixtures, `tests/parity-fuzz.sh` (node-suite T75) fuzzes seeded generated cases through both runtimes — two implementations of one spec are each other's oracle. See [parity-notes.md](planning/parity-notes.md).
3. **Gates must be behavioral.** Deterministic, under `GATE_TIMEOUT_S`, asserting behavior — not existence (`test -f` / `true` are hollow). Every DAG — the seeded template and any generated plan — must pass `hb-audit` clean (0 hollow gates) and be refuted (audit + agent → SOUND) before it runs. How to write them: [writing-behavioral-gates.md](docs/howto/writing-behavioral-gates.md) (a catalogue of weaknesses, each a runnable proof).
4. **Suites stay green; spec-first.** Node (`tests/run-tests.sh`), Python (`pytest` in `py/`), and parity (`tests/parity.sh`) must pass on every change. Write the failing test first, then implement. New behavior is gated by a test in the owning suite.
5. **Stage B is untrusted; the driver mediates.** Backends never touch `state.json` or `gate.sh`. The executor owns every state transition and, on a blocked gate, escalates — it never auto-weakens or auto-fixes a gate.
6. **A review pass must cite evidence, not assert one.** `hb review <gate> pass` requires `--artifact <file>`: the refuter's written attempt, which must be substantive, cite a real phase anchor, and come from a **different actor** than the one who did the work (`HB_ACTOR`). The artifact is stored and re-checked by `doctor` (it can rot). A zero-criteria gate fails at runtime; a gate that *writes* its own evidence is flagged (`side_effecting`). Never weaken these to make a pass go through.
7. **Docs are source of truth, current-state only.** Keep [dev-plugin.md](docs/dev-plugin.md) / [dev-python.md](docs/dev-python.md) / [dev-tests.md](docs/dev-tests.md) in step with code. No version narrative, no archeology — describe what is. A doc is a claim: gate a new how-to with a runnable proof or prose-integrity check and refute it before it ships — the [gated-docs](plugin/skills/gated-docs/SKILL.md) skill is the method.
8. **Local only.** Do not publish (marketplace), push, or upload unless explicitly asked.

## Before you commit

| Check | Command |
|---|---|
| Node suite | `bash tests/run-tests.sh` |
| Python suite | `cd py && PYTHONPATH=src python3 -m pytest -q` |
| Parity | `bash tests/parity.sh` |
| Audit any DAG you touched | `node plugin/templates/hb-audit.js <dag.json>` |

## Reference

Backend detail: [dev-plugin.md](docs/dev-plugin.md) · [dev-python.md](docs/dev-python.md). Tests: [dev-tests.md](docs/dev-tests.md). Parity contract + intentional divergences: [parity-notes.md](planning/parity-notes.md). Concept: [heartbeat.md](docs/heartbeat.md).
