# Vocabulary

The words HeartBeat uses, defined once. The front door ([README](../README.md)) uses every term in this
table; a proof (`docs/howto/gate-examples/vocabulary.sh`, suite group T155) keeps the two in step and
checks that the command spellings below really work on both runtimes.

## Why "HeartBeat"

HeartBeat's job is to answer one question about a long autonomous run: *is this work alive and moving?*
A task lease carries a keepalive and is reclaimed when it goes silent. A run that wakes repeatedly without
progress trips a breaker. A review that never resolves is flagged. A finished phase whose evidence has
vanished is rot. That is heartbeat monitoring in the plain distributed-systems sense, and it is the
metaphor the rest of the vocabulary follows.

## Terms

| Term | Meaning | Where you meet it |
|---|---|---|
| **pulse** | One cheap, deterministic check of the project's state that returns one decision: sleep, or wake the model with a reason and the exact next action. Costs ~0 tokens. Runs whenever something asks for it — an executor loop, an MCP call, or a timer. | `bash .hb/tick.sh` (plugin), `hb pulse` (Python), `/heartbeat pulse` (skill), the MCP `tick` tool |
| **Stage A** | The pulse. Plain bash or Python; reads settled reality (event log, state, gates), generates nothing. | `tick.sh`, `tick.py` |
| **Stage B** | The model. Runs only when a pulse says there is real work; does one unit of it, records the outcome, stops. | the agent, or a backend under `hb exec` |
| **run** | Driving pulses until the project is done or a human is needed: pulse → act → pulse. | `/heartbeat run`, `hb exec run`, `node .hb/hb-exec.js run` |
| **DAG** | The map of the work: phases break into tasks, each task names what it depends on, gates guard the step from one phase to the next. Directed acyclic graph: work flows forward, never in circles. | `dag.json` |
| **phase** | A stage of the project. Advances only when its exit gate passes. | `dag.json` → `phases[]` |
| **task** | One unit of work inside a phase, with dependencies on other tasks. | `dag.json` → `phases[].tasks[]` |
| **gate** | A behavioral check that must pass before a phase advances: does the thing *work*, not does a file *exist*. Deterministic, time-bounded. | `bash .hb/gate.sh <GATE>`, `hb gate` |
| **refute** | The adversarial review some gates carry: a second, distinct actor is told to disprove that the phase is done. Only a failed refutation (it could not break it) advances the phase, and it must cite written evidence. | `review` block on a gate, `hb review <gate> pass --artifact <file>` |
| **refuter** | The persona and checklist the refuting actor works from. | `hb refuters`, `.hb/refuters/` |
| **lease** | A task's claim by one actor. Prevents double-claiming; reclaimed when its keepalive goes stale. | `.hb/leases/<task>/` |
| **keepalive** | Refreshing a lease during a long task so it is not reclaimed. | `hb keepalive <id>`, `node .hb/hb.js keepalive <id>` |
| **event log** | The append-only source of truth and the audit trail. State is a projection of it and is rebuilt from it after a crash. | `events.jsonl`, `state.json`, `hb rebuild` |
| **drift** | An unsanctioned change to watched files between pulses. | `unsanctioned_drift`, `tick.sh --freeze` |
| **rot** | A completed phase whose gate references a file that no longer exists, so the gate can no longer be reproduced. | `hb doctor`, `gate_rot` |
| **reason** | Why a pulse woke the model. Each reason maps to one action in the protocol. | `data.reason`, `hb protocol` |

## Legacy spellings

Older names are still accepted everywhere they appear, so nothing that runs today breaks. They are not
the words to use in new prose.

| Legacy | Current | Notes |
|---|---|---|
| `tick` (`hb tick`, `/heartbeat tick`, "tick protocol") | **pulse** | The script (`tick.sh`), the Python module (`tick.py`), and the MCP tool (`tick`) keep their file and tool names. |
| `hb heartbeat <id>`, `hb beat <id>` | **keepalive** | The lease's timestamp file is still named `beat`. "beat" is not a term; it survives only as this alias and that filename. |

Cadence is not part of any definition. A timer is one way to drive pulses, and the only one with a
cadence; the executor takes the next pulse as soon as the previous action completes.
