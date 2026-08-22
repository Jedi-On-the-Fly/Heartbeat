# GATE_LK refutation attempt — tick-append-safe / write-lock scope

**Actor:** `HB_ACTOR=lk-refuter` (did NOT do this work).
**Target:** Phase LK of the v1.28 plan. Claim: `tick.sh` appends informational events
(`wake` / `lease_expired` / `review_wake` / `log_event`) to `events.jsonl` via a raw
`echo "{json}" >> "$EVENTS"` OUTSIDE the write-lock, and that this is SAFE by design
(POSIX O_APPEND atomic short-line writes + reproject as a full re-fold ⇒ state.json
eventually consistent; the lock only guards the state.json read-modify-write). Proven by
`docs/howto/gate-examples/tick-append-safe.sh` (T140), documented in `parity-notes.md`
("Write-lock scope") + `dev-plugin.md` + `dev-python.md`.

I tried hard to refute this. I could not. Every attempt below stands SOUND.

## 1. Does the proof use the SAME idiom and would it detect corruption?

`tick-append-safe.sh` part (a), line 37:
```
( echo "{\"ts\":\"$TS\",\"event\":\"probe\",\"id\":\"$i\"}" >> "$ev" ) &
```
This is byte-for-byte the tick.sh idiom `echo "{...}" >> "$EVENTS"`. The python assertion
(lines 40–50) is a **triple** check, not a smell test:
- `len(lines) == n` — catches a lost or duplicated append,
- `json.loads(l)` on every line — catches a torn / interleaved line,
- `ids == {1..n}` — catches an append that was overwritten or lost.
A pass genuinely implies no line was torn, lost, or duplicated. Not vacuous.

## 2. Teeth check

- `bash tick-append-safe.sh --selftest` →
  `SELFTEST-OK: a non-atomic read-concat-write lost updates under concurrency (2 < 40)`.
  The non-atomic writer genuinely loses updates, so the methodology can detect corruption.
- Main proof run 10× (`for i in $(seq 10); do ... | tail -1; done`) → **10× `TICK-APPEND-SAFE-OK`**,
  no non-OK line, not flaky on this box.
- **Constructed the adversarial scenario the prompt asked for:** I sabotaged the MAIN writer
  in a copy, replacing the atomic `>>` with a non-atomic read-concat-write. Result:
  `AssertionError: line count 1 != 60 (lost or duplicated an append)` → `FAIL`. So IF `>>`
  were not atomic the MAIN test goes RED. The main test's green depends on the atomic path;
  it is not green-regardless. 60 concurrent short appends is sufficient — the sabotaged
  variant collapsed to 1 line, i.e. the harness surfaces tearing/loss immediately when present.

## 3. Does part (b) run real tick.sh and is it meaningful?

Part (b) (lines 52–62) bootstraps a real project via `plugin/bootstrap.sh`, fires 8 concurrent
`bash .hb/tick.sh`, then asserts every `events.jsonl` line `json.loads`. I verified a fresh
project's tick is NOT a no-op: on a fresh bootstrap, one tick appends
`{"ts":...,"event":"wake","task":"P0T1"}` to `events.jsonl` (observed directly). So (b)
exercises a real unlocked append path — it would catch corruption from real tick.sh, not
pass vacuously.

## 4. Is the CLAIM honest, or an overclaim?

- **PIPE_BUF:** worst-case tick.sh event line is a `wake`/`lease_expired`/`review_wake` or a
  `log_event "<name>"`. Longest event names are `unsanctioned_drift`, `circuit_breaker_tripped`,
  `architecture_frozen`; a sample `wake` line is **59 bytes**. Task ids come from the DAG
  (short, e.g. `P0T1`). No realistic line approaches PIPE_BUF (4096), so O_APPEND atomicity
  genuinely applies. No tearing risk.
- **All EVENTS writes in tick.sh** (`grep '>>|> ' … EVENTS`): exactly lines
  **72 / 181 / 338 / 388**, all `>>` (append), none truncating (`>`). Matches the claimed 4 sites.
- **STATE writes in tick.sh:** none direct. state.json is only rewritten via `node hb.js rebuild`
  (tick.sh lines 150, 185), and `rebuild` in `hb.js` is `withWlock(() => reproject())`
  (hb.js:528–531) — i.e. the state.json RMW is under the wlock, exactly as claimed. Other `>`
  writes in tick.sh target flag/counter files (`$ARCH_HASH`, `$GBTICKS_FILE`, `$ROT_FLAG`),
  not events.jsonl / state.json, so they're outside the claim's scope and harmless.
- `hb.js mutate` appends via `fs.appendFileSync` inside `withWlock`; tick's raw `>>` is also
  O_APPEND. Both use O_APPEND, so a tick append concurrent with an hb.js mutate cannot tear the
  log; the lock only serializes the reproject (state.json write), which is precisely the claim.

## 5. Docs honesty

`parity-notes.md` §"Write-lock scope" (lines 77–93) states the lock guards *exactly* the
state.json RMW, explicitly lists the 4 lock-free tick.sh append sites (72/181/338/388), and
**explicitly says the docs do NOT claim "all writes are locked."** It correctly attributes
safety to O_APPEND (< PIPE_BUF 4096) + reproject being a full re-fold. `dev-plugin.md`
(117–118) and `dev-python.md` (45) both agree and cross-reference this section. No overclaim,
no misstatement.

## 6. Full node suite

`HB_NO_GIT=1 bash tests/run-tests.sh` → **`RESULT: 359 passed, 0 failed` / `✅ ALL GREEN`**.
T140 is wired at `tests/run-tests.sh:1532–1538` (T140.1 main + T140.2 selftest teeth).

## Conclusion

The GATE_LK / tick-append-safe claim about write-lock scope is accurate and proven. The proof
uses the exact tick.sh idiom, has demonstrated teeth (selftest + my sabotage → RED), part (b)
exercises a real non-empty append path, the event lines are far under PIPE_BUF, the only
unlocked events.jsonl writes are the 4 O_APPEND sites, state.json is only written under wlock,
and the docs are honest. Suite is 359/ALL GREEN. I cannot refute it.

VERDICT: SOUND
