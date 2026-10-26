# GATE_S2 refutation, cycle 2

## Probes (all in scratchpad copies of the repo minus top-level .hb; repo untouched)
- Baseline copy (m2.DYbn): `bash tests/dag-shape.sh readers` -> SHAPE-READERS-OK (94 derived mutations); `--selftest readers` -> SHAPE-SELFTEST-READERS-OK; `bash tests/parity.sh` -> PARITY OK; `py/.venv/bin/python -m pytest -q py` (in repo, PYTHONDONTWRITEBYTECODE) -> 187 passed.
- Mutations, each in its own copy, running `bash tests/dag-shape.sh readers`:
  - Mutation for G1 — deleted the per-request `shapeProblem` line in hb-viz.js -> RED at r13 ("not refused with 409": 200 + rendered html).
  - Mutation for G2 node — tick.sh usable-answer check replaced by `process.exit(0)` -> RED at r14 [node {}] (wake next_task, next_task {}).
  - Mutation for G2 python — `_usable` returns True -> RED at r14 [python {}] (wake next_task {}).
  - Mutation for G3 node — resolver_error branch also touches .deadlock-alerted -> RED at r15 (node): deadlock_waiting on the orphan.
  - Mutation for G3 python — same touch in tick.py -> RED at r15 (py).
  - Mutation for G4 node — dag_corrupted logged every tick -> RED at r16 (node) (events 3 -> 6).
  - Mutation for G4 python — append every tick -> RED at r16 (py) (events 3 -> 6).
- Live probe (G1) — server on clean fixture; dag.json rewritten to truncated `{"phases": [`, null, [], "", "x", 5, phases[0].tasks="x", phases[0].parked="no", phases=null, deleted: every /state and / returned 409 with the first structure error and `node .hb/hb-lint.js .hb/dag.json`; server stayed alive; restored dag -> /state 200.
- Live probe (G4) — tasks="x" fixture, 3 node ticks vs 3 `heartbeat.cli tick`: each wakes dag_corrupted with errors; exactly 1 dag_corrupted event on each runtime; after restore both tick next_task and no .dag-corrupted-alerted flag remains.
- Entry-point derivation not redone beyond cycle 1 (270 refusal rows held there); r11/r12/r9 pass in baseline.

## Findings (none blocks)
- Side note (LOW, not a defect of the contract): a resolver that prints a syntactically valid task view with a bogus string id (`{"id":"ghost"}`) is accepted by both ticks and appends `wake task=ghost` (tick.sh: next_task ghost). The doer's contract is "non-empty string id", so this is within it; checking the id against the plan would close it.
- Note: spec lists `task` among known types, but both ticks reject `{"type":"task",...}` (the resolver never emits a type on a task view); identical on both runtimes.
- Hygiene: my pytest fallback once wrote a stray file /home/curtism/Drums/lab/base-py.txt; removed. No other repo writes; no servers left.
- Cycle-1 holes H1/H2 were not re-verified this round (outside G1-G4 focus).

## One line per id
P1: NOT-REPRODUCED — baseline readers green (94 mutations); both ticks wake dag_corrupted with errors identically (G4 live probe), r9/r10 pass.
P2: NOT-REPRODUCED — readers run green incl. r11/r12/r13 and verb coverage checks; no new entry point found failing open.
P3: NOT-REPRODUCED — parity PARITY OK, pytest 187 passed, restore tick gives next_task on a lint-clean dag on both runtimes.
P4: NOT-REPRODUCED — each of the 7 mutations reddened the named case r13-r16 by behavior (copy compiled, earlier cases passed); selftest green.
G1: NOT-REPRODUCED — live probe above: 409 + first error + lint command for every malformed/unreadable shape, server alive, 200 after restore; mutation removing the check reddens r13.
G2: NOT-REPRODUCED — mutations on node and python reddened r14; baseline r14 green for {} [] "x" 5 {"task":"t2"} on ticks and both drivers.
G3: NOT-REPRODUCED — mutations arming .deadlock-alerted on resolver_error redden r15 on both runtimes; baseline wakes the orphan deadlock after cure.
G4: NOT-REPRODUCED — live: 1 dag_corrupted event per runtime over 3 ticks; every-tick mutation reddens r16 both runtimes.

HOLES: none

CLEAR
