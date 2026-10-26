# A malformed plan fails closed

`dag.json` is the plan every HeartBeat tool reads. When it is malformed — a list where an object
belongs, a phase without an id, a truncated file left by a crashed editor — the tools do not each
guess. One judge decides whether the plan's structure is sound, the two runtimes agree on the
verdict byte for byte, and every other reader refuses to act on a broken plan. Nothing crashes,
nothing dispatches work from it, and nothing goes quietly to sleep. Every behavioral claim in the
next two sections is anchored to a case in `tests/dag-shape.sh` (suite group T186); the honest
limits at the end are stated, not proven.

## What counts as structure

Structure is what the readers dereference, and it is written down in the schema itself:
`plugin/dag.schema.json` marks those nodes `"x-hb-structure": true` — `phases` and each phase with
its `id`, `tasks` and each task with its `id`, `requires` and its items, `gate_entry` / `gate_exit`,
`parked` (it decides what runs), `gates` and each gate, a gate's `criteria` and each entry. The
top level must be an object carrying `phases` and `gates`. A gate without `criteria` and a phase
without `tasks` stay outside on purpose (`"x-hb-absent-ok": true`), and an empty `phases` list is
valid. The test derives its mutations from those annotations rather than from a hand-written list:
mark a new node and the proof grows cases for it (k1).

- **`hb lint` is the judge.** Each structure violation is ONE error, named by its path —
  `phases[0].tasks[1].id must be a non-empty string`, `phases: missing` — with identical bytes on
  both runtimes and exit 1 (k1). A non-object criteria entry keeps its existing
  `[G] criteria entry N must be …` line. A wrong-typed `parked` is an error too (k6).
- **An unreadable file is the same failure, with fixed words.** Missing, empty, not valid JSON
  (including a BOM, invalid UTF-8, `NaN`/`Infinity` and an unpaired surrogate), nested deeper than
  256 levels, or not an object at the top — each gets one fixed message, never the parser's own
  text, on both runtimes and through the no-argument `hb lint` as well (k2).
- **Nothing else moved.** Every git-tracked dag lints exactly as it did before this contract
  existed — the proof runs the earlier linters as its oracle — except the adapter fixtures, which
  carry no `gates` map and now say `gates: missing` (k3). The verbs that write `dag.json` (park,
  regate, detach and their reversals) write only keys the schema declares (k4).
- **Audit reports it.** `hb audit` adds one `dag_shape` error naming the first structure error,
  stays tolerant otherwise, and never calls a broken plan "hollow gates" (k5). The edge cases that
  once split the runtimes — integer-like gate names, a gate called `__proto__`, giant numbers,
  `--questions` on a broken plan — agree (k7).

## How the readers fail closed

- **The tick wakes `dag_corrupted`, every tick.** It checks the plan's structure first — before it
  tries to self-heal `state.json` (r9) — and wakes the human-needed `dag_corrupted` reason carrying
  the errors, with an action that names the lint command and says to restore or fix `dag.json`,
  never to hand-edit `state.json` (r1). It never hands out a task from a broken plan and never
  sleeps on one. The event log records one `dag_corrupted` event per blockage, not one per tick (r16).
- **The resolvers answer `deadlock` / `dag_invalid`** with identical keys on both runtimes (r2).
- **A broken resolver is loud, not silent.** A resolver that is missing, crashes, or answers
  something that is no verdict wakes `deadlock` with cause `resolver_error` on every tick — never a
  quiet "nothing to do" — and both drivers stop on every run (r10, r14). Curing it never silences a
  later real deadlock (r15).
- **Verbs refuse or report.** Every verb that changes the plan or its log refuses with no event
  and an untouched `dag.json` (r3); every verb that only shows something exits nonzero with ONE
  line naming the first error and the lint command (r4); gate evaluation exits 4 in every mode,
  ahead of usage errors and a pending regate (r5); doctor reports only the structure errors and
  skips its plan-derived checks, and `hb diagnose` names `dag_corrupted` (r6); both exec drivers
  stop (r7); MCP tools answer by class — `tick` wakes, `next` says `dag_invalid`, lint/audit/doctor/diagnose
  report, the three tools that never read the project's plan (`code_context`, `code_discover`,
  `deplint`) are exempt, and the rest return an error result (r8). The live viz server re-checks on every request and
  answers 409 (r13). If node's `hb-lint.js` itself is missing or outdated, every node reader fails closed with
  one fixed line (r11). The human-needed stop lists name `dag_corrupted` and `state_corrupted` (r12).
- **A sound plan behaves exactly as before** (r0).

## Honest limits

Only structure fails closed: a wrong-typed optional field such as `title` or `desc`, or an
undeclared key, is not a lint finding — the schema documents those types and nothing enforces
them (a few fields keep their own checks: `horizon`, `cmd`, `sweep`, `review` and `regate` are lint
errors, and the gate runner fails a criterion whose `timeout_s` is invalid). A criterion's own
fields are outside STRUCTURE by design: a criterion without a string `id` lints clean, though the
schema requires one, and its label then renders per runtime in the gate's output. Semantic
lint errors (cycles, missing references) keep their own runtime path: they deadlock with
`dag_invalid` when they block, they do not wake `dag_corrupted`. A malformed `review` or
`constraints` block can still crash `refute-prompt` (node's exec driver stops on it with
`review_error`; python's `hb exec` exits with a traceback). A plan with an
empty `phases` list is valid and the tick sleeps on it. A `dag.json` rewritten in the middle of one
tick is read by each section as it finds it — and any crash that causes now wakes instead of
sleeping. The lint rules are hand-written on both runtimes, with the schema as the proof's oracle,
not a runtime dependency.

## Prove it

```bash
bash tests/dag-shape.sh              # DAG-SHAPE-OK — every claim above, both runtimes
bash tests/dag-shape.sh --selftest   # DAG-SHAPE-SELFTEST-OK — each stripped guard reddens its case
```

The suite wires both as group T186, and `tests/parity.sh` holds the cross-runtime verdicts
byte-identical (`shape:lint`, `shape:unreadable`, `shape:audit`, `shape:tick`).
